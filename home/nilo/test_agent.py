#!/usr/bin/env python3
# test_agent.py by poligle
#
# Tests for Nilo's agent against a fake Ollama (scripted replies, tool calls,
# pulls), a fake ddgr and a throwaway git repository with its own remote.
# Nothing touches the network or a real model.
#
#   python3 -m unittest home/nilo/test_agent.py

import http.server
import json
import os
import queue
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import agent  # noqa: E402


class FakeOllama(http.server.ThreadingHTTPServer):
    """Just enough of Ollama's API for the agent."""

    daemon_threads = True

    def __init__(self, port=0):
        super().__init__(("127.0.0.1", port), Handler)
        self.installed = {"qwen3.5:4b": 3_400_000_000}
        self.loaded = {}            # model -> expiry (epoch)
        self.chats = []             # every /api/chat body
        self.loads = []             # every /api/generate body
        self.no_tools = set()       # models that refuse tools
        self.down = False           # answer 503, as if it were still starting
        self.lock = threading.Lock()

    def handle_error(self, request, client_address):
        if not isinstance(sys.exc_info()[1], (ConnectionError, BrokenPipeError)):
            super().handle_error(request, client_address)

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server_address[1]}"


def iso(epoch):
    t = time.gmtime(epoch)
    return time.strftime("%Y-%m-%dT%H:%M:%S", t) + ".123456789Z"


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length) or b"{}")

    def reply(self, status, obj):
        data = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def start_stream(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

    def chunk(self, obj):
        data = (json.dumps(obj) + "\n").encode()
        self.wfile.write(f"{len(data):x}\r\n".encode() + data + b"\r\n")
        self.wfile.flush()

    def end_stream(self):
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()

    def do_GET(self):
        s = self.server
        if s.down:
            return self.reply(503, {"error": "starting"})
        if self.path == "/api/ps":
            now = time.time()
            with s.lock:
                models = [{"name": m, "model": m, "size": 5_000_000_000, "size_vram": 5_000_000_000,
                           "expires_at": iso(exp), "context_length": 16384}
                          for m, exp in s.loaded.items() if exp > now]
            return self.reply(200, {"models": models})
        if self.path == "/api/tags":
            with s.lock:
                return self.reply(200, {"models": [{"name": m, "model": m, "size": size}
                                                   for m, size in s.installed.items()]})
        self.reply(404, {"error": "not found"})

    def do_DELETE(self):
        s = self.server
        body = self.body()
        with s.lock:
            if s.installed.pop(body.get("model"), None) is None:
                return self.reply(404, {"error": f"model '{body.get('model')}' not found"})
        self.reply(200, {})

    def do_POST(self):
        s = self.server
        body = self.body()
        if self.path == "/api/generate":
            s.loads.append(body)
            model = body.get("model")
            if model not in s.installed:
                return self.reply(404, {"error": f'model "{model}" not found, try pulling it first'})
            keep = body.get("keep_alive", "5m")
            with s.lock:
                if keep == 0:
                    s.loaded.pop(model, None)
                else:
                    s.loaded[model] = time.time() + (int(keep[:-1]) * 60 if isinstance(keep, str) else keep)
            return self.reply(200, {"model": model, "response": "", "done": True})
        if self.path == "/api/pull":
            model = body.get("model")
            self.start_stream()
            self.chunk({"status": "pulling manifest"})
            for done in range(0, 101, 25):
                self.chunk({"status": "pulling aaa", "digest": "sha256:aaa", "total": 1000, "completed": done * 10})
                time.sleep(0.02)
            self.chunk({"status": "pulling bbb", "digest": "sha256:bbb", "total": 10, "completed": 10})
            self.chunk({"status": "verifying sha256 digest"})
            with s.lock:
                s.installed[model] = 1010
            self.chunk({"status": "success"})
            return self.end_stream()
        if self.path == "/api/chat":
            return self.chat(body)
        self.reply(404, {"error": "not found"})

    def chat(self, body):
        s = self.server
        s.chats.append(body)
        model = body.get("model")
        if model not in s.installed:
            return self.reply(404, {"error": f'model "{model}" not found, try pulling it first'})
        if body.get("tools") and model in s.no_tools:
            return self.reply(400, {"error": f'registry.ollama.ai/library/{model} does not support tools'})
        with s.lock:
            s.loaded[model] = time.time() + 300
        messages = body["messages"]
        last_user = max(i for i, m in enumerate(messages) if m["role"] == "user")
        question = messages[last_user]["content"].lower()
        after = messages[last_user + 1:]
        tools_done = [m for m in after if m["role"] == "tool"]
        self.start_stream()
        try:
            if "busca" in question and not tools_done:
                self.say(tool_calls=[{"function": {"name": "web_search", "arguments": {"query": "nixos 26.05"}}}])
            elif "busca" in question:
                found = json.loads(tools_done[-1]["content"])
                self.say(f"Mira esto: [{found['results'][0]['title']}]({found['results'][0]['url']})")
            elif "sube" in question and not tools_done:
                self.say(tool_calls=[{"function": {"name": "git_status", "arguments": {}}}])
            elif "sube" in question and len(tools_done) == 1:
                self.say(tool_calls=[{"id": "call_7", "function": {"name": "git_commit",
                                                                   "arguments": {"message": "Add notes", "push": True}}}])
            elif "sube" in question:
                result = json.loads(tools_done[-1]["content"])
                self.say("Hecho." if result.get("ok") else "No he hecho nada.")
            elif "edita" in question and not tools_done:
                self.say(tool_calls=[{"function": {"name": "read_file", "arguments": {"path": "notes.md"}}}])
            elif "edita" in question and len(tools_done) == 1:
                self.say(tool_calls=[{"function": {"name": "edit_file", "arguments": {
                    "path": "notes.md", "old": "notes", "new": "Notas de Nilo"}}}])
            elif "edita" in question or "crea" in question and tools_done:
                result = json.loads(tools_done[-1]["content"])
                self.say("Cambiado." if result.get("ok") else "No lo he cambiado.")
            elif "crea" in question:
                self.say(tool_calls=[{"function": {"name": "write_file", "arguments": {
                    "path": "docs/nuevo.md", "content": "# Nuevo\n\nHola.\n"}}}])
            elif "lento" in question:
                for i in range(200):
                    self.chunk({"message": {"role": "assistant", "content": f"{i} "}, "done": False})
                    time.sleep(0.02)
                self.chunk({"message": {"role": "assistant", "content": ""}, "done": True})
            else:
                if body.get("think"):
                    self.chunk({"message": {"role": "assistant", "content": "", "thinking": "hmm"}, "done": False})
                self.say("¡Hola! Soy Nilo.")
            self.end_stream()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def say(self, text="", tool_calls=None):
        for word in text.split(" ") if text else []:
            self.chunk({"message": {"role": "assistant", "content": word + " "}, "done": False})
        if tool_calls:
            self.chunk({"message": {"role": "assistant", "content": "", "tool_calls": tool_calls}, "done": False})
        self.chunk({"message": {"role": "assistant", "content": ""}, "done": True,
                    "eval_count": 12, "eval_duration": 600_000_000, "prompt_eval_count": 80})


MODELS = [
    {"tag": "qwen3.5:0.8b", "label": "Qwen 3.5 0.8B", "size": 1.3, "ram": 2},
    {"tag": "qwen3.5:2b", "label": "Qwen 3.5 2B", "size": 2.7, "ram": 3.5},
    {"tag": "qwen3.5:4b", "label": "Qwen 3.5 4B", "size": 3.4, "ram": 5},
    {"tag": "qwen3.5:9b", "label": "Qwen 3.5 9B", "size": 6.6, "ram": 8.5},
]


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True,
                          stdin=subprocess.DEVNULL).stdout.strip()


class AgentProcess:
    def __init__(self, config, state, env=None):
        self.proc = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "agent.py"), "--config", config,
                                      "--state", state],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     text=True, encoding="utf-8", bufsize=1, env=env)
        self.events = queue.Queue()
        self.log = []
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            event = json.loads(line)
            self.log.append(event)
            self.events.put(event)

    def send(self, **request):
        self.proc.stdin.write(json.dumps(request) + "\n")
        self.proc.stdin.flush()

    def wait(self, ev, timeout=10, where=lambda e: True):
        deadline = time.monotonic() + timeout
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                raise AssertionError(f"no {ev!r} event; got {[e['ev'] for e in self.log][-30:]}; last {self.log[-3:]}")
            try:
                event = self.events.get(timeout=left)
            except queue.Empty:
                continue
            if event["ev"] == ev and where(event):
                return event

    def until_done(self, timeout=15):
        """Events of one answer, up to and including "done"."""
        seen = []
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                event = self.events.get(timeout=0.2)
            except queue.Empty:
                continue
            seen.append(event)
            if event["ev"] == "done":
                return seen
            if event["ev"] == "confirm":
                self.on_confirm(event)
        raise AssertionError(f"no done; got {[e['ev'] for e in seen]}")

    on_confirm = staticmethod(lambda event: None)

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            self.proc.kill()
            self.proc.wait()
        for stream in (self.proc.stdout, self.proc.stderr):
            stream.close()


class AgentTest(unittest.TestCase):
    def setUp(self):
        self.ollama = FakeOllama()
        threading.Thread(target=self.ollama.serve_forever, daemon=True).start()
        self.dir = tempfile.mkdtemp(prefix="nilo-test-")
        self.ddgr = os.path.join(self.dir, "ddgr")
        with open(self.ddgr, "w") as f:
            f.write("#!/bin/sh\n"
                    "printf '%s\\n' \"$@\" > \"$(dirname \"$0\")/ddgr-args\"\n"
                    "cat <<'EOF'\n"
                    '[{"title": "NixOS 26.05 released", "url": "https://nixos.org/blog/26.05", '
                    '"abstract": "The   new release\\n is out."}, '
                    '{"title": "No url", "url": "", "abstract": ""}]\n'
                    "EOF\n")
        os.chmod(self.ddgr, 0o755)
        # systemctl: "show" says Ollama failed; "start" leaves a mark (and fails if told to).
        self.systemctl = os.path.join(self.dir, "systemctl")
        with open(self.systemctl, "w") as f:
            f.write("#!/bin/sh\n"
                    "d=$(dirname \"$0\")\n"
                    "case \"$1\" in\n"
                    "  show) printf 'LoadState=loaded\\nActiveState=failed\\nSubState=failed\\n"
                    "Result=exit-code\\nExecMainStatus=1\\nNRestarts=0\\n' ;;\n"
                    "  *) echo \"$@\" >> \"$d/started\"\n"
                    "     if [ -e \"$d/start-fails\" ]; then echo 'Job failed' >&2; exit 1; fi ;;\n"
                    "esac\n")
        self.journalctl = os.path.join(self.dir, "journalctl")
        with open(self.journalctl, "w") as f:
            f.write("#!/bin/sh\necho 'Error: listen tcp 127.0.0.1:11434: bind: address already in use'\n")
        os.chmod(self.systemctl, 0o755)
        os.chmod(self.journalctl, 0o755)
        self.config = os.path.join(self.dir, "config.json")
        self.write_config()
        self.state = os.path.join(self.dir, "state", "nilo.json")
        self.agent = None

    def write_config(self, **extra):
        with open(self.config, "w") as f:
            json.dump(dict({"ollama": self.ollama.url, "language": "es", "models": MODELS, "contextLength": 8192,
                            "ddgr": self.ddgr, "git": shutil.which("git"), "host": "thinkpad",
                            "systemctl": self.systemctl, "journalctl": self.journalctl,
                            "flake": "~/nixos-config"}, **extra), f)

    def tearDown(self):
        if self.agent:
            self.agent.close()
        self.ollama.shutdown()
        self.ollama.server_close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def start(self, settings=None, env=None):
        if settings is not None:
            os.makedirs(os.path.dirname(self.state), exist_ok=True)
            with open(self.state, "w") as f:
                json.dump(settings, f)
        self.agent = AgentProcess(self.config, self.state, env)
        self.agent.send(op="hello")
        return self.agent.wait("hello")

    def text_of(self, events):
        return "".join(e["text"] for e in events if e["ev"] == "token")

    # ---------------------------------------------------------------------------

    def test_hello_and_catalogue(self):
        hello = self.start()
        self.assertEqual(hello["protocol"], agent.PROTOCOL)
        self.assertTrue(hello["ollama"])
        self.assertFalse(hello["settings"]["onboarded"])
        tags = {m["tag"]: m for m in hello["models"]}
        self.assertTrue(tags["qwen3.5:4b"]["installed"])
        self.assertFalse(tags["qwen3.5:9b"]["installed"])
        self.assertIn(hello["recommended"], tags)
        self.assertEqual(hello["settings"]["model"], hello["recommended"])
        self.assertGreater(hello["ramGB"], 0)

    def test_answer_streams_and_wakes_the_model(self):
        self.start({"model": "qwen3.5:4b", "onboarded": True})
        self.agent.send(op="ask", text="Hola")
        events = self.agent.until_done()
        kinds = [e["ev"] for e in events]  # the poller's "state" may come in between
        self.assertLess(kinds.index("start"), kinds.index("token"))
        self.assertEqual(self.text_of(events).strip(), "¡Hola! Soy Nilo.")
        done = events[-1]
        self.assertEqual(done["stats"]["tokens"], 12)
        self.assertTrue(any(e["ev"] == "state" and e["loaded"] for e in self.agent.log))
        body = self.ollama.chats[-1]
        self.assertEqual(body["keep_alive"], "5m")
        self.assertEqual(body["options"], {"num_ctx": 8192})
        self.assertIs(body["think"], False)
        self.assertEqual(body["messages"][0]["role"], "system")
        self.assertIn("Nilo", body["messages"][0]["content"])
        self.assertEqual({t["function"]["name"] for t in body["tools"]}, {"web_search", "open_url", "system_info"})

    def test_web_search_tool(self):
        self.start({"model": "qwen3.5:4b", "onboarded": True})
        self.agent.send(op="ask", text="Busca la última versión de NixOS")
        events = self.agent.until_done()
        tools = [e for e in events if e["ev"] == "tool"]
        self.assertEqual([t["status"] for t in tools], ["running", "done"])
        self.assertEqual(tools[1]["count"], 1)
        self.assertIn("[NixOS 26.05 released](https://nixos.org/blog/26.05)", self.text_of(events))
        with open(os.path.join(self.dir, "ddgr-args")) as f:
            args = f.read().split("\n")
        self.assertEqual(args[:6], ["--json", "-n", "5", "-r", "es-es", "--"])
        result = json.loads(self.ollama.chats[-1]["messages"][-1]["content"])
        self.assertEqual(result["results"][0]["snippet"], "The new release is out.")

    def test_no_tools_without_access(self):
        self.start({"model": "qwen3.5:4b", "onboarded": True, "web": False, "system": False})
        self.agent.send(op="ask", text="Hola")
        self.agent.until_done()
        self.assertNotIn("tools", self.ollama.chats[-1])
        self.assertIn("No tienes acceso a internet", self.ollama.chats[-1]["messages"][0]["content"])

    def test_model_without_tools(self):
        self.ollama.no_tools.add("qwen3.5:4b")
        self.start({"model": "qwen3.5:4b", "onboarded": True})
        self.agent.send(op="ask", text="Hola")
        events = self.agent.until_done()
        self.assertIn("Soy Nilo", self.text_of(events))
        self.assertNotIn("tools", self.ollama.chats[-1])

    def make_repo(self):
        remote = os.path.join(self.dir, "remote.git")
        repo = os.path.join(self.dir, "repo")
        git(self.dir, "init", "-q", "--bare", remote)
        git(self.dir, "init", "-q", "-b", "main", repo)
        git(repo, "config", "user.email", "test@example.com")
        git(repo, "config", "user.name", "Test")
        with open(os.path.join(repo, "a.txt"), "w") as f:
            f.write("one\n")
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "First")
        git(repo, "remote", "add", "origin", remote)
        git(repo, "push", "-q", "-u", "origin", "main")
        with open(os.path.join(repo, "notes.md"), "w") as f:
            f.write("notes\n")
        with open(os.path.join(repo, "a.txt"), "a") as f:
            f.write("two\n")
        return repo, remote

    def test_git_commit_confirmed(self):
        repo, remote = self.make_repo()
        self.start({"model": "qwen3.5:4b", "onboarded": True, "git": True, "repo": repo})
        confirms = []

        def accept(event):
            confirms.append(event)
            self.agent.send(op="confirm", id=event["id"], ok=True)

        self.agent.on_confirm = accept
        self.agent.send(op="ask", text="Sube los cambios")
        events = self.agent.until_done()
        self.assertEqual(len(confirms), 1)
        confirm = confirms[0]
        self.assertEqual(confirm["action"], "commit-push")
        self.assertEqual(confirm["branch"], "main")
        self.assertEqual(confirm["remote"], "origin/main")
        self.assertEqual(confirm["message"], "Add notes")
        self.assertEqual(sorted(confirm["files"]), [" M a.txt", "?? notes.md"])
        self.assertEqual(git(repo, "log", "-1", "--pretty=%s"), "Add notes")
        self.assertEqual(git(remote, "rev-parse", "main"), git(repo, "rev-parse", "HEAD"))
        done = [e for e in events if e["ev"] == "tool" and e["status"] == "done"]
        self.assertTrue(done[-1]["pushed"])
        self.assertEqual(done[-1]["commit"], git(repo, "rev-parse", "--short", "HEAD"))
        self.assertIn("Hecho.", self.text_of(events))
        tool_message = self.ollama.chats[-1]["messages"][-1]
        self.assertEqual(tool_message.get("tool_call_id"), "call_7")
        status = json.loads(self.ollama.chats[-2]["messages"][-1]["content"])
        self.assertEqual(status["recentCommits"], ["First"])
        self.assertIn("+two", status["diff"])

    def test_git_commit_declined(self):
        repo, _ = self.make_repo()
        self.start({"model": "qwen3.5:4b", "onboarded": True, "git": True, "repo": repo})
        self.agent.on_confirm = lambda event: self.agent.send(op="confirm", id=event["id"], ok=False)
        self.agent.send(op="ask", text="Sube los cambios")
        events = self.agent.until_done()
        self.assertEqual(git(repo, "log", "-1", "--pretty=%s"), "First")
        done = [e for e in events if e["ev"] == "tool" and e["status"] == "done"]
        self.assertTrue(done[-1]["declined"])
        self.assertIn("No he hecho nada.", self.text_of(events))

    def test_git_not_allowed(self):
        repo, _ = self.make_repo()
        self.start({"model": "qwen3.5:4b", "onboarded": True, "git": False, "repo": repo})
        tools = agent.Tools(type("A", (), {"settings": {"git": False}, "config": {}})())
        result, facts = tools.run("git_commit", {"message": "x"}, agent.Cancel())
        self.assertIn("not allowed", result["error"])
        self.assertFalse(facts["ok"])

    def test_stop(self):
        self.start({"model": "qwen3.5:4b", "onboarded": True})
        self.agent.send(op="ask", text="Algo lento")
        self.agent.wait("token")
        self.agent.send(op="stop")
        events = self.agent.until_done(timeout=5)
        self.assertTrue(events[-1].get("cancelled"))
        self.agent.send(op="ask", text="Hola")
        events = self.agent.until_done()
        self.assertIn("Soy Nilo", self.text_of(events))
        messages = self.ollama.chats[-1]["messages"]
        self.assertEqual([m["role"] for m in messages], ["system", "user", "assistant", "user"])

    def test_reset_forgets(self):
        self.start({"model": "qwen3.5:4b", "onboarded": True})
        self.agent.send(op="ask", text="Hola")
        self.agent.until_done()
        self.agent.send(op="reset")
        self.agent.wait("reset")
        self.agent.send(op="ask", text="Hola otra vez")
        self.agent.until_done()
        self.assertEqual([m["role"] for m in self.ollama.chats[-1]["messages"]], ["system", "user"])

    def test_busy(self):
        self.start({"model": "qwen3.5:4b", "onboarded": True})
        self.agent.send(op="ask", text="Algo lento")
        self.agent.wait("token")
        self.agent.send(op="ask", text="Hola")
        self.assertEqual(self.agent.wait("error")["code"], "busy")
        self.agent.send(op="stop")
        self.agent.until_done()

    def test_settings_persist(self):
        self.start()
        self.agent.send(op="set", key="keepAlive", value="15")
        self.assertEqual(self.agent.wait("settings")["settings"]["keepAlive"], 15)
        self.agent.send(op="set", key="model", value="qwen3.5:9b")
        self.agent.wait("settings", where=lambda e: e["settings"]["model"] == "qwen3.5:9b")
        self.agent.send(op="set", key="onboarded", value=True)
        self.agent.wait("settings", where=lambda e: e["settings"]["onboarded"])
        self.agent.send(op="set", key="model", value="rm -rf /")
        self.assertEqual(self.agent.wait("error")["code"], "bad-request")
        self.agent.send(op="set", key="repo", value=self.dir)
        self.assertEqual(self.agent.wait("error")["code"], "bad-repo")
        with open(self.state) as f:
            saved = json.load(f)
        self.assertEqual((saved["keepAlive"], saved["model"], saved["onboarded"]), (15, "qwen3.5:9b", True))
        self.agent.close()
        hello = self.start()
        self.assertEqual(hello["settings"]["model"], "qwen3.5:9b")

    def test_new_repo_asks_again(self):
        repo = self.make_notes_repo()
        other = os.path.join(self.dir, "other")
        os.makedirs(os.path.join(other, ".git"))
        self.start({"model": "qwen3.5:4b", "onboarded": True, "git": True, "write": True, "repo": repo})
        self.agent.send(op="set", key="repo", value=repo + "/")
        same = self.agent.wait("settings")["settings"]
        self.assertEqual((same["git"], same["write"]), (True, True))
        self.agent.send(op="set", key="repo", value=other)
        moved = self.agent.wait("settings")["settings"]
        self.assertEqual((moved["repo"], moved["git"], moved["write"]), (other, False, False))

    def test_pull_and_delete(self):
        self.start()
        self.agent.send(op="pull", model="qwen3.5:9b")
        success = self.agent.wait("pull", where=lambda e: e["status"] == "success")
        self.assertEqual((success["completed"], success["total"]), (1010, 1010))
        progress = [e for e in self.agent.log if e["ev"] == "pull" and e.get("total")]
        self.assertTrue(all(e["completed"] <= e["total"] for e in progress))
        models = self.agent.wait("models")
        self.assertTrue({m["tag"]: m for m in models["models"]}["qwen3.5:9b"]["installed"])
        self.agent.send(op="delete", model="qwen3.5:9b")
        models = self.agent.wait("models")
        self.assertFalse({m["tag"]: m for m in models["models"]}["qwen3.5:9b"]["installed"])

    def test_missing_model(self):
        self.start({"model": "qwen3.5:9b", "onboarded": True})
        self.agent.send(op="ask", text="Hola")
        events = self.agent.until_done()
        self.assertEqual([e["code"] for e in events if e["ev"] == "error"], ["model-missing"])
        self.assertTrue(events[-1]["failed"])

    def test_warm_and_sleep(self):
        self.start({"model": "qwen3.5:4b", "onboarded": True, "keepAlive": 1})
        self.agent.send(op="warm")
        state = self.agent.wait("state", where=lambda e: e["loaded"])
        states = [(e["loading"], e["loaded"]) for e in self.agent.log if e["ev"] == "state"]
        woke = states[states.index((True, False)):states.index((False, True)) + 1]
        self.assertNotIn((False, False), woke, states)  # it never looks asleep while waking
        self.assertEqual(state["model"], "qwen3.5:4b")
        self.assertEqual(state["gpu"], 100)
        self.assertGreater(state["expires"], time.time())
        self.assertEqual(self.ollama.loads[-1]["keep_alive"], "1m")
        self.assertEqual(self.ollama.loads[-1]["options"], {"num_ctx": 8192})
        self.agent.send(op="sleep")
        self.agent.wait("state", where=lambda e: not e["loaded"])
        self.assertEqual(self.ollama.loads[-1]["keep_alive"], 0)

    def test_ollama_down(self):
        self.write_config(ollama="http://127.0.0.1:9")
        hello = self.start({"model": "qwen3.5:4b", "onboarded": True})
        self.assertFalse(hello["ollama"])
        self.agent.send(op="ask", text="Hola")
        events = self.agent.until_done()
        self.assertEqual([e["code"] for e in events if e["ev"] == "error"], ["ollama-down"])

    def test_ollama_comes_up_later(self):
        self.ollama.down = True
        hello = self.start({"model": "qwen3.5:4b", "onboarded": True})
        self.assertFalse(hello["ollama"])
        self.ollama.down = False
        self.agent.send(op="status")
        models = self.agent.wait("models", where=lambda e: e["ollama"])
        self.assertTrue({m["tag"]: m for m in models["models"]}["qwen3.5:4b"]["installed"])

    def free_port(self):
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            return probe.getsockname()[1]

    def test_ollama_down_is_started(self):
        port = self.free_port()
        self.write_config(ollama=f"http://127.0.0.1:{port}")
        late = {}

        def come_up():
            mark = os.path.join(self.dir, "started")
            for _ in range(200):
                if os.path.exists(mark):
                    late["server"] = FakeOllama(port)
                    threading.Thread(target=late["server"].serve_forever, daemon=True).start()
                    return
                time.sleep(0.05)

        threading.Thread(target=come_up, daemon=True).start()
        hello = self.start({"model": "qwen3.5:4b", "onboarded": True})
        self.assertFalse(hello["ollama"])
        starting = self.agent.wait("ollama", where=lambda e: e.get("starting"))
        self.assertEqual((starting["activeState"], starting["result"]), ("failed", "exit-code"))
        self.assertIn("address already in use", starting["log"][0])
        self.agent.wait("ollama", where=lambda e: e.get("up"))
        models = self.agent.wait("models", where=lambda e: e["ollama"])
        self.assertTrue({m["tag"]: m for m in models["models"]}["qwen3.5:4b"]["installed"])
        with open(os.path.join(self.dir, "started")) as f:
            self.assertEqual(f.read().split(), ["--no-ask-password", "start", "ollama.service"])
        late["server"].shutdown()
        late["server"].server_close()

    def test_pull_when_ollama_cannot_start(self):
        self.write_config(ollama=f"http://127.0.0.1:{self.free_port()}")
        open(os.path.join(self.dir, "start-fails"), "w").close()
        self.start({"model": "qwen3.5:4b", "onboarded": True})
        failed = self.agent.wait("ollama", where=lambda e: e.get("up") is False)
        self.assertEqual(failed["error"], "Job failed")
        self.agent.send(op="pull", model="qwen3.5:9b")
        pull = self.agent.wait("pull", where=lambda e: e["status"] == "error")
        self.assertEqual(pull["code"], "ollama-down")
        self.agent.send(op="startOllama")
        self.agent.wait("ollama", where=lambda e: e.get("starting"))
        self.agent.wait("ollama", where=lambda e: e.get("up") is False)
        with open(os.path.join(self.dir, "started")) as f:
            self.assertEqual(f.read().splitlines()[-1].split(), ["start", "ollama.service"])  # may ask polkit

    def make_notes_repo(self):
        repo, _ = self.make_repo()
        with open(os.path.join(repo, ".gitignore"), "w") as f:
            f.write("secret.txt\n")
        with open(os.path.join(repo, "secret.txt"), "w") as f:
            f.write("x\n")
        return repo

    def test_edit_file_confirmed(self):
        repo = self.make_notes_repo()
        self.start({"model": "qwen3.5:4b", "onboarded": True, "write": True, "repo": repo})
        confirms = []

        def accept(event):
            confirms.append(event)
            self.agent.send(op="confirm", id=event["id"], ok=True)

        self.agent.on_confirm = accept
        self.agent.send(op="ask", text="Edita las notas")
        events = self.agent.until_done()
        self.assertEqual(len(confirms), 1)
        card = confirms[0]
        self.assertEqual((card["action"], card["path"], card["added"], card["removed"]), ("edit", "notes.md", 1, 1))
        self.assertEqual([(d["t"], d["s"]) for d in card["diff"] if d["t"] != "@"],
                         [("-", "notes"), ("+", "Notas de Nilo")])
        with open(os.path.join(repo, "notes.md")) as f:
            self.assertEqual(f.read(), "Notas de Nilo\n")
        self.assertIn("Cambiado.", self.text_of(events))
        read = json.loads(self.ollama.chats[1]["messages"][-1]["content"])
        self.assertEqual((read["path"], read["text"], read["lines"]), ("notes.md", "notes\n", 1))
        tools = {t["function"]["name"] for t in self.ollama.chats[0]["tools"]}
        self.assertTrue({"list_files", "read_file", "edit_file", "write_file"} <= tools)
        self.assertIn("edit_file", self.ollama.chats[0]["messages"][0]["content"])

    def test_edit_file_declined(self):
        repo = self.make_notes_repo()
        self.start({"model": "qwen3.5:4b", "onboarded": True, "write": True, "repo": repo})
        self.agent.on_confirm = lambda event: self.agent.send(op="confirm", id=event["id"], ok=False)
        self.agent.send(op="ask", text="Edita las notas")
        events = self.agent.until_done()
        with open(os.path.join(repo, "notes.md")) as f:
            self.assertEqual(f.read(), "notes\n")
        done = [e for e in events if e["ev"] == "tool" and e["status"] == "done"]
        self.assertTrue(done[-1]["declined"])
        self.assertIn("No lo he cambiado.", self.text_of(events))

    def test_write_file_creates(self):
        repo = self.make_notes_repo()
        self.start({"model": "qwen3.5:4b", "onboarded": True, "write": True, "repo": repo})
        confirms = []

        def accept(event):
            confirms.append(event)
            self.agent.send(op="confirm", id=event["id"], ok=True)

        self.agent.on_confirm = accept
        self.agent.send(op="ask", text="Crea un documento")
        events = self.agent.until_done()
        self.assertEqual((confirms[0]["action"], confirms[0]["added"]), ("create", 3))
        with open(os.path.join(repo, "docs", "nuevo.md")) as f:
            self.assertEqual(f.read(), "# Nuevo\n\nHola.\n")
        done = [e for e in events if e["ev"] == "tool" and e["status"] == "done"]
        self.assertTrue(done[-1]["created"])

    def test_no_files_without_permission(self):
        repo = self.make_notes_repo()
        self.start({"model": "qwen3.5:4b", "onboarded": True, "git": True, "repo": repo})
        self.agent.send(op="ask", text="Hola")
        self.agent.until_done()
        tools = {t["function"]["name"] for t in self.ollama.chats[-1]["tools"]}
        self.assertFalse({"list_files", "read_file", "edit_file", "write_file"} & tools)
        tools = agent.Tools(type("A", (), {"settings": {"write": False}, "config": {}})())
        result, facts = tools.run("write_file", {"path": "x", "content": "y"}, agent.Cancel())
        self.assertIn("not allowed", result["error"])

    def test_paths_stay_inside(self):
        repo = self.make_notes_repo()
        os.symlink(self.dir, os.path.join(repo, "escape"))
        fake = type("A", (), {"settings": {"write": True, "repo": repo}, "config": {"git": shutil.which("git")}})()
        tools = agent.Tools(fake)
        for path in ("../config.json", "/etc/passwd", "escape/config.json", ".git/config", "~/x"):
            result, facts = tools.run("read_file", {"path": path}, agent.Cancel())
            self.assertIn("error", result, path)
        listed, _ = tools.run("list_files", {}, agent.Cancel())
        self.assertIn("notes.md", listed["files"])
        self.assertNotIn("secret.txt", listed["files"])
        with open(os.path.join(repo, "notes.md"), "w") as f:
            f.write("a\nb\na\n")
        twice, _ = tools.run("edit_file", {"path": "notes.md", "old": "a", "new": "c"}, agent.Cancel())
        self.assertIn("2 times", twice["error"])
        missing, _ = tools.run("edit_file", {"path": "notes.md", "old": "zzz", "new": "c"}, agent.Cancel())
        self.assertIn("not in the file", missing["error"])
        os.makedirs(os.path.join(repo, "sub", ".git"))
        with open(os.path.join(repo, "sub", ".git", "config"), "w") as f:
            f.write("x\n")
        nested, _ = tools.run("read_file", {"path": "sub/.git/config"}, agent.Cancel())
        self.assertIn(".git", nested["error"])
        # Not UTF-8: it can be read, but not changed (the rest would come back altered).
        with open(os.path.join(repo, "latin.txt"), "wb") as f:
            f.write("caf\xe9 y m\xe1s\n".encode("latin-1"))
        read, _ = tools.run("read_file", {"path": "latin.txt"}, agent.Cancel())
        self.assertIn("caf", read["text"])
        latin, _ = tools.run("edit_file", {"path": "latin.txt", "old": "caf", "new": "te"}, agent.Cancel())
        self.assertIn("UTF-8", latin["error"])
        with open(os.path.join(repo, "latin.txt"), "rb") as f:
            self.assertEqual(f.read(), "caf\xe9 y m\xe1s\n".encode("latin-1"))
        # Confirmed, a change keeps the file's line endings and mode.
        fake.ask_confirmation = lambda payload, cancel: True
        crlf = os.path.join(repo, "crlf.sh")
        with open(crlf, "wb") as f:
            f.write(b"#!/bin/sh\r\necho a\r\n")
        os.chmod(crlf, 0o755)
        done, _ = tools.run("edit_file", {"path": "crlf.sh", "old": "echo a", "new": "echo b"}, agent.Cancel())
        self.assertTrue(done["ok"])
        with open(crlf, "rb") as f:
            self.assertEqual(f.read(), b"#!/bin/sh\r\necho b\r\n")
        self.assertEqual(os.stat(crlf).st_mode & 0o777, 0o755)

    def test_read_file_in_parts(self):
        repo = self.make_notes_repo()
        with open(os.path.join(repo, "long.txt"), "w") as f:
            f.write("".join(f"line {i}\n" for i in range(1, 1001)))
        fake = type("A", (), {"settings": {"write": True, "repo": repo}, "config": {}})()
        first, _ = agent.Tools(fake).run("read_file", {"path": "long.txt"}, agent.Cancel())
        self.assertEqual((first["from_line"], first["to_line"], first["next_line"], first["lines"]), (1, 400, 401, 1000))
        last, _ = agent.Tools(fake).run("read_file", {"path": "long.txt", "from_line": 801}, agent.Cancel())
        self.assertNotIn("next_line", last)
        self.assertTrue(last["text"].endswith("line 1000\n"))

    def test_repos(self):
        home = os.path.join(self.dir, "home")
        for path in ("", "nixos-config", "code/codewizards", "code/apps/baitspace", "deep/a/b/c/hidden", ".cache/x"):
            os.makedirs(os.path.join(home, path, ".git"), exist_ok=True)
        os.makedirs(os.path.join(home, "code/node_modules/pkg/.git"))
        self.start(env=dict(os.environ, HOME=home))
        self.agent.send(op="repos")
        repos = self.agent.wait("repos")["repos"]
        self.assertEqual(sorted(repos), ["~/code/apps/baitspace", "~/code/codewizards", "~/nixos-config"])
        self.agent.send(op="set", key="repo", value=os.path.join(home, "code", "codewizards") + "/")
        self.assertEqual(self.agent.wait("settings")["settings"]["repo"], "~/code/codewizards")

    def test_bad_requests(self):
        self.start()
        self.agent.send(op="nope")
        self.assertEqual(self.agent.wait("error")["code"], "bad-request")
        self.agent.proc.stdin.write("not json\n")
        self.agent.proc.stdin.flush()
        self.assertEqual(self.agent.wait("error")["code"], "bad-request")


class UnitTest(unittest.TestCase):
    def test_parse_time(self):
        self.assertAlmostEqual(agent.parse_time("2026-10-29T10:00:00.123456789Z"), 1793268000.123456, places=3)
        self.assertAlmostEqual(agent.parse_time("2026-10-29T11:00:00+01:00"), 1793268000, places=3)
        self.assertIsNone(agent.parse_time(""))
        self.assertIsNone(agent.parse_time("yesterday"))

    def test_private_addresses_are_refused(self):
        for url in ("http://127.0.0.1:11434/api/ps", "http://localhost/", "http://192.168.1.1/", "file:///etc/passwd",
                    "http://[::1]/", "http://10.0.0.8/"):
            with self.assertRaises(agent.FetchError, msg=url):
                agent.check_public(url)

    def test_page_text(self):
        page = b"""<html><head><title> Release  notes </title><style>p{}</style></head>
        <body><nav>Home | Blog</nav><h1>NixOS 26.05</h1><p>It is <b>out</b>.</p>
        <ul><li>One</li><li>Two</li></ul><script>alert(1)</script><footer>(c)</footer></body></html>"""
        title, text = agent.page_text("text/html", None, page)
        self.assertEqual(title, "Release notes")
        self.assertEqual(text, "NixOS 26.05\nIt is out.\n- One\n- Two")
        with self.assertRaises(agent.FetchError):
            agent.page_text("application/pdf", None, b"%PDF")

    def test_prompt(self):
        settings = dict(agent.DEFAULT_SETTINGS, model="qwen3.5:9b", git=True)
        import datetime
        text = agent.build_prompt({"language": "es", "host": "thinkpad", "flake": "~/nixos-config"}, settings,
                                  now=datetime.datetime(2026, 10, 29, 9, 5))
        self.assertIn("jueves, 29 de octubre de 2026, las 09:05", text)
        self.assertIn("qwen3.5:9b", text)
        self.assertIn("web_search", text)
        self.assertIn("git_commit", text)
        self.assertIn("SUPER+I y la tecla Copilot", text)
        self.assertIn("--flake ~/nixos-config#thinkpad", text)
        english = agent.build_prompt({"language": "en"}, dict(settings, web=False),
                                     now=datetime.datetime(2026, 10, 29, 21, 30))
        self.assertIn("Thursday, October 29, 2026, 21:30", english)
        self.assertIn("no internet access", english)

    def test_recommended_model(self):
        a = agent.Agent.__new__(agent.Agent)
        a.config = {"models": MODELS + [{"tag": "qwen3.5:35b", "ram": 25}]}
        for ram, tag in ((6, "qwen3.5:0.8b"), (8, "qwen3.5:2b"), (16, "qwen3.5:4b"), (31.2, "qwen3.5:9b"),
                         (64, "qwen3.5:35b")):
            a.ram_gb = ram
            self.assertEqual(a.recommended(), tag, ram)


if __name__ == "__main__":
    unittest.main()
