#!/usr/bin/env python3
# agent.py by poligle
#
# Nilo's agent. The shell (home/shell/services/Nilo.qml) talks to it with one
# JSON object per line on stdin and stdout. It keeps the conversation, streams
# the replies from Ollama and runs the tools Nilo is allowed to use: search
# the web, read a page, a summary of this computer and, confirmed by the user
# every time, git add/commit/push in one repository. Nothing else: no shell,
# no writing files.
#
# Standard library only. home/nilo.nix wraps it with its configuration
# (Ollama's address, the models on offer, the store paths of ddgr and git);
# the settings chosen in the shell live in $XDG_STATE_HOME/nihil/nilo.json.
#
#   nilo-agent --config FILE [--state FILE]
#
# Requests (stdin)
#   {"op": "hello"}                          everything the shell needs to draw
#   {"op": "ask", "text": "..."}             a question
#   {"op": "stop"}                           stop the answer being written
#   {"op": "reset"}                          forget the conversation
#   {"op": "confirm", "id": "c1", "ok": true}
#   {"op": "set", "key": "model", "value": "qwen3.5:4b"}
#   {"op": "pull", "model": "..."}  {"op": "cancelPull"}  {"op": "delete", "model": "..."}
#   {"op": "warm"}                           load the model now (the user is typing)
#   {"op": "sleep"}                          unload it now
#   {"op": "status"}                         ask Ollama again
#
# Events (stdout): hello, settings, models, state, start, thinking, token,
# tool, confirm, confirmed, done, error, pull. Each carries "ev" and its fields.

import argparse
import datetime
import html.parser
import http.client
import ipaddress
import itertools
import json
import os
import pwd
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

PROTOCOL = 1
MAX_ROUNDS = 6          # model calls per question (each tool result needs one)
PAGE_CHARS = 6000       # text of a page handed to the model
DIFF_CHARS = 3000       # part of the diff git_status shows, for the commit message
CONFIRM_SECONDS = 300   # a confirmation nobody answers counts as "no"

DEFAULT_SETTINGS = {
    "onboarded": False,
    "model": "",
    "web": True,
    "system": True,
    "git": False,
    "repo": "~/nixos-config",
    "keepAlive": 5,
    "think": False,
}


def log(*parts):
    try:
        print("nilo:", *parts, file=sys.stderr, flush=True)
    except (OSError, ValueError):
        pass


class Output:
    """One JSON object per line on stdout, from any thread."""

    def __init__(self, stream):
        self.stream = stream
        self.lock = threading.Lock()

    def __call__(self, ev, **fields):
        line = json.dumps({"ev": ev, **fields}, ensure_ascii=False)
        with self.lock:
            try:
                self.stream.write(line + "\n")
                self.stream.flush()
            except (BrokenPipeError, ValueError):
                os._exit(0)  # the shell has gone


# --- Ollama -----------------------------------------------------------------------

class OllamaError(Exception):
    def __init__(self, code, detail=""):
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


class Cancel:
    """Stops a streamed request from another thread: shutting the socket down
    wakes the blocked read, and Ollama stops generating when the client goes."""

    def __init__(self):
        self.cancelled = False
        self.conn = None
        self.lock = threading.Lock()

    def attach(self, conn):
        with self.lock:
            self.conn = conn

    def detach(self, conn):
        with self.lock:
            if self.conn is conn:
                self.conn = None

    def cancel(self):
        with self.lock:
            self.cancelled = True
            sock = self.conn.sock if self.conn else None
        if sock:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


class Ollama:
    def __init__(self, base):
        url = urllib.parse.urlsplit(base)
        self.host = url.hostname or "127.0.0.1"
        self.port = url.port or 11434

    def _error(self, status, raw):
        try:
            message = json.loads(raw).get("error", "")
        except (ValueError, AttributeError):
            message = raw.decode("utf-8", "replace") if isinstance(raw, bytes) else str(raw)
        message = str(message).strip()
        if status == 404 or "not found" in message:
            return OllamaError("model-missing", message)
        if "does not support tools" in message:
            return OllamaError("no-tools", message)
        if "more system memory" in message or "out of memory" in message:
            return OllamaError("memory", message)
        return OllamaError("ollama", message or f"HTTP {status}")

    def request(self, method, path, body=None, timeout=10):
        conn = http.client.HTTPConnection(self.host, self.port, timeout=timeout)
        try:
            data = json.dumps(body).encode() if body is not None else None
            headers = {"Content-Type": "application/json"} if data is not None else {}
            conn.request(method, path, body=data, headers=headers)
            resp = conn.getresponse()
            raw = resp.read()
            if resp.status >= 400:
                raise self._error(resp.status, raw)
            return json.loads(raw) if raw.strip() else {}
        except (OSError, http.client.HTTPException) as e:
            raise OllamaError("ollama-down", str(e)) from e
        except ValueError as e:
            raise OllamaError("ollama", f"bad reply: {e}") from e
        finally:
            conn.close()

    def stream(self, path, body, cancel, timeout=600):
        """POST and yield every JSON line of the streamed reply."""
        conn = http.client.HTTPConnection(self.host, self.port, timeout=timeout)
        cancel.attach(conn)
        try:
            try:
                conn.request("POST", path, body=json.dumps(body).encode(),
                             headers={"Content-Type": "application/json"})
                resp = conn.getresponse()
            except (OSError, http.client.HTTPException) as e:
                if cancel.cancelled:
                    return
                raise OllamaError("ollama-down", str(e)) from e
            if resp.status >= 400:
                raise self._error(resp.status, resp.read())
            while not cancel.cancelled:
                try:
                    line = resp.readline()
                except (OSError, http.client.HTTPException, ValueError) as e:
                    if cancel.cancelled:
                        return
                    raise OllamaError("ollama", f"connection lost: {e}") from e
                if not line:
                    return
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                if "error" in obj:
                    raise self._error(500, line)
                yield obj
        finally:
            cancel.detach(conn)
            conn.close()

    def ps(self):
        return self.request("GET", "/api/ps", timeout=4).get("models", [])

    def tags(self):
        return self.request("GET", "/api/tags", timeout=6).get("models", [])

    def load(self, model, keep_alive, options):
        return self.request("POST", "/api/generate", {
            "model": model, "keep_alive": keep_alive, "options": options, "stream": False,
        }, timeout=900)

    def unload(self, model):
        return self.request("POST", "/api/generate", {"model": model, "keep_alive": 0, "stream": False}, timeout=30)

    def delete(self, model):
        return self.request("DELETE", "/api/delete", {"model": model}, timeout=30)


def parse_time(text):
    """Go's RFC 3339 with nanoseconds, as epoch seconds (None if it can't)."""
    if not text:
        return None
    m = re.match(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?(Z|[+-]\d\d:\d\d)?$", text)
    if not m:
        return None
    frac = (m.group(2) or ".0")[:7]
    zone = m.group(3) or "Z"
    if zone == "Z":
        zone = "+00:00"
    try:
        return datetime.datetime.fromisoformat(m.group(1) + frac + zone).timestamp()
    except ValueError:
        return None


# --- Pages ------------------------------------------------------------------------

class FetchError(Exception):
    pass


def check_public(url):
    """Only http(s) to public addresses: the model must not reach this machine
    or the local network (a page could tell it to)."""
    parts = urllib.parse.urlsplit(url)
    if parts.scheme not in ("http", "https") or not parts.hostname:
        raise FetchError("only http and https addresses")
    try:
        infos = socket.getaddrinfo(parts.hostname, parts.port or (443 if parts.scheme == "https" else 80),
                                   type=socket.SOCK_STREAM)
    except socket.gaierror as e:
        raise FetchError(f"cannot resolve {parts.hostname}") from e
    for info in infos:
        address = ipaddress.ip_address(info[4][0].split("%")[0])
        if not address.is_global:
            raise FetchError("that address is local or private")


class PublicRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        check_public(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url, language, limit=2_000_000, timeout=15):
    check_public(url)
    opener = urllib.request.build_opener(PublicRedirects)
    accept_language = "es-ES,es;q=0.9,en;q=0.7" if language == "es" else "en;q=0.9,es;q=0.5"
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Nilo/1 (NIHIL assistant)",
        "Accept": "text/html,application/xhtml+xml,text/plain,application/json;q=0.9,*/*;q=0.5",
        "Accept-Language": accept_language,
    })
    try:
        with opener.open(req, timeout=timeout) as resp:
            raw = resp.read(limit + 1)
            ctype = resp.headers.get_content_type()
            charset = resp.headers.get_content_charset()
            final = resp.geturl()
    except urllib.error.HTTPError as e:
        raise FetchError(f"HTTP {e.code}") from e
    except (urllib.error.URLError, OSError, http.client.HTTPException) as e:
        raise FetchError(str(getattr(e, "reason", e))) from e
    return final, ctype, charset, raw[:limit]


class TextOfPage(html.parser.HTMLParser):
    SKIP = {"script", "style", "noscript", "svg", "template", "iframe", "nav", "aside", "footer", "form", "button", "select"}
    BLOCK = {"p", "div", "br", "li", "tr", "section", "article", "header", "main", "h1", "h2", "h3", "h4", "h5", "h6",
             "ul", "ol", "table", "pre", "blockquote", "dd", "dt", "figcaption", "hr"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.title = ""
        self.skip = 0
        self.in_title = False

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self.skip += 1
        elif tag == "title":
            self.in_title = True
        elif tag in self.BLOCK:
            self.parts.append("\n- " if tag == "li" else "\n")

    def handle_startendtag(self, tag, attrs):
        if tag in ("br", "hr"):
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in self.SKIP:
            self.skip = max(0, self.skip - 1)
        elif tag == "title":
            self.in_title = False
        elif tag in self.BLOCK:
            self.parts.append("\n")

    def handle_data(self, data):
        if self.in_title:
            self.title += data
        elif not self.skip:
            self.parts.append(data)

    def text(self):
        text = "".join(self.parts)
        text = re.sub(r"[ \t\r\f\v\u00a0]+", " ", text)
        text = re.sub(r" *\n *", "\n", text)
        text = re.sub(r"\n(- \n)+", "\n", text)
        text = re.sub(r"\n{2,}", "\n", text)
        return text.strip()


def page_text(ctype, charset, raw):
    if ctype in ("text/html", "application/xhtml+xml"):
        if not charset:
            m = re.search(rb"<meta[^>]+charset=[\"']?([A-Za-z0-9_-]+)", raw[:4096], re.I)
            charset = m.group(1).decode() if m else "utf-8"
        try:
            decoded = raw.decode(charset, "replace")
        except LookupError:
            decoded = raw.decode("utf-8", "replace")
        parser = TextOfPage()
        try:
            parser.feed(decoded)
            parser.close()
        except Exception:  # html.parser is lenient; keep whatever it gathered
            pass
        return re.sub(r"\s+", " ", parser.title).strip(), parser.text()
    if ctype.startswith("text/") or ctype in ("application/json", "application/xml"):
        return "", raw.decode(charset or "utf-8", "replace").strip()
    raise FetchError(f"cannot read {ctype}")


def clip(text, limit):
    return text if len(text) <= limit else text[:limit].rstrip() + " …"


# --- Tools ------------------------------------------------------------------------

def schema(name, description, properties=None, required=()):
    return {"type": "function", "function": {
        "name": name, "description": description,
        "parameters": {"type": "object", "properties": properties or {}, "required": list(required)},
    }}


SCHEMAS = {
    "web_search": ("web", schema(
        "web_search",
        "Search the web. Use it for anything current or that you are not sure about. Returns titles, links and snippets.",
        {"query": {"type": "string", "description": "What to search for, as you would type it in a search engine"},
         "max_results": {"type": "integer", "description": "How many results, 1 to 8 (default 5)"}},
        ["query"])),
    "open_url": ("web", schema(
        "open_url",
        "Read a web page (usually one from web_search) and get its text.",
        {"url": {"type": "string", "description": "The full http(s) address"}},
        ["url"])),
    "system_info": ("system", schema(
        "system_info",
        "Facts about this computer: NixOS version and generation, kernel, CPU, memory, disk, battery and uptime.")),
    "git_status": ("git", schema(
        "git_status",
        "State of the user's repository: branch, changed files, a short diff and the latest commit messages.")),
    "git_commit": ("git", schema(
        "git_commit",
        "Stage every change, commit it with the message and push it (git add -A, commit, push). The user sees "
        "exactly what will happen and confirms it before anything runs. Look at git_status first.",
        {"message": {"type": "string", "description": "The commit message, in the style of the repository's latest commits"},
         "push": {"type": "boolean", "description": "Also push to the remote (default true)"}},
        ["message"])),
}


class Tools:
    def __init__(self, agent):
        self.agent = agent
        self.config = agent.config

    def schemas(self, settings):
        return [s for access, s in SCHEMAS.values() if settings.get(access)]

    def run(self, name, args, cancel):
        """Run one tool: (result for the model, facts for the shell)."""
        entry = SCHEMAS.get(name)
        if not entry:
            return {"error": f"there is no tool called {name}"}, {"ok": False}
        if not self.agent.settings.get(entry[0]):
            return {"error": f"{name} is not allowed in Nilo's settings"}, {"ok": False}
        if not isinstance(args, dict):
            args = {}
        try:
            result = getattr(self, name)(cancel=cancel, **{k: v for k, v in args.items() if k in
                                          SCHEMAS[name][1]["function"]["parameters"]["properties"]})
        except subprocess.TimeoutExpired:
            result = {"error": "it took too long"}
        except Exception as e:  # a tool must never take the agent down
            log(f"{name} failed:", repr(e))
            result = {"error": str(e) or e.__class__.__name__}
        return result, self.facts(name, result)

    @staticmethod
    def facts(name, result):
        ok = "error" not in result and not result.get("declined")
        facts = {"ok": ok}
        if name == "web_search" and ok:
            facts["count"] = len(result.get("results", []))
        elif name == "open_url" and ok:
            facts["title"] = result.get("title", "")
            facts["host"] = urllib.parse.urlsplit(result.get("url", "")).hostname or ""
        elif name == "git_status" and ok:
            facts["changes"] = len(result.get("changes", [])) + result.get("more", 0)
            facts["branch"] = result.get("branch", "")
        elif name == "git_commit":
            facts["declined"] = bool(result.get("declined"))
            facts["commit"] = result.get("commit", "")
            facts["pushed"] = bool(result.get("pushed"))
        if "error" in result:
            facts["error"] = str(result["error"])[:200]
        return facts

    # web

    def web_search(self, query, max_results=5, cancel=None):
        # ddgr opens a browser for a "!bang" (a "!" in the first two characters).
        query = re.sub(r"\s+", " ", str(query or "").replace("!", " ")).strip()[:200]
        if not query:
            return {"error": "empty query"}
        try:
            count = max(1, min(8, int(max_results)))
        except (TypeError, ValueError):
            count = 5
        language = self.config.get("language", "en")
        if self.config.get("searxng"):
            url = self.config["searxng"].rstrip("/") + "/search?" + urllib.parse.urlencode(
                {"q": query, "format": "json", "language": language})
            parts = urllib.parse.urlsplit(url)
            if parts.scheme not in ("http", "https"):
                return {"error": "the SearXNG address must be http(s)"}
            req = urllib.request.Request(url, headers={"Accept": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=20) as resp:
                    data = json.loads(resp.read(2_000_000))
            except (urllib.error.URLError, OSError, ValueError) as e:
                return {"error": f"search failed: {getattr(e, 'reason', e)}"}
            items = [{"title": r.get("title", ""), "url": r.get("url", ""), "snippet": r.get("content", "")}
                     for r in data.get("results", [])]
        else:
            region = "es-es" if language == "es" else "us-en"
            proc = subprocess.run([self.config["ddgr"], "--json", "-n", str(count), "-r", region, "--", query],
                                  stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
            if proc.returncode != 0:
                return {"error": "search failed", "detail": proc.stderr.strip()[-300:]}
            try:
                data = json.loads(proc.stdout or "[]")
            except ValueError:
                return {"error": "search failed", "detail": proc.stdout.strip()[-300:]}
            items = [{"title": r.get("title", ""), "url": r.get("url", ""), "snippet": r.get("abstract", "")}
                     for r in data if isinstance(r, dict)]
        results = [dict(r, snippet=clip(re.sub(r"\s+", " ", r["snippet"]).strip(), 300)) for r in items if r["url"]]
        return {"query": query, "results": results[:count]}

    def open_url(self, url, cancel=None):
        try:
            final, ctype, charset, raw = fetch(str(url or "").strip(), self.config.get("language", "en"))
            title, text = page_text(ctype, charset, raw)
        except FetchError as e:
            return {"error": str(e)}
        if not text:
            return {"error": "the page has no text (it may need JavaScript)"}
        return {"url": final, "title": title, "text": clip(text, PAGE_CHARS)}

    # system

    def system_info(self, cancel=None):
        info = {"hostname": socket.gethostname(), "kernel": os.uname().release}
        try:
            with open("/etc/os-release") as f:
                fields = dict(line.rstrip("\n").split("=", 1) for line in f if "=" in line)
            info["os"] = fields.get("PRETTY_NAME", "").strip('"')
        except OSError:
            pass
        try:
            link = os.readlink("/nix/var/nix/profiles/system")
            m = re.match(r"system-(\d+)-link", link)
            if m:
                built = os.lstat("/nix/var/nix/profiles/" + link).st_mtime
                info["generation"] = int(m.group(1))
                info["generationBuilt"] = datetime.datetime.fromtimestamp(built).strftime("%Y-%m-%d %H:%M")
        except OSError:
            pass
        try:
            with open("/proc/cpuinfo") as f:
                model = next((line.split(":", 1)[1].strip() for line in f if line.startswith("model name")), "")
            info["cpu"] = f"{model} ({os.cpu_count()} threads)" if model else f"{os.cpu_count()} threads"
        except OSError:
            pass
        mem = meminfo()
        if mem:
            info["memory"] = {"totalGB": round(mem.get("MemTotal", 0) / 1048576, 1),
                              "availableGB": round(mem.get("MemAvailable", 0) / 1048576, 1),
                              "swapUsedGB": round((mem.get("SwapTotal", 0) - mem.get("SwapFree", 0)) / 1048576, 1)}
        disks = {}
        for label, path in (("/", "/"), ("home", os.path.expanduser("~"))):
            try:
                usage = shutil.disk_usage(path)
                disks[label] = {"freeGB": round(usage.free / 1e9, 1), "totalGB": round(usage.total / 1e9, 1)}
            except OSError:
                pass
        if disks:
            info["disk"] = disks
        supplies = "/sys/class/power_supply"
        batteries = sorted(p for p in os.listdir(supplies) if p.startswith("BAT")) if os.path.isdir(supplies) else []
        for bat in batteries:
            try:
                with open(f"{supplies}/{bat}/capacity") as f:
                    capacity = int(f.read().strip())
                with open(f"{supplies}/{bat}/status") as f:
                    status = f.read().strip()
                info["battery"] = {"percent": capacity, "status": status}
                break
            except (OSError, ValueError):
                continue
        try:
            with open("/proc/uptime") as f:
                seconds = int(float(f.read().split()[0]))
            info["uptime"] = f"{seconds // 86400}d {seconds % 86400 // 3600}h {seconds % 3600 // 60}m"
        except (OSError, ValueError, IndexError):
            pass
        info["load"] = [round(x, 2) for x in os.getloadavg()]
        return info

    # git

    def repo(self):
        path = os.path.expanduser(str(self.agent.settings.get("repo") or "~/nixos-config"))
        if not os.path.isdir(path):
            raise RuntimeError(f"{self.agent.settings.get('repo')} does not exist")
        return path

    def git(self, repo, *args, timeout=20):
        env = dict(os.environ, GIT_TERMINAL_PROMPT="0", LC_ALL="C", GIT_OPTIONAL_LOCKS="0")
        proc = subprocess.run([self.config.get("git", "git"), "-C", repo, *args], stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=timeout, env=env)
        return proc.returncode, proc.stdout, proc.stderr

    def git_status(self, cancel=None):
        repo = self.repo()
        code, top, err = self.git(repo, "rev-parse", "--show-toplevel")
        if code != 0:
            return {"error": f"{self.agent.settings.get('repo')} is not a git repository"}
        _, branch, _ = self.git(repo, "rev-parse", "--abbrev-ref", "HEAD")
        code, upstream, _ = self.git(repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
        upstream = upstream.strip() if code == 0 else None
        ahead = behind = 0
        if upstream:
            code, counts, _ = self.git(repo, "rev-list", "--left-right", "--count", "HEAD...@{u}")
            if code == 0 and len(counts.split()) == 2:
                ahead, behind = (int(x) for x in counts.split())
        _, porcelain, _ = self.git(repo, "status", "--porcelain=v1", "-uall")
        changes = [line for line in porcelain.splitlines() if line.strip()]
        _, stat, _ = self.git(repo, "diff", "HEAD", "--stat", "--stat-width=100")
        _, diff, _ = self.git(repo, "diff", "HEAD", "-U1", "--no-color")
        _, recent, _ = self.git(repo, "log", "-6", "--pretty=%s")
        return {
            "repo": self.agent.settings.get("repo"),
            "branch": branch.strip(),
            "upstream": upstream,
            "ahead": ahead,
            "behind": behind,
            "changes": changes[:40],
            "more": max(0, len(changes) - 40),
            "diffstat": stat.strip().splitlines()[-1] if stat.strip() else "",
            "diff": clip(diff, DIFF_CHARS),
            "recentCommits": [s for s in recent.splitlines() if s],
        }

    def git_commit(self, message, push=True, cancel=None):
        message = str(message or "").strip()
        if not message:
            return {"error": "the commit message is empty"}
        message = message[:2000]
        push = push is not False and str(push).lower() != "false"
        status = self.git_status()
        if "error" in status:
            return status
        repo = self.repo()
        changes = status["changes"]
        if not changes and not (push and status["ahead"] > 0):
            return {"error": "there is nothing to commit or push"}
        action = ("commit-push" if push else "commit") if changes else "push"
        _, remotes, _ = self.git(repo, "remote")
        remotes = remotes.split()
        if push and not status["upstream"] and "origin" not in remotes:
            return {"error": "the branch has no remote to push to"}
        ok = self.agent.ask_confirmation({
            "action": action,
            "repo": status["repo"],
            "branch": status["branch"],
            "remote": status["upstream"] or (f"origin/{status['branch']}" if push else ""),
            "files": changes[:30],
            "more": len(changes) - 30 + status["more"] if len(changes) > 30 else status["more"],
            "ahead": status["ahead"],
            "message": message if changes else "",
        }, cancel)
        if not ok:
            return {"declined": True, "note": "The user did not confirm. Nothing was done."}
        result = {"ok": True}
        if changes:
            code, _, err = self.git(repo, "add", "-A")
            if code != 0:
                return {"error": "git add failed", "detail": err.strip()[-400:]}
            code, out, err = self.git(repo, "commit", "-m", message)
            if code != 0:
                return {"error": "git commit failed", "detail": (err or out).strip()[-400:]}
            _, sha, _ = self.git(repo, "rev-parse", "--short", "HEAD")
            result["commit"] = sha.strip()
        if push:
            args = ["push"] if status["upstream"] else ["push", "-u", "origin", status["branch"]]
            code, out, err = self.git(repo, *args, timeout=120)
            if code != 0:
                result.update(ok=False, pushed=False, error="git push failed", detail=(err or out).strip()[-400:])
                return result
            result["pushed"] = True
            result["output"] = (err or out).strip()[-300:]
        return result


def meminfo():
    values = {}
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                key, _, rest = line.partition(":")
                parts = rest.split()
                if parts and parts[0].isdigit():
                    values[key] = int(parts[0])  # kB
    except OSError:
        pass
    return values


# --- The prompt -------------------------------------------------------------------

DAYS = {
    "es": ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"],
    "en": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
}
MONTHS = {
    "es": ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
           "noviembre", "diciembre"],
    "en": ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
           "November", "December"],
}

PROMPT = {
    "es": {
        "intro": "Eres Nilo, el asistente de NIHIL, el escritorio de {user} en NixOS. Funcionas en este ordenador con "
                 "{model} (Ollama): lo que se habla aquí no sale de él{web}.",
        "webOut": ", salvo las búsquedas que hagas en internet",
        "now": "Ahora es {weekday}, {day} de {month} de {year}, las {time}.",
        "rules": [
            "Responde en español, claro y breve; ve al grano. Markdown sencillo: párrafos cortos, listas, "
            "**negrita**, `código`.",
            "Si no sabes algo con seguridad, dilo. No inventes datos, cifras, comandos ni enlaces.",
        ],
        "web": "Para lo que cambia con el tiempo (noticias, precios, versiones, el tiempo, horarios) o lo que no "
               "sepas, busca con web_search y lee con open_url si hace falta. Termina con las fuentes como enlaces "
               "Markdown.",
        "noWeb": "No tienes acceso a internet: si algo puede haber cambiado, dilo.",
        "system": "system_info te da datos reales de este ordenador (NixOS, memoria, disco, batería).",
        "git": "El repositorio es {repo}. Si te piden guardar o subir los cambios: mira git_status, escribe un "
               "mensaje de commit breve en el estilo de los últimos y llama a git_commit. El usuario lo confirma "
               "antes de que se ejecute. No hagas nada más con git.",
        "limits": "No puedes editar archivos ni ejecutar comandos: si te lo piden, explica cómo hacerlo.",
        "about": "NIHIL: SUPER+Espacio abre el launcher (> acciones, = calculadora, ? tú); SUPER+D el dashboard; "
                 "SUPER+P los ajustes; {summon} te abren a ti. La configuración está en {flake} y se aplica con "
                 "`sudo nixos-rebuild switch --flake {flake}#{host}`.",
        "summon": "SUPER+I y la tecla Copilot",
    },
    "en": {
        "intro": "You are Nilo, the assistant of NIHIL, {user}'s NixOS desktop. You run on this computer with {model} "
                 "(Ollama): what is said here never leaves it{web}.",
        "webOut": ", except the web searches you make",
        "now": "It is {weekday}, {month} {day}, {year}, {time}.",
        "rules": [
            "Answer in English, clearly and briefly; get to the point. Simple Markdown: short paragraphs, lists, "
            "**bold**, `code`.",
            "If you are not sure about something, say so. Never make up facts, figures, commands or links.",
        ],
        "web": "For anything that changes over time (news, prices, versions, weather, timetables) or that you don't "
               "know, search with web_search and read with open_url if needed. End with the sources as Markdown "
               "links.",
        "noWeb": "You have no internet access: if something may have changed, say so.",
        "system": "system_info gives you real facts about this computer (NixOS, memory, disk, battery).",
        "git": "The repository is {repo}. When asked to save or push the changes: look at git_status, write a short "
               "commit message in the style of the latest ones and call git_commit. The user confirms it before it "
               "runs. Do nothing else with git.",
        "limits": "You cannot edit files or run commands: if asked to, explain how to do it.",
        "about": "NIHIL: SUPER+Space opens the launcher (> actions, = calculator, ? you); SUPER+D the dashboard; "
                 "SUPER+P the settings; {summon} open you. The configuration lives in {flake} and is applied with "
                 "`sudo nixos-rebuild switch --flake {flake}#{host}`.",
        "summon": "SUPER+I and the Copilot key",
    },
}


def build_prompt(config, settings, now=None):
    language = config.get("language", "en") if config.get("language") in PROMPT else "en"
    text = PROMPT[language]
    now = now or datetime.datetime.now()
    try:
        user = pwd.getpwuid(os.getuid()).pw_name
    except KeyError:
        user = os.environ.get("USER", "")
    lines = [
        text["intro"].format(user=user, model=settings["model"], web=text["webOut"] if settings["web"] else ""),
        text["now"].format(weekday=DAYS[language][now.weekday()], day=now.day, month=MONTHS[language][now.month - 1],
                           year=now.year, time=now.strftime("%H:%M")),
        "",
    ]
    rules = list(text["rules"])
    rules.append(text["web"] if settings["web"] else text["noWeb"])
    if settings["system"]:
        rules.append(text["system"])
    if settings["git"]:
        rules.append(text["git"].format(repo=settings["repo"]))
    rules.append(text["limits"])
    lines += [f"- {rule}" for rule in rules]
    lines += ["", text["about"].format(summon=config.get("summon") or text["summon"],
                                       flake=config.get("flake", "~/nixos-config"), host=config.get("host", ""))]
    return "\n".join(lines)


# --- The agent --------------------------------------------------------------------

class Agent:
    def __init__(self, config, state_path, out):
        self.config = config
        self.state_path = state_path
        self.out = out
        self.ollama = Ollama(config.get("ollama", "http://127.0.0.1:11434"))
        self.tools = Tools(self)
        self.ram_gb = round(meminfo().get("MemTotal", 0) / 1048576, 1)
        self.settings = self.load_settings()
        self.history = []
        self.lock = threading.Lock()
        self.turn = None            # Cancel of the answer being written
        self.pulling = None         # (model, Cancel)
        self.confirms = {}          # id -> [Event, answer]
        self.ids = itertools.count(1)
        self.no_tools = False       # the model said it can't use tools
        self.state = {"ollama": None, "loaded": False, "loading": False, "model": "", "expires": None,
                      "sizeGB": 0, "gpu": 0}
        self.state_lock = threading.Lock()
        self.wake = threading.Event()

    # settings

    def recommended(self):
        models = self.config.get("models", [])
        if not models:
            return ""
        budget = self.ram_gb * 0.45
        fitting = [m for m in models if m.get("ram", 0) <= budget]
        return (max(fitting, key=lambda m: m.get("ram", 0)) if fitting else models[0])["tag"]

    def load_settings(self):
        settings = dict(DEFAULT_SETTINGS)
        try:
            with open(self.state_path) as f:
                saved = json.load(f)
            for key, value in saved.items():
                if key in settings and type(value) is type(DEFAULT_SETTINGS[key]):
                    settings[key] = value
        except (OSError, ValueError, AttributeError):
            pass
        if not settings["model"]:
            settings["model"] = self.recommended()
        return settings

    def save_settings(self):
        try:
            os.makedirs(os.path.dirname(self.state_path), exist_ok=True)
            tmp = self.state_path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(self.settings, f, indent=2)
            os.replace(tmp, self.state_path)
        except OSError as e:
            log("cannot save settings:", e)

    def set(self, key, value):
        if key not in DEFAULT_SETTINGS:
            return self.out("error", code="bad-request", detail=f"unknown setting {key}")
        kind = type(DEFAULT_SETTINGS[key])
        if kind is bool:
            value = bool(value)
        elif kind is int:
            try:
                value = max(1, min(120, int(value)))
            except (TypeError, ValueError):
                return self.out("error", code="bad-request", detail=f"{key} must be a number")
        else:
            value = str(value or "").strip()
            if key == "model" and not re.fullmatch(r"[\w.\-/]+(:[\w.\-]+)?", value):
                return self.out("error", code="bad-request", detail="not a model name")
            if key == "repo":
                value = value or DEFAULT_SETTINGS["repo"]
                if not os.path.isdir(os.path.join(os.path.expanduser(value), ".git")):
                    self.out("settings", settings=self.settings)
                    return self.out("error", code="bad-repo", detail=value)
        old = self.settings.get(key)
        self.settings[key] = value
        self.save_settings()
        self.out("settings", settings=self.settings)
        if key == "model" and old != value:
            self.no_tools = False
            if self.state["loaded"] and old:
                threading.Thread(target=self.quietly, args=(self.ollama.unload, old), daemon=True).start()
            self.wake.set()
        elif key == "keepAlive" and self.state["loaded"]:
            threading.Thread(target=self.warm, daemon=True).start()

    def quietly(self, fn, *args):
        try:
            fn(*args)
        except OllamaError as e:
            log(fn.__name__, "failed:", e.detail or e.code)
        self.wake.set()

    # models and state

    def catalogue(self):
        try:
            installed = {m.get("name", ""): m for m in self.ollama.tags()}
        except OllamaError:
            installed = None
        known = []
        for entry in self.config.get("models", []):
            tag = entry["tag"]
            known.append(dict(entry, installed=installed is not None and (tag in installed or f"{tag}:latest" in installed)))
        tags = {m["tag"] for m in known}
        for name, m in sorted((installed or {}).items()):
            if name not in tags and name.removesuffix(":latest") not in tags:
                known.append({"tag": name, "label": name, "size": round(m.get("size", 0) / 1e9, 1), "ram": 0,
                              "installed": True, "extra": True})
        current = self.settings["model"]
        if current and current not in {m["tag"] for m in known}:
            known.append({"tag": current, "label": current, "size": 0, "ram": 0, "installed": False, "extra": True})
        return {"models": known, "recommended": self.recommended(), "ramGB": self.ram_gb,
                "ollama": installed is not None}

    def send_models(self):
        self.out("models", **self.catalogue())

    def refresh_state(self):
        model = self.settings["model"]
        state = {"model": model}
        try:
            running = self.ollama.ps()
            state["ollama"] = True
            mine = next((m for m in running if m.get("name") == model or m.get("model") == model
                         or m.get("name") == f"{model}:latest"), None)
            state["loaded"] = mine is not None
            if mine:
                state["loading"] = False
                state["model"] = model
                state["expires"] = parse_time(mine.get("expires_at"))
                size = mine.get("size", 0)
                state["sizeGB"] = round(size / 1e9, 1)
                state["gpu"] = round(100 * mine.get("size_vram", 0) / size) if size else 0
            else:
                state["expires"] = None
        except OllamaError:
            state.update(ollama=False, loaded=False, expires=None)
        was = self.state["ollama"]
        self.set_state(**state)
        # Ollama came up after the agent (at boot): what is installed now.
        if state["ollama"] and was is False:
            self.send_models()

    def set_state(self, **changes):
        with self.state_lock:
            state = dict(self.state, **changes)
            if state == self.state:
                return
            self.state = state
            self.out("state", **state)

    def poll(self):
        """Keep `state` true to Ollama: check again when the model should have
        gone to sleep, and now and then in case Ollama came up later."""
        while True:
            self.refresh_state()
            if self.state["loaded"] and self.state["expires"]:
                delay = max(2.0, min(30.0, self.state["expires"] - time.time() + 1.5))
            elif self.state["loading"]:
                delay = 3.0
            else:
                delay = 15.0 if not self.state["ollama"] else 60.0
            self.wake.wait(delay)
            self.wake.clear()

    def options(self):
        return {"num_ctx": int(self.config.get("contextLength", 16384))}

    def keep_alive(self):
        return f"{int(self.settings['keepAlive'])}m"

    def warm(self):
        model = self.settings["model"]
        if not model or self.state["loading"]:
            return
        if not self.state["loaded"]:
            self.set_state(loading=True)
        try:
            self.ollama.load(model, self.keep_alive(), self.options())
            # Straight from "loading" to "loaded", without looking asleep in between.
            self.refresh_state()
        except OllamaError as e:
            if e.code != "ollama-down":
                log("warm:", e.detail or e.code)
        finally:
            self.set_state(loading=False)
            self.wake.set()

    def sleep(self):
        if self.state["loaded"] and self.settings["model"]:
            self.quietly(self.ollama.unload, self.settings["model"])

    # downloads

    def pull(self, model):
        if self.pulling:
            return self.out("pull", model=model, status="busy")
        cancel = Cancel()
        self.pulling = (model, cancel)
        threading.Thread(target=self._pull, args=(model, cancel), daemon=True).start()

    def _pull(self, model, cancel):
        layers = {}
        last = 0.0
        status = "error"
        detail = ""
        try:
            self.out("pull", model=model, status="starting", completed=0, total=0)
            for p in self.ollama.stream("/api/pull", {"model": model, "stream": True}, cancel, timeout=120):
                if p.get("digest") and p.get("total"):
                    layers[p["digest"]] = (p.get("completed", 0), p["total"])
                status = p.get("status", "")
                now = time.monotonic()
                if status == "success" or now - last > 0.25:
                    last = now
                    done = sum(c for c, _ in layers.values())
                    total = sum(t for _, t in layers.values())
                    self.out("pull", model=model, status=status, completed=done, total=total)
            if cancel.cancelled:
                status = "cancelled"
        except OllamaError as e:
            status, detail = "error", e.detail or e.code
        finally:
            self.pulling = None
        if status != "success":
            self.out("pull", model=model, status=status if status in ("cancelled", "error") else "error",
                     detail=detail or status)
        self.send_models()
        self.wake.set()

    def cancel_pull(self):
        if self.pulling:
            self.pulling[1].cancel()

    def delete(self, model):
        if model == self.settings["model"] and self.state["loaded"]:
            self.quietly(self.ollama.unload, model)
        try:
            self.ollama.delete(model)
        except OllamaError as e:
            self.out("error", code=e.code, detail=e.detail)
        self.send_models()

    # the conversation

    def ask_confirmation(self, detail, cancel):
        cid = f"c{next(self.ids)}"
        event = threading.Event()
        self.confirms[cid] = [event, None]
        self.out("confirm", id=cid, **detail)
        deadline = time.monotonic() + CONFIRM_SECONDS
        while not event.wait(0.2):
            if (cancel and cancel.cancelled) or time.monotonic() > deadline:
                break
        answer = self.confirms.pop(cid, [None, None])[1] is True
        self.out("confirmed", id=cid, ok=answer)
        return answer

    def answer_confirmation(self, cid, ok):
        entry = self.confirms.get(cid)
        if entry:
            entry[1] = bool(ok)
            entry[0].set()

    def messages(self, history):
        system = build_prompt(self.config, self.settings)
        budget = int(self.config.get("contextLength", 16384) * 2.5) - len(system)
        history = list(history)

        def size(msgs):
            return sum(len(m.get("content", "")) + len(json.dumps(m.get("tool_calls", ""))) for m in msgs)

        # Drop whole exchanges from the start, never the question being answered.
        while size(history) > budget:
            later = [i for i, m in enumerate(history) if m["role"] == "user" and i > 0]
            if not later:
                break
            history = history[later[0]:]
        return [{"role": "system", "content": system}] + history

    def ask(self, text):
        text = str(text or "").strip()
        if not text:
            return
        with self.lock:
            if self.turn:
                return self.out("error", code="busy", detail="")
            self.turn = Cancel()
            cancel = self.turn
        threading.Thread(target=self._answer, args=(text, cancel), daemon=True).start()

    def _answer(self, text, cancel):
        # "done" goes out only once the agent can take the next question.
        ending = {"stats": {}}
        try:
            ending.update(self._turn(text, cancel, ending["stats"]))
        except OllamaError as e:
            self.out("error", code=e.code, detail=e.detail)
            ending["failed"] = True
        except Exception as e:  # never leave the shell waiting
            log("answer failed:", repr(e))
            self.out("error", code="internal", detail=str(e))
            ending["failed"] = True
        finally:
            with self.lock:
                self.turn = None
            self.out("done", **ending)
            self.wake.set()

    def _turn(self, text, cancel, stats):
        """One question: model calls and tools until it answers. Returns what
        "done" should add ({"cancelled": True} when stopped)."""
        model = self.settings["model"]
        # The conversation this question belongs to: "reset" starts a new list,
        # so an answer cut short by it lands in the old one.
        history = self.history
        history.append({"role": "user", "content": text})
        self.out("start", model=model)
        if not model:
            raise OllamaError("no-model")
        rounds = 0
        while rounds < MAX_ROUNDS:
            rounds += 1
            tools = [] if self.no_tools or rounds == MAX_ROUNDS else self.tools.schemas(self.settings)
            payload = {"model": model, "messages": self.messages(history), "stream": True,
                       "keep_alive": self.keep_alive(), "options": self.options(),
                       "think": bool(self.settings["think"])}
            if tools:
                payload["tools"] = tools
            if not self.state["loaded"]:
                self.set_state(loading=True)
            content, calls = "", []
            try:
                for chunk in self.ollama.stream("/api/chat", payload, cancel):
                    if self.state["loading"] or not self.state["loaded"]:
                        self.set_state(loading=False, loaded=True)
                    message = chunk.get("message") or {}
                    if message.get("thinking"):
                        self.out("thinking", text=message["thinking"])
                    if message.get("content"):
                        content += message["content"]
                        self.out("token", text=message["content"])
                    if message.get("tool_calls"):
                        calls.extend(message["tool_calls"])
                    if chunk.get("done"):
                        stats.update(tokens=chunk.get("eval_count", 0),
                                     seconds=round(chunk.get("eval_duration", 0) / 1e9, 2),
                                     prompt=chunk.get("prompt_eval_count", 0))
            except OllamaError as e:
                if e.code == "no-tools" and tools:
                    self.no_tools = True
                    rounds -= 1
                    continue
                raise
            finally:
                if self.state["loading"]:
                    self.set_state(loading=False)
            if cancel.cancelled:
                if content:
                    history.append({"role": "assistant", "content": content})
                return {"cancelled": True}
            reply = {"role": "assistant", "content": content}
            if calls:
                reply["tool_calls"] = calls
            history.append(reply)
            if not calls:
                return {}
            for call in calls:
                function = call.get("function") or {}
                name = function.get("name", "")
                args = function.get("arguments") or {}
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except ValueError:
                        args = {}
                tid = f"t{next(self.ids)}"
                self.out("tool", id=tid, name=name, args=args, status="running")
                result, facts = self.tools.run(name, args, cancel)
                self.out("tool", id=tid, name=name, status="done", **facts)
                message = {"role": "tool", "tool_name": name, "content": json.dumps(result, ensure_ascii=False)}
                if call.get("id"):
                    message["tool_call_id"] = call["id"]
                history.append(message)
                if cancel.cancelled:
                    return {"cancelled": True}
        return {}

    def stop(self):
        with self.lock:
            turn = self.turn
        if turn:
            turn.cancel()

    def reset(self):
        self.stop()
        self.history = []
        self.out("reset")

    # protocol

    def hello(self):
        self.out("hello", protocol=PROTOCOL, settings=self.settings, language=self.config.get("language", "en"),
                 **self.catalogue())
        self.wake.set()

    def handle(self, request):
        op = request.get("op")
        if op == "hello":
            self.hello()
        elif op == "ask":
            self.ask(request.get("text"))
        elif op == "stop":
            self.stop()
        elif op == "reset":
            self.reset()
        elif op == "confirm":
            self.answer_confirmation(request.get("id"), request.get("ok"))
        elif op == "set":
            self.set(request.get("key"), request.get("value"))
        elif op == "pull":
            self.pull(str(request.get("model") or self.settings["model"]))
        elif op == "cancelPull":
            self.cancel_pull()
        elif op == "delete":
            threading.Thread(target=self.delete, args=(str(request.get("model")),), daemon=True).start()
        elif op == "warm":
            threading.Thread(target=self.warm, daemon=True).start()
        elif op == "sleep":
            threading.Thread(target=self.sleep, daemon=True).start()
        elif op == "status":
            self.wake.set()
            threading.Thread(target=self.send_models, daemon=True).start()
        else:
            self.out("error", code="bad-request", detail=f"unknown op {op!r}")

    def run(self, stdin):
        threading.Thread(target=self.poll, daemon=True).start()
        for line in stdin:
            line = line.strip()
            if not line:
                continue
            try:
                request = json.loads(line)
                if not isinstance(request, dict):
                    raise ValueError("not an object")
            except ValueError as e:
                self.out("error", code="bad-request", detail=str(e))
                continue
            self.handle(request)


def main():
    parser = argparse.ArgumentParser(description="Nilo's agent for the NIHIL shell (JSON lines on stdin/stdout).")
    parser.add_argument("--config", required=True, help="configuration written by home/nilo.nix")
    parser.add_argument("--state", help="settings file (default $XDG_STATE_HOME/nihil/nilo.json)")
    args = parser.parse_args()
    with open(args.config) as f:
        config = json.load(f)
    state = args.state or os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
                                       "nihil", "nilo.json")
    for stream in (sys.stdin, sys.stdout):
        stream.reconfigure(encoding="utf-8", errors="replace")
    Agent(config, state, Output(sys.stdout)).run(sys.stdin)


if __name__ == "__main__":
    main()
