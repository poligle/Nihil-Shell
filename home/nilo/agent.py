#!/usr/bin/env python3
# agent.py by poligle
#
# Nilo's agent. The shell (home/shell/services/Nilo.qml) talks to it with one
# JSON object per line on stdin and stdout. It keeps the conversation, streams
# the replies from Ollama and runs the tools Nilo is allowed to use: search
# the web, read a page, a summary of this computer, open apps and, in the one
# repository it is given, git add/commit/push and reading and changing files.
# With the terminal allowed it also runs commands. Every commit, every change
# to a file and every command waits for the user to confirm it.
#
# Standard library only. home/nilo/default.nix wraps it with its configuration
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
#   {"op": "repos"}                          git repositories under ~, to choose one
#   {"op": "startOllama"}                    start ollama.service (it asks polkit)
#   {"op": "launched", "id": "c2", "ok": true, "name": "Spotify"}
#                                            the shell opened what open_app asked for
#   {"op": "notes"}                          the user's notes for Nilo (made if missing)
#
# Events (stdout): hello, settings, models, state, start, thinking, token,
# tool, output, confirm, confirmed, launch, done, error, pull, repos, ollama,
# notes. Each carries "ev" and its fields.
#
# What Nilo knows about the system and the rules it works by are in nilo.md
# (next to this file), added to the prompt with the user's own notes and the
# repository's NILO.md: see build_context.

import argparse
import datetime
import difflib
import html.parser
import http.client
import ipaddress
import itertools
import json
import os
import pwd
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

PROTOCOL = 1
MAX_ROUNDS = 8          # model calls per question (each tool result needs one)
PAGE_CHARS = 6000       # text of a page handed to the model
DIFF_CHARS = 3000       # part of the diff git_status shows, for the commit message
CONFIRM_SECONDS = 300   # a confirmation nobody answers counts as "no"
READ_LINES = 400        # lines of a file read_file hands over at a time
READ_CHARS = 16000      # and at most this much text
FILE_BYTES = 512_000    # the largest file Nilo reads or writes
LIST_FILES = 300        # names list_files shows
CARD_LINES = 80         # diff lines a confirmation shows
COMMAND_CHARS = 4000    # the longest command Nilo may run
COMMAND_SECONDS = 120   # a command running longer is stopped (the terminal has no limit)
OUTPUT_KEEP = 65536     # bytes of a command's output kept from its start, and from its end
OUTPUT_CHARS = 6000     # of which the model gets this much text
OUTPUT_LINES = 6        # the last lines the shell shows under the command
CONTEXT_CHARS = 9000    # nilo.md, the user's notes and the repository's NILO.md, together
PULL_ATTEMPTS = 4       # a download that breaks off is tried again (Ollama resumes it)
PULL_WAIT = 5           # seconds before the second attempt; then 20, 45
# What a model has to leave the rest of the machine: an eighth of the
# memory, never under 2 GB. A model bigger than the rest can't run here.
RESERVE_SHARE = 0.125
RESERVE_GB = 2.0

# Why a download failed, from Ollama's own words ("max retries exceeded: Get
# https://…r2.cloudflarestorage.com/…: EOF"). Network trouble and the
# registry's rate limit are worth another try; a full disk or a name the
# registry doesn't know are not.
PULL_ERRORS = [
    ("rate", r"(?i)\b429\b|too many requests|rate.?limit"),
    ("space", r"(?i)no space left"),
    ("missing", r"(?i)file does not exist|manifest unknown|pull model manifest: 404|not found"),
    ("network", r"(?i)max retries exceeded|connection (reset|refused|lost)|\beof\b|i/o timeout|timed out|"
                r"tls|no such host|temporary failure|network is unreachable|stream error|http2|dial tcp"),
]


def pull_error(detail):
    return next((code for code, pattern in PULL_ERRORS if re.search(pattern, str(detail or ""))), "")

DEFAULT_SETTINGS = {
    "onboarded": False,
    "model": "",
    "web": True,
    "system": True,
    "git": False,
    "write": False,
    "apps": True,
    "shell": False,
    "repo": "~/nixos-config",
    "keepAlive": 5,
    "think": False,
    "auto": False,
}

# Until another repository is chosen, Nilo works in NIHIL's own checkout:
# the one nihil dev builds from (its path is in DEV_FILE, modules/nihil-cli.nix),
# else the first of CHECKOUTS that is a git repository, else "repo" above.
DEV_FILE = "/var/lib/nihil/dev"
CHECKOUTS = ("~/nixos-config", "~/Nihil-Shell")


# Automatic model (setting "auto"): a question that looks simple goes to the
# smallest model downloaded, everything else to the one chosen. Simple means
# short, one question, no code and none of the words of the work that needs
# the big one (explaining, writing, files, git, commands, Nix).
DEMANDING = re.compile(
    r"(?i)(c[oó]digo|\bcode\b|script|programa|funci[oó]n|function|debug|error|traceback|\bnix|flake|config|"
    r"instal|commit|\bpush|\bgit\b|archivo|fichero|\bfiles?\b|repo|comando|command|terminal|ejecut|\brun\b|"
    r"compil|build|explica|explain|por ?qu[eé]|\bwhy\b|compar|anali[sz]|analy[sz]|resum|summar|paso a paso|"
    r"step by step|escrib|\bwrite|redact|traduc|translat|\bplan|dise[ñn]|design|calcul|demuestra|\bprove|"
    r"matem|\bmath|ecuaci|equation|ensayo|essay|informe|report|corrig|\bfix)")


def simple(text):
    text = str(text or "").strip()
    return (len(text) <= 140 and "\n" not in text and "```" not in text and text.count("?") <= 1
            and not DEMANDING.search(text))


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
    "list_files": ("write", schema(
        "list_files",
        "List the files of the user's repository, or of a folder in it (what git tracks, plus new files it doesn't ignore).",
        {"path": {"type": "string", "description": "A folder inside the repository, relative to it (default: all of it)"}})),
    "read_file": ("write", schema(
        "read_file",
        "Read a text file of the user's repository. Long files come in parts: ask again with from_line.",
        {"path": {"type": "string", "description": "The file, relative to the repository"},
         "from_line": {"type": "integer", "description": "First line to read (default 1)"}},
        ["path"])),
    "edit_file": ("write", schema(
        "edit_file",
        "Change a file of the repository by replacing one exact piece of its text. The user sees the change and "
        "confirms it before it is written. Read the file first and copy `old` exactly; it must appear only once.",
        {"path": {"type": "string", "description": "The file, relative to the repository"},
         "old": {"type": "string", "description": "The exact text to replace, with enough lines around it to be unique"},
         "new": {"type": "string", "description": "What goes in its place"}},
        ["path", "old", "new"])),
    "write_file": ("write", schema(
        "write_file",
        "Create a file in the repository, or replace all of its content. The user sees the change and confirms it "
        "before it is written. To change part of an existing file, use edit_file.",
        {"path": {"type": "string", "description": "The file, relative to the repository"},
         "content": {"type": "string", "description": "The whole new content of the file"}},
        ["path", "content"])),
    "open_app": ("apps", schema(
        "open_app",
        "Open an application on the desktop by its name (Spotify, Thunar, Zen…), or a file, a folder or a web "
        "address in the application that opens it.",
        {"target": {"type": "string", "description": "The app's name, an absolute path or an http(s) address"}},
        ["target"])),
    "run_command": ("shell", schema(
        "run_command",
        "Run a bash command on this computer and get its output. The user sees the exact command and confirms it "
        "before it runs: one command per call, and say in `reason` what it does and why. Commands that need a "
        "password (sudo), are interactive or take minutes go with terminal=true: they open in a terminal window "
        "for the user and you don't see their output.",
        {"command": {"type": "string", "description": "The command, as typed in bash"},
         "reason": {"type": "string", "description": "One short sentence for the user: what it does and why"},
         "cwd": {"type": "string", "description": "Folder to run it in (default: the repository, or ~)"},
         "terminal": {"type": "boolean", "description": "Open it in a terminal window instead (default false)"}},
        ["command", "reason"])),
}

# What makes a command worth a red card. The user confirms every command
# anyway; these say why this one deserves a second look.
RISKS = [
    ("root", r"(^|[;&|(\s])(sudo|doas|pkexec|run0)\s"),
    ("delete", r"(^|[;&|(\s])(rm\s+(-\w*[rRf]|--recursive|--force)|shred\s|find\s.*-delete\b|truncate\s)"),
    ("disk", r"(^|[;&|(\s])(mkfs\S*|wipefs|fdisk|sfdisk|parted|sgdisk|cryptsetup|dd)\s|>\s*/dev/(sd|nvme|mmcblk|vd)"),
    ("git", r"\bgit\s+(push\s.*(--force|-f\b|--delete)|reset\s+--hard|clean\s+-\w*f|branch\s+-D|checkout\s+--\s|restore\s)"),
    ("power", r"(^|[;&|(\s])(shutdown|reboot|poweroff|halt|systemctl\s+(--\S+\s+)*(poweroff|reboot|halt|suspend|hibernate|kexec))\b"),
    ("system", r"\b(nixos-rebuild|nix-collect-garbage|nix-env)\b|\bsystemctl\s+(--\S+\s+)*(stop|disable|mask|restart|kill)\b|\bnix\s+(profile\s+(remove|wipe-history)|store\s+(delete|gc))"),
    ("permissions", r"\bch(mod|own|grp)\s+(-\w*R|--recursive)"),
    ("internet", r"\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(ba|z|da)?sh\b"),
]


def risks(command):
    return [name for name, pattern in RISKS if re.search(pattern, command)]


ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[()*+][0-9A-Za-z]|\x1b[@-~]")


def terminal_text(raw):
    """A command's output as plain text: no colours, and of a line redrawn
    with \\r (progress bars) only what was left on screen."""
    text = ANSI.sub("", raw.decode("utf-8", "replace"))
    return "\n".join(line.rstrip("\r").rsplit("\r", 1)[-1].rstrip() for line in text.split("\n"))


def clip_middle(text, limit):
    """The start and, mostly, the end: errors come last."""
    if len(text) <= limit:
        return text
    head = limit // 3
    return text[:head].rstrip() + "\n…\n" + text[-(limit - head):].lstrip()


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
        elif name == "list_files" and ok:
            facts["path"] = result.get("path", ".")
            facts["count"] = len(result.get("files", [])) + result.get("more", 0)
        elif name == "read_file" and ok:
            facts["path"] = result.get("path", "")
            facts["lines"] = result.get("lines", 0)
        elif name in ("edit_file", "write_file"):
            facts["declined"] = bool(result.get("declined"))
            facts["path"] = result.get("path", "")
            facts["created"] = bool(result.get("created"))
            facts["added"] = result.get("added", 0)
            facts["removed"] = result.get("removed", 0)
        elif name == "open_app":
            facts["opened"] = result.get("opened", "")
        elif name == "run_command":
            facts["declined"] = bool(result.get("declined"))
            facts["terminal"] = bool(result.get("terminal"))
            facts["exit"] = result.get("exit")
            facts["seconds"] = result.get("seconds", 0)
            lines = [line for line in str(result.get("output", "")).splitlines() if line.strip()]
            facts["tail"] = [line[:200] for line in lines[-OUTPUT_LINES:]]
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
        path = os.path.expanduser(str(self.agent.settings.get("repo") or DEFAULT_SETTINGS["repo"]))
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
        # Nilo signs as co-author (nihil.nilo.coauthor): GitHub shows its face
        # next to the user's when the email belongs to an account.
        coauthor = self.config.get("coauthor") or {}
        trailer = ""
        if changes and coauthor.get("email"):
            trailer = f"Co-authored-by: {coauthor.get('name') or 'Nilo'} <{coauthor['email']}>"
            if trailer.lower() in message.lower():
                trailer = ""
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
            "trailer": trailer,
        }, cancel)
        if not ok:
            return {"declined": True, "note": "The user did not confirm. Nothing was done."}
        result = {"ok": True}
        if changes:
            code, _, err = self.git(repo, "add", "-A")
            if code != 0:
                return {"error": "git add failed", "detail": err.strip()[-400:]}
            code, out, err = self.git(repo, "commit", "-m", message, *(["--trailer", trailer] if trailer else []))
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

    # files, only inside the repository

    def resolve(self, path, must_exist=True):
        """(root, absolute path, path relative to the root). Symlinks are
        followed first, so none can lead outside; .git is off limits."""
        root = os.path.realpath(self.repo())
        given = os.path.expanduser(str(path or "").strip() or ".")
        full = os.path.realpath(os.path.join(root, given))
        if os.path.commonpath([root, full]) != root:
            raise RuntimeError("that path is outside the repository")
        rel = os.path.relpath(full, root)
        if ".git" in rel.split(os.sep):
            raise RuntimeError("Nilo does not touch .git")
        if must_exist and not os.path.exists(full):
            raise RuntimeError(f"{rel} does not exist")
        return root, full, rel

    @staticmethod
    def text_of(full, strict=False):
        """The file as text. To change it (strict), it must be UTF-8: anything
        else would come back altered in places the diff doesn't show."""
        if os.path.getsize(full) > FILE_BYTES:
            raise RuntimeError(f"the file is larger than {FILE_BYTES // 1000} kB")
        with open(full, "rb") as f:
            raw = f.read()
        if b"\0" in raw[:8192]:
            raise RuntimeError("it is not a text file")
        try:
            return raw.decode("utf-8")
        except UnicodeDecodeError:
            if strict:
                raise RuntimeError("it is not UTF-8 text: Nilo only changes UTF-8 files") from None
            return raw.decode("utf-8", "replace")

    def list_files(self, path=".", cancel=None):
        root, full, rel = self.resolve(path)
        if not os.path.isdir(full):
            raise RuntimeError(f"{rel} is not a folder")
        code, tracked, _ = self.git(root, "ls-files", "--cached", "--others", "--exclude-standard", "--", rel)
        if code == 0:
            names = sorted(set(tracked.splitlines()))
        else:
            names = []
            for dirpath, dirs, files in os.walk(full):
                dirs[:] = [d for d in dirs if not d.startswith(".")]
                names += [os.path.relpath(os.path.join(dirpath, f), root) for f in files]
            names.sort()
        return {"path": rel, "files": names[:LIST_FILES], "more": max(0, len(names) - LIST_FILES)}

    def read_file(self, path, from_line=1, cancel=None):
        _, full, rel = self.resolve(path)
        if os.path.isdir(full):
            raise RuntimeError(f"{rel} is a folder: use list_files")
        lines = self.text_of(full).splitlines(keepends=True)
        try:
            start = max(1, int(from_line))
        except (TypeError, ValueError):
            start = 1
        part, size = [], 0
        for line in lines[start - 1:start - 1 + READ_LINES]:
            if size + len(line) > READ_CHARS and part:
                break
            part.append(line)
            size += len(line)
        end = start + len(part) - 1
        result = {"path": rel, "lines": len(lines), "from_line": start, "to_line": end, "text": "".join(part)}
        if end < len(lines):
            result["next_line"] = end + 1
        return result

    @staticmethod
    def diff(old, new):
        """The change as lines for the confirmation card, and its size."""
        lines = list(difflib.unified_diff(old.splitlines(), new.splitlines(), lineterm="", n=2))[2:]
        shown, added, removed = [], 0, 0
        for line in lines:
            kind = "@" if line.startswith("@@") else line[:1]
            if kind == "+":
                added += 1
            elif kind == "-":
                removed += 1
            if len(shown) < CARD_LINES:
                shown.append({"t": kind, "s": "" if kind == "@" else line[1:][:300]})
        return shown, max(0, len(lines) - CARD_LINES), added, removed

    def confirm_change(self, rel, old, new, created, cancel):
        shown, more, added, removed = self.diff(old, new)
        if not added and not removed:
            return None, {"error": "that changes nothing"}
        ok = self.agent.ask_confirmation({
            "action": "create" if created else "edit",
            "repo": self.agent.settings.get("repo"),
            "path": rel,
            "diff": shown,
            "more": more,
            "added": added,
            "removed": removed,
        }, cancel)
        facts = {"path": rel, "added": added, "removed": removed, "created": created}
        if not ok:
            return None, dict(facts, declined=True, note="The user did not confirm. The file was not changed.")
        return facts, None

    @staticmethod
    def put(full, text):
        """Write in place of the file at once (a temporary file, then a rename)."""
        mode = os.stat(full).st_mode & 0o7777 if os.path.exists(full) else 0o644
        tmp = f"{full}.nilo-{os.getpid()}"
        try:
            with open(tmp, "w", encoding="utf-8", newline="") as f:
                f.write(text)
            os.chmod(tmp, mode)
            os.replace(tmp, full)
        finally:
            if os.path.exists(tmp):
                os.remove(tmp)

    def edit_file(self, path, old, new, cancel=None):
        _, full, rel = self.resolve(path)
        if os.path.isdir(full):
            raise RuntimeError(f"{rel} is a folder")
        text = self.text_of(full, strict=True)
        old, new = str(old or ""), str(new or "")
        if not old:
            return {"error": "`old` is empty: copy the text to replace from read_file"}
        count = text.count(old)
        if count == 0:
            return {"error": "`old` is not in the file: read it again and copy the text exactly"}
        if count > 1:
            return {"error": f"`old` appears {count} times: add the lines around it so it is unique"}
        changed = text.replace(old, new, 1)
        facts, refused = self.confirm_change(rel, text, changed, False, cancel)
        if refused:
            return refused
        self.put(full, changed)
        return dict(facts, ok=True)

    def write_file(self, path, content, cancel=None):
        _, full, rel = self.resolve(path, must_exist=False)
        if os.path.isdir(full):
            raise RuntimeError(f"{rel} is a folder")
        content = str(content or "")
        if len(content.encode("utf-8")) > FILE_BYTES:
            return {"error": f"the content is larger than {FILE_BYTES // 1000} kB"}
        created = not os.path.exists(full)
        old = "" if created else self.text_of(full, strict=True)
        facts, refused = self.confirm_change(rel, old, content, created, cancel)
        if refused:
            return refused
        os.makedirs(os.path.dirname(full), exist_ok=True)
        self.put(full, content)
        return dict(facts, ok=True)

    # the desktop: the shell opens apps (it knows the desktop entries)

    def open_app(self, target, cancel=None):
        target = re.sub(r"\s+", " ", str(target or "")).strip()[:300]
        if not target:
            return {"error": "say what to open"}
        kind = "app"
        if re.match(r"(?i)^(https?|mailto):", target):
            kind = "url"
        elif target.startswith(("/", "~")):
            kind = "path"
            target = os.path.expanduser(target)
            if not os.path.exists(target):
                return {"error": f"{target} does not exist"}
        answer = self.agent.call_shell("launch", {"target": target, "kind": kind}, cancel)
        if not isinstance(answer, dict):
            return {"error": "the desktop did not answer"}
        if not answer.get("ok"):
            result = {"error": answer.get("error") or f"nothing called {target} to open"}
            if answer.get("similar"):
                result["similar"] = [str(name) for name in answer["similar"]][:8]
            return result
        return {"ok": True, "opened": str(answer.get("name") or target)}

    # the terminal: every command is confirmed first

    def folder(self, cwd):
        """Where a command runs: `cwd` (relative to the default), or the
        repository, or the home folder."""
        home = os.path.expanduser("~")
        default = os.path.expanduser(str(self.agent.settings.get("repo") or ""))
        default = default if default and os.path.isdir(default) else home
        path = os.path.join(default, os.path.expanduser(str(cwd).strip())) if cwd and str(cwd).strip() else default
        if not os.path.isdir(path):
            raise RuntimeError(f"{cwd} is not a folder")
        return os.path.realpath(path)

    def run_command(self, command, reason="", cwd=None, terminal=False, cancel=None):
        command = str(command or "").strip()
        if not command:
            return {"error": "the command is empty"}
        if len(command) > COMMAND_CHARS:
            return {"error": f"the command is longer than {COMMAND_CHARS} characters: split it or write a script"}
        folder = self.folder(cwd)
        danger = risks(command)
        # sudo asks for a password on a terminal, and here there is none.
        terminal = terminal is True or str(terminal).lower() == "true" or "root" in danger
        ok = self.agent.ask_confirmation({
            "action": "terminal" if terminal else "run",
            "command": command,
            "cwd": self.agent.short_path(folder),
            "reason": re.sub(r"\s+", " ", str(reason or "")).strip()[:300],
            "danger": danger,
        }, cancel)
        if not ok:
            return {"declined": True, "note": "The user did not confirm. Nothing ran."}
        if terminal:
            return self.in_terminal(command, folder)
        return self.execute(command, folder, cancel)

    def in_terminal(self, command, folder):
        """In a terminal window the user sees and can type in (a password),
        kept open when the command ends, with its exit code at the bottom."""
        script = command + "\nprintf '\\n[%s]\\n' \"$?\""
        try:
            subprocess.Popen([self.config.get("terminal", "kitty"), "--hold", "--directory", folder,
                              self.config.get("bash", "bash"), "-lc", script],
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
        except OSError as e:
            return {"error": f"cannot open the terminal: {e}"}
        return {"ok": True, "terminal": True, "cwd": self.agent.short_path(folder),
                "note": "It is running in a terminal window: you don't see its output. Tell the user to look there."}

    def execute(self, command, folder, cancel):
        limit = float(self.config.get("commandSeconds", COMMAND_SECONDS))
        env = dict(os.environ, TERM="dumb", NO_COLOR="1", PAGER="cat", GIT_PAGER="cat", SYSTEMD_PAGER="",
                   SYSTEMD_COLORS="0", GIT_TERMINAL_PROMPT="0")
        started = time.monotonic()
        try:
            proc = subprocess.Popen([self.config.get("bash", "bash"), "-c", command], cwd=folder, env=env,
                                    stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    start_new_session=True)
        except OSError as e:
            return {"error": f"cannot run bash: {e}"}
        head, tail, total = bytearray(), bytearray(), [0]

        def pump():
            # The output's start and its end; whatever is in between only counts.
            while True:
                try:
                    chunk = os.read(proc.stdout.fileno(), 65536)
                except OSError:
                    return
                if not chunk:
                    return
                total[0] += len(chunk)
                room = OUTPUT_KEEP - len(head)
                if room > 0:
                    head.extend(chunk[:room])
                    chunk = chunk[room:]
                if chunk:
                    tail.extend(chunk)
                    del tail[:-OUTPUT_KEEP]

        reader = threading.Thread(target=pump, daemon=True)
        reader.start()
        stopped, shown, last = "", None, 0.0
        while proc.poll() is None:
            if cancel and cancel.cancelled:
                stopped = "cancelled"
            elif time.monotonic() - started > limit:
                stopped = "timeout"
            if stopped:
                self.kill(proc)
                break
            time.sleep(0.1)
            if time.monotonic() - last > 0.3:
                last = time.monotonic()
                lines = [line for line in terminal_text(bytes((head + tail)[-4096:])).splitlines() if line.strip()]
                lines = [line[:200] for line in lines[-OUTPUT_LINES:]]
                if lines != shown:
                    shown = lines
                    self.agent.out("output", id=self.agent.current_tool, lines=lines)
        reader.join(timeout=2)
        dropped = total[0] - len(head) - len(tail)
        text = terminal_text(bytes(head)) + (f"\n… ({dropped} bytes) …\n" if dropped > 0 else "") + terminal_text(bytes(tail))
        result = {"exit": proc.returncode, "seconds": round(time.monotonic() - started, 1),
                  "cwd": self.agent.short_path(folder), "output": clip_middle(text.strip(), OUTPUT_CHARS) or "(no output)"}
        if stopped == "timeout":
            result["error"] = f"it ran for more than {int(limit)} s and was stopped: use terminal=true for long commands"
        elif stopped == "cancelled":
            result["note"] = "The user stopped it."
        return result

    @staticmethod
    def kill(proc):
        """The command and everything it started: they share its session."""
        for sig, wait in ((signal.SIGTERM, 2), (signal.SIGKILL, 2)):
            try:
                os.killpg(proc.pid, sig)
            except (ProcessLookupError, PermissionError):
                return
            try:
                proc.wait(timeout=wait)
                return
            except subprocess.TimeoutExpired:
                continue


def meminfo(path="/proc/meminfo"):
    values = {}
    try:
        with open(path) as f:
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
        "write": "Puedes leer y cambiar archivos de {repo} con list_files, read_file, edit_file y write_file, solo "
                 "cuando te lo pidan. Lee un archivo antes de cambiarlo; para cambios pequeños usa edit_file. El "
                 "usuario ve cada cambio y lo confirma antes de que se escriba; si no lo confirma, no insistas.",
        "apps": "Con open_app abres aplicaciones, archivos, carpetas y webs en el escritorio cuando te lo pidan.",
        "shell": "Con run_command ejecutas comandos de bash en este ordenador. El usuario ve cada comando y lo confirma "
                 "antes de que se ejecute: uno por llamada, y di en reason qué hace y por qué. Mira antes de cambiar "
                 "nada. Lo que pide contraseña (sudo), es interactivo o tarda minutos va con terminal=true: se abre "
                 "en una terminal para el usuario y tú no ves la salida.",
        "limits": "No puedes editar archivos ni ejecutar comandos: si te lo piden, explica cómo hacerlo.",
        "limitsWrite": "No puedes ejecutar comandos ni tocar nada fuera de {repo}: si te lo piden, explica cómo hacerlo.",
        "limitsShell": "Ejecuta solo lo que haga falta para lo que te piden, y nunca algo destructivo que no te hayan "
                       "pedido claramente.",
        "about": "NIHIL: SUPER+Espacio abre el launcher (> acciones, = calculadora, ? tú); SUPER+D el dashboard; "
                 "SUPER+P los ajustes; {summon} te abren a ti. La configuración de esta máquina está en {flake} "
                 "(settings.json, local.nix, home.nix) y se aplica con `nihil rebuild`; `nihil update` trae la "
                 "última versión de NIHIL.",
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
        "write": "You can read and change files of {repo} with list_files, read_file, edit_file and write_file, only "
                 "when asked to. Read a file before changing it; for small changes use edit_file. The user sees every "
                 "change and confirms it before it is written; if they don't, don't insist.",
        "apps": "With open_app you open apps, files, folders and web pages on the desktop when asked to.",
        "shell": "With run_command you run bash commands on this computer. The user sees every command and confirms "
                 "it before it runs: one per call, and say in reason what it does and why. Look before you change "
                 "anything. Whatever asks for a password (sudo), is interactive or takes minutes goes with "
                 "terminal=true: it opens in a terminal for the user and you don't see its output.",
        "limits": "You cannot edit files or run commands: if asked to, explain how to do it.",
        "limitsWrite": "You cannot run commands or touch anything outside {repo}: if asked to, explain how to do it.",
        "limitsShell": "Run only what the request needs, and never anything destructive you weren't clearly asked for.",
        "about": "NIHIL: SUPER+Space opens the launcher (> actions, = calculator, ? you); SUPER+D the dashboard; "
                 "SUPER+P the settings; {summon} open you. This machine's configuration is in {flake} "
                 "(settings.json, local.nix, home.nix) and is applied with `nihil rebuild`; `nihil update` brings "
                 "the latest NIHIL.",
        "summon": "SUPER+I and the Copilot key",
    },
}


# --- nilo.md ----------------------------------------------------------------------

NOTES = {
    "es": "<!--\nTus notas para Nilo. Lo que escribas fuera de este comentario se añade a lo que sabe \n"
          "(home/nilo/nilo.md) en cada pregunta: quién eres, cómo te gustan las respuestas, tus proyectos.\n"
          "Una sección cuyo título acaba en {web}, {system}, {apps}, {write}, {git} o {shell} solo cuenta\n"
          "con ese permiso activado; {user}, {host}, {flake} y {repo} se rellenan solos.\n-->\n",
    "en": "<!--\nYour notes for Nilo. Whatever you write outside this comment is added to what it knows\n"
          "(home/nilo/nilo.md) on every question: who you are, how you like answers, your projects.\n"
          "A section whose heading ends in {web}, {system}, {apps}, {write}, {git} or {shell} only counts\n"
          "while that switch is on; {user}, {host}, {flake} and {repo} are filled in.\n-->\n",
}

SWITCH_TAG = re.compile(r"\s*\{(web|system|apps|write|git|shell)\}\s*$")


def notes_path():
    return os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "nihil", "nilo.md")


def read_text(path):
    if not path:
        return ""
    try:
        with open(os.path.expanduser(str(path)), encoding="utf-8", errors="replace") as f:
            return f.read(4 * CONTEXT_CHARS)
    except OSError:
        return ""


def context_sections(text, settings, values):
    """What of a nilo.md applies now: no comments, no sections of switches
    that are off (a heading ending in {shell} keeps its section, subsections
    included, only with that switch on), and the placeholders filled in."""
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    kept, off = [], 0           # off: depth of the heading whose section is left out
    for line in text.splitlines():
        heading = re.match(r"(#{1,6})\s", line)
        if heading:
            depth = len(heading.group(1))
            if off and depth > off:
                continue
            off = 0
            tag = SWITCH_TAG.search(line)
            if tag:
                if not settings.get(tag.group(1)):
                    off = depth
                    continue
                line = line[:tag.start()]
        elif off:
            continue
        kept.append(line)
    text = "\n".join(kept)
    for key, value in values.items():
        text = text.replace("{" + key + "}", str(value))
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def build_context(config, settings, user):
    """nilo.md, then the user's notes, then (with files or git allowed) the
    repository's own NILO.md."""
    values = {"user": user, "host": config.get("host", ""), "flake": config.get("flake", "~/nixos-config"),
              "repo": settings.get("repo", "")}
    parts = [read_text(config.get("context")), read_text(notes_path())]
    if settings.get("write") or settings.get("git"):
        repo = os.path.expanduser(str(settings.get("repo") or ""))
        parts.append(next((read_text(os.path.join(repo, name)) for name in ("NILO.md", "nilo.md")
                           if repo and os.path.isfile(os.path.join(repo, name))), ""))
    text = "\n\n".join(part for part in (context_sections(p, settings, values) for p in parts) if part)
    return clip(text, CONTEXT_CHARS)


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
    if settings.get("write"):
        rules.append(text["write"].format(repo=settings["repo"]))
    if settings.get("apps"):
        rules.append(text["apps"])
    if settings.get("shell"):
        rules.append(text["shell"])
    limits = "limitsShell" if settings.get("shell") else "limitsWrite" if settings.get("write") else "limits"
    rules.append(text[limits].format(repo=settings["repo"]))
    lines += [f"- {rule}" for rule in rules]
    lines += ["", text["about"].format(summon=config.get("summon") or text["summon"],
                                       flake=config.get("flake", "~/nixos-config"), host=config.get("host", ""))]
    context = build_context(config, settings, user)
    if context:
        lines += ["", context]
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
        self.confirms = {}          # id -> [Event, answer]: confirmations and the shell's replies
        self.ids = itertools.count(1)
        self.current_tool = ""      # id of the tool running, for its live output
        self.no_tools = False       # the model said it can't use tools
        self.state = {"ollama": None, "loaded": False, "loading": False, "model": "", "expires": None,
                      "sizeGB": 0, "gpu": 0}
        self.installed = set()      # model names Ollama has, as of the last catalogue
        self.active = ""            # the model of the latest answer (auto may pick a smaller one)
        self.state_lock = threading.Lock()
        self.wake = threading.Event()
        self.starting = False       # starting ollama.service
        self.last_start = -1e9      # when Nilo last tried to (monotonic)

    # settings

    def recommended(self):
        models = self.config.get("models", [])
        if not models:
            return ""
        budget = self.ram_gb * 0.45
        fitting = [m for m in models if m.get("ram", 0) <= budget]
        return (max(fitting, key=lambda m: m.get("ram", 0)) if fitting else models[0])["tag"]

    def current(self):
        """The model Nilo is using: the one chosen, or the one auto used last."""
        return self.active or self.settings["model"]

    def has(self, tag):
        return tag in self.installed or f"{tag}:latest" in self.installed

    def fast(self):
        """For auto: the smallest model of the list that is downloaded and
        smaller than the one chosen (\"\" if there is none)."""
        models = [m for m in self.config.get("models", []) if m.get("ram", 0) > 0 and self.has(m["tag"])]
        chosen = next((m.get("ram", 0) for m in self.config.get("models", []) if m["tag"] == self.settings["model"]), 0)
        smaller = [m for m in models if m["tag"] != self.settings["model"] and (not chosen or m["ram"] < chosen)]
        return min(smaller, key=lambda m: m["ram"])["tag"] if smaller else ""

    def route(self, text):
        """The model for one question."""
        chosen = self.settings["model"]
        if not self.settings.get("auto") or self.settings.get("think") or not simple(text):
            return chosen
        return self.fast() or chosen

    def default_repo(self):
        """NIHIL's checkout, where Nilo works until another repository is chosen."""
        candidates = [read_text(self.config.get("devFile", DEV_FILE)).strip(), *CHECKOUTS]
        for path in candidates:
            if path and os.path.exists(os.path.join(os.path.expanduser(path), ".git")):
                return self.short_path(path)
        return DEFAULT_SETTINGS["repo"]

    def load_settings(self):
        settings = dict(DEFAULT_SETTINGS)
        chosen = False
        try:
            with open(self.state_path) as f:
                saved = json.load(f)
            for key, value in saved.items():
                if key in settings and type(value) is type(DEFAULT_SETTINGS[key]):
                    settings[key] = value
                    chosen = chosen or (key == "repo" and value.strip() != "")
        except (OSError, ValueError, AttributeError):
            pass
        if not settings["model"]:
            settings["model"] = self.recommended()
        if not chosen:
            settings["repo"] = self.default_repo()
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
                value = value or self.default_repo()
                if not os.path.exists(os.path.join(os.path.expanduser(value), ".git")):
                    self.out("settings", settings=self.settings)
                    return self.out("error", code="bad-repo", detail=value)
                value = self.short_path(value)
        old = self.settings.get(key)
        self.settings[key] = value
        if key in ("model", "auto"):
            self.active = ""
        # Git and files were allowed for one repository: another one asks again.
        if key == "repo" and os.path.realpath(os.path.expanduser(old or "")) != os.path.realpath(os.path.expanduser(value)):
            self.settings["git"] = False
            self.settings["write"] = False
        self.save_settings()
        self.out("settings", settings=self.settings)
        if key == "model" and old != value:
            self.no_tools = False
            if self.state["loaded"] and self.state["model"]:
                threading.Thread(target=self.quietly, args=(self.ollama.unload, self.state["model"]), daemon=True).start()
            self.wake.set()
        elif key == "auto":
            self.send_models()
        elif key == "keepAlive" and self.state["loaded"]:
            threading.Thread(target=self.warm, daemon=True).start()

    @staticmethod
    def short_path(path):
        """~/x for anything under the home directory, as the settings show it."""
        home = os.path.expanduser("~")
        full = os.path.abspath(os.path.expanduser(path))
        return "~" + full[len(home):] if full == home or full.startswith(home + os.sep) else full

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
        if installed is not None:
            self.installed = set(installed)
        return {"models": known, "recommended": self.recommended(), "ramGB": self.ram_gb,
                "ollama": installed is not None, "fast": self.fast()}

    def send_models(self):
        self.out("models", **self.catalogue())

    def refresh_state(self):
        model = self.current()
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

    # Every model runs where the machine says (Preferences, System: the CPU
    # or the GPU, modules/nilo.nix): Ollama places it, the same for all.
    def options(self):
        return {"num_ctx": int(self.config.get("contextLength", 16384))}

    def need(self, model):
        """GB `model` takes with Nilo's context: as the models list says, or
        its download and a quarter more for one that isn't on it (0 if it
        isn't downloaded)."""
        names = {model, model.removesuffix(":latest"), f"{model}:latest"}
        listed = next((m for m in self.config.get("models", []) if m.get("tag") in names and m.get("ram")), None)
        if listed is not None:
            return float(listed["ram"])
        try:
            download = next((m for m in self.ollama.tags() if m.get("name") in names), None)
        except OllamaError:
            return 0.0
        return download.get("size", 0) / 1e9 * 1.25 if download else 0.0

    def keep_alive(self):
        return f"{int(self.settings['keepAlive'])}m"

    def room(self, model):
        """Refuse ("memory") a model that can't run here at all: one that
        takes, with Nilo's context, more than the machine's memory less its
        reserve, downloaded or not (before 22 GB come down for nothing).
        Anything smaller runs."""
        total = meminfo(self.config.get("meminfo", "/proc/meminfo")).get("MemTotal", 0) * 1024 / 1e9
        need = self.need(model)
        reserve = max(RESERVE_GB, total * RESERVE_SHARE)
        if total > 0 and need > total - reserve:
            raise OllamaError("memory", f"{model} takes about {need:.1f} GB, and this machine has "
                                        f"{total:.1f}, {reserve:.1f} of them for the rest")

    def warm(self):
        model = self.current()
        if not model or self.state["loading"]:
            return
        self.ensure_ollama()
        # Not if it doesn't fit, and without waking the eyes for it: the question
        # will say so. (Saying "loading" first raced the question's own refusal.)
        try:
            self.room(model)
        except OllamaError as e:
            log("warm:", e.detail or e.code)
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
        """Every model of Nilo's that is in memory (auto may have two)."""
        try:
            running = [m.get("name", "") for m in self.ollama.ps()]
        except OllamaError:
            return
        ours = {m["tag"] for m in self.config.get("models", [])} | {self.settings["model"], self.active}
        for name in running:
            if name in ours or name.removesuffix(":latest") in ours:
                self.quietly(self.ollama.unload, name)

    # Ollama itself: when it doesn't answer, what systemd says, and starting it

    def run_quietly(self, *command, timeout=5):
        try:
            return subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout)
        except (OSError, subprocess.TimeoutExpired) as e:
            return subprocess.CompletedProcess(command, 1, "", str(e))

    def diagnose(self):
        unit = self.config.get("ollamaUnit", "ollama.service")
        info = {"unit": unit}
        shown = self.run_quietly(self.config.get("systemctl", "systemctl"), "show", unit,
                                 "--property=LoadState,ActiveState,SubState,Result,ExecMainStatus,NRestarts")
        for line in shown.stdout.splitlines():
            key, _, value = line.partition("=")
            if key:
                info[key[0].lower() + key[1:]] = value
        # The lines that say what went wrong, if any stand out; otherwise the last ones.
        journal = self.run_quietly(self.config.get("journalctl", "journalctl"), "-u", unit, "-b", "-n", "80",
                                   "-o", "cat", "--no-pager")
        lines = [re.sub(r"^time=\S+\s+|\bsource=\S+\s+", "", line).strip()
                 for line in journal.stdout.splitlines()] if journal.returncode == 0 else []
        lines = [line for line in lines if line]
        telling = [line for line in lines if re.search(
            r"(?i)level=(error|warn)|\b(error|panic|fatal|failed|denied|refused|killed|exited|signal|in use|out of memory)\b", line)]
        info["log"] = [line[:220] for line in (telling or lines)[-5:]]
        return info

    def ollama_up(self, seconds):
        deadline = time.monotonic() + seconds
        while True:
            try:
                self.ollama.ps()
                return True
            except OllamaError:
                if time.monotonic() > deadline:
                    return False
                time.sleep(0.5)

    def start_ollama(self, ask=False):
        """Ask systemd to start Ollama (modules/nilo.nix lets polkit say yes
        without a password) and wait for it to answer."""
        with self.lock:
            if self.starting:
                return
            self.starting = True
            self.last_start = time.monotonic()
        try:
            self.out("ollama", starting=True, **self.diagnose())
            command = [self.config.get("systemctl", "systemctl"), "start", self.config.get("ollamaUnit", "ollama.service")]
            if not ask:
                command.insert(1, "--no-ask-password")
            started = self.run_quietly(*command, timeout=120)
            up = started.returncode == 0 and self.ollama_up(20)
            self.refresh_state()
            if up:
                self.out("ollama", starting=False, up=True)
                self.send_models()
            else:
                self.out("ollama", starting=False, up=False, error=(started.stderr or started.stdout).strip()[-300:],
                         **self.diagnose())
        except Exception as e:
            log("starting ollama failed:", repr(e))
            self.out("ollama", starting=False, up=False, error=str(e)[-300:])
        finally:
            self.starting = False
            self.wake.set()

    def ensure_ollama(self):
        """Before something that needs Ollama: if it is down, try to start it
        (at most once a minute, so a broken service isn't hammered)."""
        if self.state["ollama"] is not False:
            return
        if time.monotonic() - self.last_start < 60:
            return
        self.start_ollama()

    def repos(self):
        """Git repositories under ~ (three levels down), the most recently used first."""
        home = os.path.expanduser("~")
        skip = {"node_modules", "target", "build", "dist", "result", "venv", "vendor", "__pycache__"}
        found, visited, began = [], 0, time.monotonic()
        for dirpath, dirs, files in os.walk(home):
            visited += 1
            if visited > 8000 or time.monotonic() - began > 2:
                break
            if dirpath != home and (".git" in dirs or ".git" in files):
                found.append(dirpath)
                dirs[:] = []
                continue
            depth = 0 if dirpath == home else os.path.relpath(dirpath, home).count(os.sep) + 1
            dirs[:] = [] if depth >= 3 else sorted(d for d in dirs if not d.startswith(".") and d not in skip)

        def used(path):
            try:
                return os.stat(os.path.join(path, ".git")).st_mtime
            except OSError:
                return 0

        found.sort(key=used, reverse=True)
        self.out("repos", repos=[self.short_path(p) for p in found[:30]])

    def notes(self):
        """The user's notes for Nilo, for the shell to open in an editor."""
        path = notes_path()
        if not os.path.exists(path):
            language = self.config.get("language", "en")
            try:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w", encoding="utf-8") as f:
                    f.write(NOTES.get(language, NOTES["en"]))
            except OSError as e:
                return self.out("error", code="notes", detail=str(e))
        self.out("notes", path=path)

    # downloads

    def pull(self, model):
        if self.pulling:
            return self.out("pull", model=model, status="busy")
        cancel = Cancel()
        self.pulling = (model, cancel)
        threading.Thread(target=self._pull, args=(model, cancel), daemon=True).start()

    def _pull(self, model, cancel):
        try:
            self.ensure_ollama()
            status, detail, code = self._pull_once(model, cancel)
            # Ollama was down without the agent knowing yet: start it, try again.
            if code == "ollama-down" and not cancel.cancelled:
                self.refresh_state()
                self.ensure_ollama()
                if self.state["ollama"]:
                    status, detail, code = self._pull_once(model, cancel)
            # Broken off (the network, the registry's limit): again, from where it stopped.
            for attempt in range(2, PULL_ATTEMPTS + 1):
                if status == "success" or cancel.cancelled or code == "ollama-down" or pull_error(detail) not in ("network", "rate"):
                    break
                wait = float(self.config.get("pullWait", PULL_WAIT)) * (attempt - 1) ** 2
                log(f"pull {model} broke off ({detail}); attempt {attempt} in {wait} s")
                self.out("pull", model=model, status="retrying", attempt=attempt, attempts=PULL_ATTEMPTS, detail=detail)
                deadline = time.monotonic() + wait
                while time.monotonic() < deadline and not cancel.cancelled:
                    time.sleep(0.2)
                if not cancel.cancelled:
                    status, detail, code = self._pull_once(model, cancel)
        finally:
            self.pulling = None
        if status != "success":
            if status != "cancelled":
                log(f"pull {model} failed: {detail or status}")
            self.out("pull", model=model, status=status if status in ("cancelled", "error") else "error",
                     detail=detail or status, code=code if code == "ollama-down" else pull_error(detail) or code)
        self.send_models()
        self.wake.set()

    def _pull_once(self, model, cancel):
        """(status, detail, error code) of one attempt."""
        layers = {}
        last = 0.0
        status = "error"
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
            return ("cancelled" if cancel.cancelled else status), "", ""
        except OllamaError as e:
            return "error", e.detail or e.code, e.code

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

    def call_shell(self, ev, detail, cancel, seconds=8):
        """Ask the shell to do something only it can (open an app) and wait
        for its reply; None if it doesn't answer."""
        cid = f"c{next(self.ids)}"
        event = threading.Event()
        self.confirms[cid] = [event, None]
        self.out(ev, id=cid, **detail)
        deadline = time.monotonic() + seconds
        while not event.wait(0.1):
            if (cancel and cancel.cancelled) or time.monotonic() > deadline:
                break
        return self.confirms.pop(cid, [None, None])[1]

    def answer_shell(self, cid, reply):
        entry = self.confirms.get(cid)
        if entry:
            entry[1] = {k: v for k, v in reply.items() if k not in ("op", "id")}
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
        model = self.route(text)
        if model != self.current():
            self.set_state(model=model, loaded=False)
        self.active = model
        stats["model"] = model
        # The conversation this question belongs to: "reset" starts a new list,
        # so an answer cut short by it lands in the old one.
        history = self.history
        history.append({"role": "user", "content": text})
        self.out("start", model=model, auto=model != self.settings["model"])
        if not model:
            raise OllamaError("no-model")
        self.ensure_ollama()
        if not self.state["loaded"]:
            self.room(model)
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
                # The shell shows the path or the query; a file's whole text stays here.
                shown = {k: v[:200] if isinstance(v, str) else v for k, v in args.items()} if isinstance(args, dict) else args
                self.out("tool", id=tid, name=name, args=shown, status="running")
                self.current_tool = tid
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
        models = self.catalogue()
        self.out("hello", protocol=PROTOCOL, settings=self.settings, language=self.config.get("language", "en"),
                 **models)
        self.wake.set()
        if not models["ollama"]:
            self.set_state(ollama=False)
            threading.Thread(target=self.ensure_ollama, daemon=True).start()

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
        elif op == "repos":
            threading.Thread(target=self.repos, daemon=True).start()
        elif op == "startOllama":
            threading.Thread(target=self.start_ollama, kwargs={"ask": True}, daemon=True).start()
        elif op == "launched":
            self.answer_shell(request.get("id"), request)
        elif op == "notes":
            self.notes()
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
    parser.add_argument("--config", required=True, help="configuration written by home/nilo/default.nix")
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