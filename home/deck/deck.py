#!/usr/bin/env python3
# deck.py by poligle

import argparse
import base64
import collections
import errno
import fcntl
import functools
import hashlib
import hmac
import html.parser
import http.client
import http.server
import ipaddress
import json
import math
import mimetypes
import os
import re
import secrets
import shutil
import signal
import socket
import socketserver
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

API = 1
PORT = 64445                    # NIHIL on a phone's keypad
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 8
CODE_LIFETIME = 300             # seconds a code pairs
CODE_ATTEMPTS = 5
MAX_BODY = 4096
TASKS_MAX = 256 * 1024     # a phone's whole kanban
VECTOR_MAX = 100 * 1024 * 1024
VECTOR_TEXT = 256 * 1024
VECTOR_WAIT = 50
VECTOR_LIVE = 120
CHUNK = 64 * 1024
COVER_MAX = 4 * 1024 * 1024
CARDS_MAX = 1000
FAIL_WINDOW = 60
FAIL_LIMIT = 10
FAIL_KEPT = 1024
CONNECTIONS = 32
SEEN_EVERY = 60
ICON_SIZE = 128
APPS_FOR = 20
APP_ID = re.compile(r"[A-Za-z0-9._+-]{1,160}")
MIME = re.compile(r"[a-z0-9][a-z0-9!#$&^_.+-]{0,63}/[a-z0-9][a-z0-9!#$&^_.+-]{0,126}")
EXTENSIONS = {"text/plain": ".txt", "image/png": ".png", "image/jpeg": ".jpg", "image/gif": ".gif",
              "image/webp": ".webp", "video/mp4": ".mp4", "video/webm": ".webm", "video/quicktime": ".mov"}
VIRTUAL = re.compile(r"(docker|br-|virbr|veth|vnet|lxcbr|lxdbr|podman|cni|flannel)")
ACTIONS = {
    "media": ("toggle", "next", "previous"),
    "volume": ("up", "down", "mute"),
    "caffeine": ("on", "off", "toggle"),
    "night": ("on", "off", "toggle"),
}


def now():
    return time.time()


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def digest(token):
    return hashlib.sha256(token.encode()).hexdigest()


def home_dir(variable, fallback):
    return os.environ.get(variable) or os.path.join(os.path.expanduser("~"), fallback)


def state_dir():
    return os.path.join(home_dir("XDG_STATE_HOME", ".local/state"), "nihil", "deck")


def cache_dir():
    return os.path.join(home_dir("XDG_CACHE_HOME", ".cache"), "nihil", "deck")


def control_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR") or state_dir()
    return os.path.join(runtime, "nihil-deck.sock")


def write_private(path, text):
    folder = os.path.dirname(path)
    os.makedirs(folder, mode=0o700, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=folder, prefix=".deck-")
    try:
        with os.fdopen(fd, "w") as file:
            file.write(text)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def ensure_certificate(folder, openssl):
    cert = os.path.join(folder, "cert.pem")
    key = os.path.join(folder, "key.pem")
    if os.path.isfile(cert) and os.path.isfile(key):
        return cert, key
    os.makedirs(folder, mode=0o700, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=folder, prefix=".cert-") as work:
        new_cert = os.path.join(work, "cert.pem")
        new_key = os.path.join(work, "key.pem")
        old = os.umask(0o077)
        try:
            subprocess.run([openssl, "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256",
                            "-nodes", "-days", "3650", "-subj", "/CN=nihil-deck",
                            "-keyout", new_key, "-out", new_cert],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=60)
        finally:
            os.umask(old)
        os.chmod(new_key, 0o600)
        os.replace(new_key, key)
        os.replace(new_cert, cert)
    return cert, key


def _tlv(data, at):
    tag = data[at]
    length = data[at + 1]
    at += 2
    if length & 0x80:
        count = length & 0x7F
        length = int.from_bytes(data[at:at + count], "big")
        at += count
    return tag, at, at + length


def public_key_info(der):
    _, start, _ = _tlv(der, 0)
    _, tbs, tbs_end = _tlv(der, start)
    fields = []
    at = tbs
    while at < tbs_end:
        tag, _, end = _tlv(der, at)
        fields.append((tag, at, end))
        at = end
    if fields and fields[0][0] == 0xA0:
        fields = fields[1:]
    if len(fields) < 6 or fields[5][0] != 0x30:
        raise ValueError("not a certificate this can read")
    _, begin, end = fields[5]
    return der[begin:end]


def pin_of(cert_path):
    with open(cert_path) as file:
        der = ssl.PEM_cert_to_DER_cert(file.read())
    return b64url(hashlib.sha256(public_key_info(der)).digest())


class Devices:

    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()
        self.items = []
        self.saved = 0
        try:
            with open(path) as file:
                found = json.load(file)
            self.items = [item for item in found.get("devices", [])
                          if isinstance(item, dict) and isinstance(item.get("token"), str) and isinstance(item.get("id"), str)]
        except (FileNotFoundError, ValueError, AttributeError):
            self.items = []

    def _save(self):
        write_private(self.path, json.dumps({"devices": self.items}, indent=2) + "\n")
        self.saved = now()

    def add(self, name):
        token = secrets.token_urlsafe(32)
        with self.lock:
            ids = {item["id"] for item in self.items}
            device = secrets.token_hex(4)
            while device in ids:
                device = secrets.token_hex(4)
            moment = int(now())
            self.items.append({"id": device, "name": name, "token": digest(token), "paired": moment, "seen": moment})
            self._save()
        return device, token

    def find(self, token):
        if not token:
            return None
        wanted = digest(token)
        found = None
        with self.lock:
            for item in self.items:
                if hmac.compare_digest(item["token"], wanted):
                    found = item
        return found

    def touch(self, device):
        with self.lock:
            device["seen"] = int(now())
            if now() - self.saved >= SEEN_EVERY:
                self._save()

    def flush(self):
        with self.lock:
            if self.items or os.path.exists(self.path):
                self._save()

    def forget(self, device):
        with self.lock:
            kept = [item for item in self.items if device != "all" and item["id"] != device]
            if len(kept) == len(self.items):
                return False
            self.items = kept
            self._save()
        return True

    def listing(self):
        with self.lock:
            return [{key: item.get(key) for key in ("id", "name", "paired", "seen")} for item in self.items]


class Pairing:

    def __init__(self):
        self.lock = threading.Lock()
        self.code = None
        self.expires = 0
        self.attempts = 0

    def open(self):
        with self.lock:
            self.code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
            self.expires = now() + CODE_LIFETIME
            self.attempts = 0
            return self.code, self.expires

    def close(self):
        with self.lock:
            self.code = None

    @property
    def open_now(self):
        with self.lock:
            return self.code is not None and now() <= self.expires

    def take(self, code):
        with self.lock:
            if self.code is None:
                return "closed"
            if now() > self.expires:
                self.code = None
                return "expired"
            given = str(code or "").strip().upper()
            if not hmac.compare_digest(given.encode(), self.code.encode()):
                self.attempts += 1
                if self.attempts >= CODE_ATTEMPTS:
                    self.code = None
                return "wrong"
            self.code = None
            return "ok"


class Throttle:

    def __init__(self):
        self.lock = threading.Lock()
        self.failures = {}

    def _recent(self, address):
        cutoff = now() - FAIL_WINDOW
        times = [moment for moment in self.failures.get(address, []) if moment > cutoff]
        if times:
            self.failures[address] = times
        else:
            self.failures.pop(address, None)
        return times

    def blocked(self, address):
        with self.lock:
            return len(self._recent(address)) >= FAIL_LIMIT

    def fail(self, address):
        with self.lock:
            self.failures.setdefault(address, []).append(now())
            self._recent(address)
            if len(self.failures) > FAIL_KEPT:
                for other in list(self.failures):
                    self._recent(other)


def valid_url(url):
    if not isinstance(url, str) or not 0 < len(url) <= 2048:
        return False
    if any(ord(char) < 0x21 or ord(char) == 0x7F for char in url):
        return False
    try:
        parts = urllib.parse.urlsplit(url)
    except ValueError:
        return False
    return parts.scheme in ("http", "https") and bool(parts.hostname)


def clean_name(name, fallback):
    text = "".join(char for char in str(name or "") if char.isprintable()).strip()
    return text[:40] or fallback


class Session:

    def __init__(self, config):
        self.config = config
        self.lock = threading.Lock()
        self.cached = None
        self.cached_at = 0

    def run(self, command, timeout=6):
        try:
            done = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                  errors="replace", timeout=timeout)
        except (OSError, subprocess.SubprocessError):
            return None
        return done.stdout.strip() if done.returncode == 0 else None

    cover_cache = None

    def ipc(self, *arguments):
        return self.run([self.config["ipc"], *arguments])

    def apps(self, fresh=False):
        with self.lock:
            if not fresh and self.cached is not None and now() - self.cached_at < APPS_FOR:
                return self.cached
        text = self.ipc("apps", "list")
        if text is None:
            return None
        try:
            found = json.loads(text)
        except ValueError:
            return None
        listed = []
        for entry in found if isinstance(found, list) else []:
            if not isinstance(entry, dict):
                continue
            app, name = entry.get("id"), entry.get("name")
            if isinstance(app, str) and APP_ID.fullmatch(app) and isinstance(name, str) and name:
                icon = entry.get("icon") if isinstance(entry.get("icon"), str) else ""
                listed.append({"id": app, "name": name, "icon": icon})
        with self.lock:
            self.cached, self.cached_at = listed, now()
        return listed

    def app(self, app):
        if not isinstance(app, str) or not APP_ID.fullmatch(app):
            return None
        for fresh in (False, True):
            listed = self.apps(fresh)
            if listed is None:
                return None
            for entry in listed:
                if entry["id"] == app:
                    return entry
        return None

    def launch(self, app):
        if self.app(app) is None:
            return "unknown"
        answer = self.ipc("apps", "launch", app)
        return "ok" if answer == "ok" else "unknown" if answer == "unknown" else "shell"

    def open_url(self, url):
        if not valid_url(url):
            return "invalid"
        answer = self.ipc("apps", "url", url)
        return "ok" if answer == "ok" else "invalid" if answer == "invalid" else "shell"

    def media(self, action):
        return self.ipc("media", action) is not None

    def playing(self):
        text = self.ipc("media", "now")
        if not text:
            return None
        try:
            found = json.loads(text)
        except ValueError:
            return None
        if not isinstance(found, dict):
            return None
        art = str(found.pop("art", "") or "")
        found["cover"] = hashlib.sha256(art.encode()).hexdigest()[:16] if art else ""
        return found

    def cover(self, token):
        text = self.ipc("media", "now")
        try:
            art = str(json.loads(text or "null").get("art") or "")
        except (ValueError, AttributeError):
            return None
        if not art or hashlib.sha256(art.encode()).hexdigest()[:16] != token:
            return None
        with self.lock:
            if self.cover_cache and self.cover_cache[0] == art:
                return self.cover_cache[1]
        found = None
        try:
            if art.startswith("file://"):
                local = urllib.parse.unquote(urllib.parse.urlsplit(art).path)
                if os.path.getsize(local) <= COVER_MAX:
                    with open(local, "rb") as file:
                        found = as_image(file.read(), self.config.get("rsvg", "rsvg-convert"))
            elif valid_url(art):
                found = as_image(fetch(art, COVER_MAX)[1], self.config.get("rsvg", "rsvg-convert"))
        except (OSError, ValueError, urllib.error.URLError, http.client.HTTPException):
            found = None
        with self.lock:
            self.cover_cache = (art, found)
        return found

    def tasks(self, board=None):
        text = self.ipc("tasks", "state") if board is None else self.ipc("tasks", "sync", json.dumps(board))
        try:
            found = json.loads(text or "")
        except ValueError:
            return None
        return found if isinstance(found, dict) else None

    def volume(self, action=None):
        if action is not None and self.run([self.config["volume"], action]) is None:
            return None
        text = self.run([self.config["wpctl"], "get-volume", "@DEFAULT_AUDIO_SINK@"])
        found = re.search(r"Volume:\s*([0-9.]+)", text or "")
        if not found:
            return None
        return {"level": round(float(found.group(1)) * 100), "muted": "[MUTED]" in text}

    def lock_screen(self):
        return self.ipc("session", "lock") is not None

    def toggles(self):
        try:
            found = json.loads(self.ipc("toggles", "state") or "")
        except ValueError:
            return {}
        if not isinstance(found, dict):
            return {}
        return {key: found[key] for key in ("caffeine", "night") if isinstance(found.get(key), bool)}

    def switch(self, kind, action):
        if self.ipc(kind, action) is None:
            return None
        return self.toggles().get(kind)

    def notify(self, title, body):
        command = [self.config["notify"], "-a", "NIHIL", title]
        if body:
            command.append(body)
        self.run(command)


def data_dirs():
    dirs = [home_dir("XDG_DATA_HOME", ".local/share")]
    dirs += [d for d in os.environ.get("XDG_DATA_DIRS", "").split(":") if d]
    user = os.environ.get("USER", "")
    dirs += [os.path.expanduser("~/.nix-profile/share"), f"/etc/profiles/per-user/{user}/share",
             "/run/current-system/sw/share", "/usr/local/share", "/usr/share"]
    seen, ordered = set(), []
    for d in dirs:
        if d not in seen:
            seen.add(d)
            ordered.append(d)
    return ordered


@functools.lru_cache(maxsize=64)
def theme_index(root):
    inherits, directories, sizes, kinds = [], [], {}, {}
    section = None
    try:
        with open(os.path.join(root, "index.theme"), encoding="utf-8", errors="replace") as file:
            for raw in file:
                line = raw.strip()
                if line.startswith("[") and line.endswith("]"):
                    section = line[1:-1]
                elif "=" in line:
                    key, value = (part.strip() for part in line.split("=", 1))
                    if section == "Icon Theme" and key == "Inherits":
                        inherits = [name.strip() for name in value.split(",") if name.strip()]
                    elif section == "Icon Theme" and key in ("Directories", "ScaledDirectories"):
                        directories += [name.strip() for name in value.split(",") if name.strip()]
                    elif section and key == "Size" and value.isdigit():
                        sizes[section] = int(value)
                    elif section and key == "Type":
                        kinds[section] = value
    except OSError:
        return (), ()
    unique = list(dict.fromkeys(directories))
    def order(directory):
        size = sizes.get(directory, 0)
        scalable = kinds.get(directory) == "Scalable" or "scalable" in directory
        return (0 if scalable else 1, size < ICON_SIZE, abs(size - ICON_SIZE))
    unique.sort(key=order)
    return tuple(inherits), tuple(unique)


def icon_file(name, theme, dirs=None):
    if not name:
        return None
    if os.path.isabs(name):
        return name if os.path.isfile(name) and name.endswith((".png", ".svg")) else None
    if "/" in name or name.startswith("."):
        return None
    dirs = dirs or data_dirs()
    queue, visited = [theme, "hicolor"] if theme else ["hicolor"], set()
    while queue:
        current = queue.pop(0)
        if not current or current in visited:
            continue
        visited.add(current)
        for base in dirs:
            root = os.path.join(base, "icons", current)
            if not os.path.isdir(root):
                continue
            inherits, directories = theme_index(root)
            for directory in directories:
                for extension in (".svg", ".png"):
                    path = os.path.join(root, directory, name + extension)
                    if os.path.isfile(path):
                        return path
            queue[0:0] = [parent for parent in inherits if parent not in visited and parent != "hicolor"]
    for base in dirs:
        for extension in (".png", ".svg"):
            path = os.path.join(base, "pixmaps", name + extension)
            if os.path.isfile(path):
                return path
    return None


def icon_png(path, rsvg, cache):
    if path.endswith(".png"):
        return path
    stamp = hashlib.sha256(f"{os.path.realpath(path)}:{os.path.getmtime(path)}:{ICON_SIZE}".encode()).hexdigest()[:24]
    out = os.path.join(cache, stamp + ".png")
    if os.path.isfile(out):
        return out
    os.makedirs(cache, mode=0o700, exist_ok=True)
    temporary = out + ".new"
    try:
        subprocess.run([rsvg, "-w", str(ICON_SIZE), "-h", str(ICON_SIZE), "-a", "-f", "png", "-o", temporary, path],
                       check=True, capture_output=True, timeout=10)
        os.replace(temporary, out)
    except (OSError, subprocess.SubprocessError):
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        return None
    return out


def clean_board(body):
    cards = body.get("cards", [])
    removed = body.get("removed", {})
    if not isinstance(cards, list) or not isinstance(removed, dict) or len(cards) > CARDS_MAX or len(removed) > 10 * CARDS_MAX:
        return None
    clean = []
    for card in cards:
        if not isinstance(card, dict):
            return None
        ident, text, column = card.get("id"), card.get("text"), card.get("column")
        stamps = (card.get("textStamp"), card.get("placeStamp"))
        if not isinstance(ident, str) or not 0 < len(ident) <= 64 or not isinstance(text, str) or not text.strip():
            return None
        if not isinstance(column, int) or isinstance(column, bool) or not 0 <= column <= 2:
            return None
        if not all(isinstance(t, int) and not isinstance(t, bool) and t >= 0 for t in stamps):
            return None
        kept = {"id": ident, "text": " ".join(text.split())[:160], "column": column,
                "textStamp": stamps[0], "placeStamp": stamps[1]}
        rank = card.get("rank")
        if rank is not None:
            if not isinstance(rank, (int, float)) or isinstance(rank, bool) or not math.isfinite(rank):
                return None
            kept["rank"] = rank
        clean.append(kept)
    gone = {}
    for ident, when in removed.items():
        if not isinstance(ident, str) or not 0 < len(ident) <= 64 or not isinstance(when, int) or isinstance(when, bool) or when < 0:
            return None
        gone[ident] = when
    return {"cards": clean, "removed": gone}


EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT = 0
BTN_TOUCH = 330
FINGER_TOOLS = (325, 333, 334, 335, 328)
ABS_X, ABS_Y = 0, 1
ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 47, 53, 54, 57
INPUT_PROP_POINTER = 0
BUS_VIRTUAL = 6
TRACKPAD_NAME = "NIHIL deck trackpad"
TRACKPAD_PROTOCOL = "nihil-trackpad"
TRACKPAD_SLOTS = 5
TRACKPAD_IDLE = 4
TRACKPAD_SETTLE = 0.25
TRACKPAD_DELAY = 0.025
TOUCH_FRAME, KEEPALIVE = 1, 2
MAX_FINGERS = 10


def _ioc(number, size=0):
    return ((1 << 30) if size else 0) | (size << 16) | (ord("U") << 8) | number


UI_DEV_CREATE = _ioc(1)
UI_DEV_DESTROY = _ioc(2)
UI_DEV_SETUP = _ioc(3, 92)      # struct uinput_setup
UI_ABS_SETUP = _ioc(4, 28)      # struct uinput_abs_setup
UI_SET_EVBIT = _ioc(100, 4)
UI_SET_KEYBIT = _ioc(101, 4)
UI_SET_ABSBIT = _ioc(103, 4)
UI_SET_PROPBIT = _ioc(110, 4)


class Uinput:

    def __init__(self, path, width, height, resolution):
        self.width, self.height = width, height
        self.fd = os.open(path, os.O_WRONLY | os.O_NONBLOCK | os.O_CLOEXEC)
        try:
            for kind in (EV_KEY, EV_ABS):
                fcntl.ioctl(self.fd, UI_SET_EVBIT, kind)
            for key in (BTN_TOUCH, *FINGER_TOOLS):
                fcntl.ioctl(self.fd, UI_SET_KEYBIT, key)
            fcntl.ioctl(self.fd, UI_SET_PROPBIT, INPUT_PROP_POINTER)
            for code, top in ((ABS_X, width), (ABS_Y, height), (ABS_MT_POSITION_X, width), (ABS_MT_POSITION_Y, height)):
                self.axis(code, top, resolution)
            self.axis(ABS_MT_SLOT, TRACKPAD_SLOTS - 1, 0)
            self.axis(ABS_MT_TRACKING_ID, 65535, 0)
            setup = struct.pack("=4H80sI", BUS_VIRTUAL, 0x6E69, 0x6C64, 1, TRACKPAD_NAME.encode(), 0)
            fcntl.ioctl(self.fd, UI_DEV_SETUP, setup)
            fcntl.ioctl(self.fd, UI_DEV_CREATE)
        except OSError:
            os.close(self.fd)
            raise

    def axis(self, code, top, resolution):
        fcntl.ioctl(self.fd, UI_SET_ABSBIT, code)
        fcntl.ioctl(self.fd, UI_ABS_SETUP, struct.pack("=HH6i", code, 0, 0, 0, top, 0, 0, resolution))

    def write(self, events):
        os.write(self.fd, b"".join(struct.pack("@llHHi", 0, 0, kind, code, value) for kind, code, value in events))

    def close(self):
        try:
            fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        except OSError:
            pass
        os.close(self.fd)


class Fingers:

    def __init__(self):
        self.slots = [None] * TRACKPAD_SLOTS    # [finger, tracking id, x, y]
        self.slot = -1
        self.next_id = 0
        self.count = 0
        self.primary = None

    def frame(self, contacts):
        events = []
        touching = {finger for finger, _, _ in contacts}
        for index, held in enumerate(self.slots):
            if held is not None and held[0] not in touching:
                self.select(events, index)
                events.append((EV_ABS, ABS_MT_TRACKING_ID, -1))
                self.slots[index] = None
        for finger, x, y in contacts:
            index = next((i for i, held in enumerate(self.slots) if held is not None and held[0] == finger), None)
            if index is None:
                index = next((i for i, held in enumerate(self.slots) if held is None), None)
                if index is None:
                    continue
                self.select(events, index)
                events += [(EV_ABS, ABS_MT_TRACKING_ID, self.next_id), (EV_ABS, ABS_MT_POSITION_X, x), (EV_ABS, ABS_MT_POSITION_Y, y)]
                self.slots[index] = [finger, self.next_id, x, y]
                self.next_id = (self.next_id + 1) % 65536
                continue
            held = self.slots[index]
            if held[2] != x or held[3] != y:
                self.select(events, index)
                if held[2] != x:
                    events.append((EV_ABS, ABS_MT_POSITION_X, x))
                if held[3] != y:
                    events.append((EV_ABS, ABS_MT_POSITION_Y, y))
                held[2], held[3] = x, y
        self.legacy(events)
        events.append((EV_SYN, SYN_REPORT, 0))
        return events

    def release(self):
        return self.frame([]) if self.count else []

    def select(self, events, index):
        if self.slot != index:
            events.append((EV_ABS, ABS_MT_SLOT, index))
            self.slot = index

    def legacy(self, events):
        held = [slot for slot in self.slots if slot is not None]
        count = len(held)
        if count != self.count:
            if self.count:
                events.append((EV_KEY, FINGER_TOOLS[self.count - 1], 0))
            if count:
                events.append((EV_KEY, FINGER_TOOLS[count - 1], 1))
            if bool(count) != bool(self.count):
                events.append((EV_KEY, BTN_TOUCH, 1 if count else 0))
            self.count = count
        if not held:
            self.primary = None
            return
        first = max(held, key=lambda slot: (self.next_id - slot[1]) % 65536)
        if (first[2], first[3]) != self.primary:
            if self.primary is None or self.primary[0] != first[2]:
                events.append((EV_ABS, ABS_X, first[2]))
            if self.primary is None or self.primary[1] != first[3]:
                events.append((EV_ABS, ABS_Y, first[3]))
            self.primary = (first[2], first[3])


class Pace:

    WINDOW = 2.0
    SQUEEZE = 0.9

    def __init__(self, delay=TRACKPAD_DELAY):
        self.delay = delay
        self.quickest = collections.deque()
        self.last = None                        # (phone, due) of the last frame
        self.raw = None
        self.wraps = 0

    def seconds(self, millis):
        if self.raw is not None and millis < self.raw and self.raw - millis > 1 << 31:
            self.wraps += 1
        self.raw = millis
        return (self.wraps * (1 << 32) + millis) / 1000

    def heard(self, phone, arrived):
        offset = arrived - phone
        while self.quickest and self.quickest[-1][1] >= offset:
            self.quickest.pop()
        self.quickest.append((arrived, offset))
        while self.quickest[0][0] < arrived - self.WINDOW:
            self.quickest.popleft()

    def due(self, phone, arrived):
        self.heard(phone, arrived)
        due = phone + self.quickest[0][1] + self.delay
        if self.last is not None and 0 <= phone - self.last[0] < 0.1:
            due = max(due, self.last[1] + self.SQUEEZE * (phone - self.last[0]))
        due = max(due, arrived)
        self.last = (phone, due)
        return due


def stream(reader, writer, pad, clock=time.monotonic):
    fingers = Fingers()
    pace = Pace()
    queue = collections.deque()
    ready = threading.Condition()
    finished = []

    def emit():
        try:
            while True:
                with ready:
                    while not queue and not finished:
                        ready.wait()
                    if not queue:
                        break
                    due, contacts = queue.popleft()
                wait = due - clock()
                if wait > 0:
                    time.sleep(wait)
                pad.write(fingers.frame(contacts))
        except OSError:
            pass
        finally:
            try:
                events = fingers.release()
                if events:
                    pad.write(events)
            except OSError:
                pass

    worker = threading.Thread(target=emit, daemon=True)
    worker.start()
    try:
        while True:
            head = reader.read(5)
            if len(head) < 5:
                break
            arrived = clock()
            kind, millis = struct.unpack("!BI", head)
            phone = pace.seconds(millis)
            if kind == KEEPALIVE:
                pace.heard(phone, arrived)
                writer.write(bytes([KEEPALIVE]))
                continue
            count = reader.read(1) if kind == TOUCH_FRAME else b""
            if len(count) < 1 or count[0] > MAX_FINGERS:
                break
            body = reader.read(5 * count[0])
            if len(body) < 5 * count[0]:
                break
            contacts = []
            for index in range(count[0]):
                finger, x, y = struct.unpack_from("!BHH", body, 5 * index)
                contacts.append((finger, min(x, pad.width), min(y, pad.height)))
            due = pace.due(phone, arrived)
            with ready:
                queue.append((due, contacts))
                ready.notify()
    except (OSError, ValueError):
        pass
    finally:
        with ready:
            finished.append(True)
            ready.notify()
        worker.join(timeout=2)


FAVICON_DAYS = 7
PAGE_MAX = 512 * 1024
FAVICON_MAX = 256 * 1024
FETCH_TIMEOUT = 5
PUBLIC_ONLY = True
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def public(host):
    if not PUBLIC_ONLY:
        return True
    try:
        found = socket.getaddrinfo(host, None)
    except (OSError, UnicodeError):
        return False
    return bool(found) and all(ipaddress.ip_address(item[4][0].split("%")[0]).is_global for item in found)


class PublicRedirects(urllib.request.HTTPRedirectHandler):

    max_redirections = 3

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not valid_url(newurl) or not public(urllib.parse.urlsplit(newurl).hostname):
            raise urllib.error.URLError("redirected somewhere not public")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url, limit, whole=True):
    if not valid_url(url) or not public(urllib.parse.urlsplit(url).hostname):
        raise ValueError("not a public web page")
    opener = urllib.request.build_opener(PublicRedirects())
    request = urllib.request.Request(url, headers={"User-Agent": "NIHIL deck (icons)", "Accept": "*/*"})
    with opener.open(request, timeout=FETCH_TIMEOUT) as response:
        data = response.read(limit + 1)
        if len(data) > limit:
            if whole:
                raise ValueError("too big")
            data = data[:limit]
        return response.geturl(), data


class IconLinks(html.parser.HTMLParser):

    def __init__(self, base):
        super().__init__()
        self.base = base
        self.found = []
        self.done = False

    def handle_starttag(self, tag, attrs):
        if self.done or tag == "body":
            self.done = True
            return
        if tag != "link":
            return
        attrs = {key: value or "" for key, value in attrs}
        rel = set(attrs.get("rel", "").lower().split())
        href = attrs.get("href", "").strip()
        touch = bool(rel & {"apple-touch-icon", "apple-touch-icon-precomposed"})
        if not href or not (touch or "icon" in rel):
            return
        sizes = [int(size) for size in re.findall(r"(\d+)x\d+", attrs.get("sizes", "").lower())]
        if "svg" in attrs.get("type", "").lower() or href.lower().split("?")[0].endswith(".svg"):
            score = 1024
        else:
            score = max(sizes or [180 if touch else 32])
        self.found.append((score, urllib.parse.urljoin(self.base, href)))

    def handle_endtag(self, tag):
        if tag == "head":
            self.done = True


def ico_png(data):
    try:
        best = None
        for index in range(min(struct.unpack_from("<H", data, 4)[0], 64)):
            width, height, _, _, _, _, size, offset = struct.unpack_from("<BBBBHHII", data, 6 + 16 * index)
            chunk = data[offset:offset + size]
            if chunk.startswith(PNG_MAGIC) and (best is None or (width or 256) * (height or 256) > best[0]):
                best = ((width or 256) * (height or 256), chunk)
        return (best[1], "image/png") if best else None
    except struct.error:
        return None


def as_image(data, rsvg):
    head = data[:16]
    if head.startswith(PNG_MAGIC):
        return data, "image/png"
    if head.startswith(b"\xff\xd8\xff"):
        return data, "image/jpeg"
    if head[:6] in (b"GIF87a", b"GIF89a"):
        return data, "image/gif"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return data, "image/webp"
    if head[:4] == b"\x00\x00\x01\x00":
        return ico_png(data)
    if b"<svg" in data[:2048].lower():
        try:
            drawn = subprocess.run([rsvg, "-w", str(ICON_SIZE), "-h", str(ICON_SIZE), "-a", "-f", "png"],
                                   input=data, check=True, capture_output=True, timeout=10).stdout
        except (OSError, subprocess.SubprocessError):
            return None
        return (drawn, "image/png") if drawn.startswith(PNG_MAGIC) else None
    return None


def favicon(url, rsvg, cache):
    parts = urllib.parse.urlsplit(url)
    origin = f"{parts.scheme}://{parts.netloc}".lower()
    path = os.path.join(cache, hashlib.sha256(origin.encode()).hexdigest()[:24])
    try:
        if time.time() - os.path.getmtime(path) < FAVICON_DAYS * 86400:
            with open(path, "rb") as file:
                kept = file.read()
            return as_image(kept, rsvg) if kept else None
    except OSError:
        pass
    failed = (OSError, ValueError, urllib.error.URLError, http.client.HTTPException)
    candidates = []
    try:
        where, page = fetch(origin + "/", PAGE_MAX, whole=False)
        links = IconLinks(where)
        links.feed(page.decode("utf-8", "replace"))
        candidates = [href for _, href in sorted(links.found, key=lambda item: -item[0])]
    except failed:
        pass
    found = None
    for href in candidates[:4] + [origin + "/favicon.ico"]:
        try:
            found = as_image(fetch(href, FAVICON_MAX)[1], rsvg)
        except failed:
            continue
        if found:
            break
    os.makedirs(cache, mode=0o700, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=cache, prefix=".icon-")
    with os.fdopen(fd, "wb") as file:
        file.write(found[0] if found else b"")
    os.replace(temporary, path)
    return found


def addresses(ip):
    found = []
    if ip:
        try:
            route = json.loads(subprocess.run([ip, "-j", "-4", "route", "get", "192.0.2.1"],
                                              capture_output=True, text=True, timeout=5).stdout or "[]")
            if route and route[0].get("prefsrc"):
                found.append(route[0]["prefsrc"])
        except (OSError, ValueError, subprocess.SubprocessError, AttributeError, IndexError):
            pass
        try:
            links = json.loads(subprocess.run([ip, "-j", "-4", "addr", "show", "up", "scope", "global"],
                                              capture_output=True, text=True, timeout=5).stdout or "[]")
            for link in links:
                if VIRTUAL.match(str(link.get("ifname", ""))):
                    continue
                for info in link.get("addr_info", []):
                    if info.get("family") == "inet" and info.get("local"):
                        found.append(info["local"])
        except (OSError, ValueError, subprocess.SubprocessError, AttributeError):
            pass
    if not found:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                probe.connect(("192.0.2.1", 9))
                found.append(probe.getsockname()[0])
        except OSError:
            pass
    return [address for address in dict.fromkeys(found) if not address.startswith("127.")]


def pair_uri(name, port, hosts, code, pin):
    query = urllib.parse.urlencode({"v": API, "name": name, "hosts": ",".join(hosts), "port": port,
                                    "code": code, "pin": pin}, safe=",")
    return "nihil-deck://pair?" + query


def vector_dir():
    return os.path.join(home_dir("XDG_CACHE_HOME", ".cache"), "nihil", "vector")


def kind_of(mime):
    if mime.startswith("text/"):
        return "text"
    for kind in ("image", "video"):
        if mime.startswith(kind + "/"):
            return kind
    return "file"


def clean_mime(value):
    mime = str(value or "").split(";")[0].strip().lower()
    return mime if MIME.fullmatch(mime) else "application/octet-stream"


def file_name(value, mime):
    name = os.path.basename(str(value or "").replace("\\", "/"))
    name = re.sub(r"[\x00-\x1f\x7f]", "", name).strip()[:160]
    if name in ("", ".", "..") or name.startswith("."):
        name = {"text": "text", "image": "image", "video": "video"}.get(kind_of(mime), "file") + EXTENSIONS.get(mime, "")
    return name


def vector_item(item):
    if not item:
        return {"id": ""}
    return {key: item[key] for key in ("id", "kind", "name", "mime", "size", "time")}


class Vector:

    def __init__(self, folder=None):
        self.folder = folder or vector_dir()
        self.changed = threading.Condition()
        self.waiting = collections.Counter()
        self.heard = {}

    def slot(self, side):
        return os.path.join(self.folder, side)

    def item(self, side):
        try:
            with open(os.path.join(self.slot(side), ".item.json")) as file:
                item = json.load(file)
            path = os.path.join(self.slot(side), item["name"])
        except (OSError, ValueError, KeyError, TypeError):
            return None
        if not os.path.isfile(path):
            return None
        item["path"] = path
        return item

    def part(self, side):
        folder = self.slot(side)
        os.makedirs(folder, mode=0o700, exist_ok=True)
        return os.path.join(folder, ".part-" + secrets.token_hex(6))

    def store(self, side, part, name, mime, origin=""):
        folder = self.slot(side)
        mime = clean_mime(mime)
        name = file_name(name, mime)
        for entry in os.listdir(folder):
            path = os.path.join(folder, entry)
            if path == part or entry == ".item.json" or entry.startswith(".deck-"):
                continue
            if entry.startswith(".part-") and now() - os.path.getmtime(path) < 600:
                continue
            try:
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)
            except OSError:
                pass
        target = os.path.join(folder, name)
        os.replace(part, target)
        size = os.path.getsize(target)
        kind = kind_of(mime)
        item = {"id": secrets.token_hex(8), "kind": "file" if kind == "text" and size > VECTOR_TEXT else kind,
                "name": name, "mime": mime, "size": size, "time": round(now()), "from": origin}
        write_private(os.path.join(folder, ".item.json"), json.dumps(item))
        self.poke()
        item["path"] = target
        return item

    def poke(self):
        with self.changed:
            self.changed.notify_all()

    def wait(self, device, since, seconds):
        deadline = now() + seconds
        with self.changed:
            self.waiting[device] += 1
            try:
                while True:
                    item = self.item("out")
                    if (item["id"] if item else "") != since or now() >= deadline:
                        return item
                    self.changed.wait(min(deadline - now(), 5))
            finally:
                self.waiting[device] -= 1
                if self.waiting[device] <= 0:
                    del self.waiting[device]
                self.heard[device] = now()

    def connected(self, devices):
        live = {key for key, count in self.waiting.items() if count > 0}
        live |= {key for key, seen in list(self.heard.items()) if now() - seen < VECTOR_LIVE}
        return [device["name"] for device in devices.listing() if device["id"] in live]


class Deck:

    def __init__(self, config, folder, pin):
        self.config = config
        self.pin = pin
        self.name = config.get("name") or socket.gethostname()
        self.port = int(config.get("port", PORT))
        self.devices = Devices(os.path.join(folder, "devices.json"))
        self.pairing = Pairing()
        self.throttle = Throttle()
        self.session = Session(config)
        self.vector = Vector(config.get("vector"))
        self.strings = config.get("strings", {})
        self.make_trackpad = lambda width, height, resolution: Uinput(config.get("uinput", "/dev/uinput"), width, height, resolution)
        self.streams = {}
        self.streams_lock = threading.Lock()

    def control(self, request):
        op = request.get("op") if isinstance(request, dict) else None
        if op == "pair":
            code, expires = self.pairing.open()
            hosts = addresses(self.config.get("ip"))
            return {"uri": pair_uri(self.name, self.port, hosts, code, self.pin), "code": code,
                    "expires": int(expires), "hosts": hosts, "port": self.port, "pin": self.pin}
        if op == "cancel":
            self.pairing.close()
            return {"ok": True}
        if op == "devices":
            return {"devices": self.devices.listing(), "pairing": self.pairing.open_now}
        if op == "forget":
            return {"ok": self.devices.forget(str(request.get("id", "")))}
        if op == "status":
            return {"port": self.port, "pin": self.pin, "devices": len(self.devices.listing()),
                    "pairing": self.pairing.open_now}
        if op == "vector":
            self.vector.poke()
            return {"devices": self.vector.connected(self.devices)}
        return {"error": "unknown"}

    def claim(self, device, connection):
        with self.streams_lock:
            before = self.streams.get(device)
            self.streams[device] = connection
        if before is not None and before is not connection:
            try:
                socket.socket.shutdown(before, socket.SHUT_RDWR)
            except OSError:
                pass

    def unclaim(self, device, connection):
        with self.streams_lock:
            if self.streams.get(device) is connection:
                del self.streams[device]

    def paired(self, name):
        title = self.strings.get("deckPaired", "%1 can now use this computer as a deck").replace("%1", name)
        self.session.notify(title, self.strings.get("deckPairedBody", ""))


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    disable_nagle_algorithm = True
    server_version = "nihil-deck/" + str(API)
    sys_version = ""

    def setup(self):
        self.request.do_handshake()
        super().setup()

    def log_message(self, format, *args):
        pass

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        if self.close_connection:
            self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)

    def png(self, path):
        with open(path, "rb") as file:
            self.image(file.read(), "image/png")

    def image(self, data, kind):
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "private, max-age=86400")
        self.end_headers()
        self.wfile.write(data)

    def read_body(self, limit=MAX_BODY):
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = -1
        if length < 0 or length > limit:
            self.close_connection = True
            return None
        data = self.rfile.read(length) if length else b""
        if not data:
            return {}
        try:
            body = json.loads(data)
        except ValueError:
            return None
        return body if isinstance(body, dict) else None

    def do_GET(self):
        self.route("GET", {})

    def send_file(self, item):
        try:
            file = open(item["path"], "rb")
        except OSError:
            self.reply(404, {"error": "vector"})
            return
        with file:
            self.send_response(200)
            self.send_header("Content-Type", item["mime"])
            self.send_header("Content-Length", str(os.fstat(file.fileno()).st_size))
            self.send_header("Content-Disposition", "attachment; filename*=UTF-8''" + urllib.parse.quote(item["name"]))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            shutil.copyfileobj(file, self.wfile, CHUNK)

    def receive(self, deck, device):
        try:
            length = int(self.headers.get("Content-Length") or -1)
        except ValueError:
            length = -1
        if length <= 0 or length > VECTOR_MAX:
            self.reply(413 if length > VECTOR_MAX else 400, {"error": "big" if length > VECTOR_MAX else "body"})
            return
        vector = deck.vector
        part = vector.part("in")
        try:
            with open(part, "wb") as file:
                left = length
                while left:
                    chunk = self.rfile.read(min(CHUNK, left))
                    if not chunk:
                        raise ConnectionError("short")
                    file.write(chunk)
                    left -= len(chunk)
            name = urllib.parse.unquote(self.headers.get("X-Vector-Name", ""))
            item = vector.store("in", part, name, self.headers.get("Content-Type"), device["name"])
        except (OSError, ConnectionError, socket.timeout):
            try:
                os.unlink(part)
            except OSError:
                pass
            self.reply(503, {"error": "vector"})
            return
        vector.heard[device["id"]] = now()
        deck.session.ipc("vector", "received")
        self.reply(200, vector_item(item))

    def do_POST(self):
        path = urllib.parse.urlsplit(self.path).path
        if path == "/v1/vector":
            self.close_connection = True
            self.route("POST", {})
            return
        body = self.read_body({"/v1/tasks": TASKS_MAX}.get(path, MAX_BODY))
        if body is None:
            self.reply(400, {"error": "body"})
            return
        self.route("POST", body)

    def route(self, method, body):
        deck = self.server.deck
        address = self.client_address[0]
        path = urllib.parse.urlsplit(self.path).path
        if deck.throttle.blocked(address):
            self.close_connection = True
            self.reply(429, {"error": "wait"})
            return
        if method == "GET" and path == "/v1/hello":
            self.reply(200, {"deck": API, "name": deck.name})
            return
        if method == "POST" and path == "/v1/pair":
            self.pair(deck, address, body)
            return
        auth = self.headers.get("Authorization", "")
        device = deck.devices.find(auth[7:].strip() if auth.startswith("Bearer ") else "")
        if device is None:
            deck.throttle.fail(address)
            self.reply(401, {"error": "unpaired"})
            return
        deck.devices.touch(device)
        self.paired_route(deck, device, method, path, body)

    def pair(self, deck, address, body):
        result = deck.pairing.take(body.get("code"))
        if result != "ok":
            deck.throttle.fail(address)
            self.reply({"closed": 409, "expired": 410, "wrong": 403}[result], {"error": result})
            return
        name = clean_name(body.get("device"), "Android")
        device, token = deck.devices.add(name)
        deck.paired(name)
        self.reply(200, {"token": token, "device": device, "name": deck.name})

    def trackpad(self, deck, device):
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        try:
            width, height, resolution = (int(query.get(key, ["0"])[0]) for key in ("w", "h", "r"))
        except ValueError:
            width = height = resolution = 0
        sized = 5 <= resolution <= 100 and all(10 * resolution <= side <= min(500 * resolution, 65535) for side in (width, height))
        if not sized or self.headers.get("Upgrade", "").strip().lower() != TRACKPAD_PROTOCOL:
            self.reply(400, {"error": "invalid"})
            return
        try:
            pad = deck.make_trackpad(width, height, resolution)
        except OSError as error:
            self.reply(503, {"error": "access" if error.errno in (errno.EACCES, errno.EPERM) else "trackpad"})
            return
        deck.claim(device["id"], self.connection)
        try:
            time.sleep(TRACKPAD_SETTLE)
            self.send_response(101)
            self.send_header("Upgrade", TRACKPAD_PROTOCOL)
            self.send_header("Connection", "Upgrade")
            self.end_headers()
            self.close_connection = True
            self.connection.settimeout(TRACKPAD_IDLE)
            try:
                self.connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            except OSError:
                pass
            stream(self.rfile, self.wfile, pad)
        finally:
            deck.unclaim(device["id"], self.connection)
            pad.close()

    def paired_route(self, deck, device, method, path, body):
        session = deck.session
        if method == "GET" and path == "/v1/apps":
            listed = session.apps()
            if listed is None:
                self.reply(503, {"error": "shell"})
                return
            self.reply(200, {"apps": [{"id": a["id"], "name": a["name"]} for a in listed]})
        elif method == "GET" and path.startswith("/v1/apps/") and path.endswith("/icon"):
            app = session.app(urllib.parse.unquote(path[len("/v1/apps/"):-len("/icon")]))
            found = icon_file(app["icon"], deck.config.get("iconTheme", "")) if app else None
            picture = icon_png(found, deck.config.get("rsvg", "rsvg-convert"), os.path.join(cache_dir(), "icons")) if found else None
            if picture is None:
                self.reply(404, {"error": "icon"})
            else:
                self.png(picture)
        elif method == "GET" and path == "/v1/favicon":
            url = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get("url", [""])[0]
            if not valid_url(url):
                self.reply(400, {"error": "invalid"})
                return
            found = favicon(url, deck.config.get("rsvg", "rsvg-convert"), os.path.join(cache_dir(), "favicons"))
            if found is None:
                self.reply(404, {"error": "icon"})
            else:
                self.image(*found)
        elif method == "GET" and path == "/v1/cover":
            token = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get("c", [""])[0]
            found = session.cover(token) if re.fullmatch(r"[0-9a-f]{16}", token) else None
            if found is None:
                self.reply(404, {"error": "cover"})
            else:
                self.image(*found)
        elif method == "GET" and path == "/v1/tasks":
            board = session.tasks()
            if board is None:
                self.reply(503, {"error": "shell"})
            else:
                self.reply(200, board)
        elif method == "POST" and path == "/v1/tasks":
            board = clean_board(body)
            if board is None:
                self.reply(400, {"error": "invalid"})
                return
            merged = session.tasks(board)
            if merged is None:
                self.reply(503, {"error": "shell"})
            else:
                self.reply(200, merged)
        elif method == "GET" and path == "/v1/state":
            self.reply(200, {"media": session.playing(), "volume": session.volume(), **session.toggles()})
        elif method == "POST" and path == "/v1/open":
            if "app" in body:
                result = session.launch(body.get("app"))
            elif "url" in body:
                result = session.open_url(body.get("url"))
            else:
                result = "invalid"
            status = {"ok": 200, "unknown": 404, "invalid": 400, "shell": 503}[result]
            self.reply(status, {"ok": True} if result == "ok" else {"error": result})
        elif method == "POST" and path in ("/v1/media", "/v1/volume", "/v1/caffeine", "/v1/night"):
            kind = path[len("/v1/"):]
            action = body.get("action")
            if action not in ACTIONS[kind]:
                self.reply(400, {"error": "action"})
            elif kind in ("caffeine", "night"):
                on = session.switch(kind, action)
                if on is None:
                    self.reply(503, {"error": "shell"})
                else:
                    self.reply(200, {"on": on})
            elif kind == "media":
                if session.media(action):
                    self.reply(200, {"ok": True})
                else:
                    self.reply(503, {"error": "shell"})
            else:
                volume = session.volume(action)
                if volume is not None:
                    self.reply(200, volume)
                else:
                    self.reply(503, {"error": "volume"})
        elif method == "GET" and path == "/v1/vector":
            query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
            try:
                wait = max(0, min(VECTOR_WAIT, int(query.get("wait", ["0"])[0])))
            except ValueError:
                wait = 0
            since = query.get("since", [""])[0]
            deck.vector.heard[device["id"]] = now()
            item = deck.vector.wait(device["id"], since, wait) if wait else deck.vector.item("out")
            self.reply(200, dict(vector_item(item), now=round(now())))
        elif method == "GET" and path == "/v1/vector/data":
            wanted = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get("id", [""])[0]
            item = deck.vector.item("out")
            if not item or item["id"] != wanted:
                self.reply(404, {"error": "vector"})
            else:
                deck.vector.heard[device["id"]] = now()
                self.send_file(item)
        elif method == "POST" and path == "/v1/vector":
            self.receive(deck, device)
        elif method == "POST" and path == "/v1/lock":
            if session.lock_screen():
                self.reply(200, {"ok": True})
            else:
                self.reply(503, {"error": "lock"})
        elif method == "GET" and path == "/v1/trackpad":
            self.trackpad(deck, device)
        elif method == "POST" and path == "/v1/unpair":
            deck.devices.forget(device["id"])
            self.reply(200, {"ok": True})
        else:
            self.reply(404, {"error": "path"})


class DeckServer(http.server.ThreadingHTTPServer):

    daemon_threads = True
    timeout_seconds = 15

    def __init__(self, address, deck, context):
        self.deck = deck
        self.context = context
        self.slots = threading.BoundedSemaphore(CONNECTIONS)
        host, port = address
        self.address_family = socket.AF_INET6 if ":" in host else socket.AF_INET
        super().__init__((host, port), Handler)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()

    def server_bind(self):
        if self.address_family == socket.AF_INET6:
            try:
                self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            except OSError:
                pass
        socketserver.TCPServer.server_bind(self)
        self.server_name = "nihil-deck"
        self.server_port = self.server_address[1]

    def get_request(self):
        connection, address = self.socket.accept()
        connection.settimeout(self.timeout_seconds)
        return self.context.wrap_socket(connection, server_side=True, do_handshake_on_connect=False), address

    def handle_error(self, request, client_address):
        error = sys.exc_info()[1]
        if not isinstance(error, (ssl.SSLError, ConnectionError, TimeoutError, socket.timeout)):
            print(f"nihil-deck: {client_address[0]}: {error!r}", file=sys.stderr)


class ControlHandler(socketserver.StreamRequestHandler):
    def handle(self):
        line = self.rfile.readline(65536)
        try:
            request = json.loads(line)
        except ValueError:
            request = None
        reply = self.server.deck.control(request)
        self.wfile.write((json.dumps(reply) + "\n").encode())


class ControlServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True

    def __init__(self, path, deck):
        self.deck = deck
        if os.path.exists(path):
            os.unlink(path)
        old = os.umask(0o177)
        try:
            super().__init__(path, ControlHandler)
        finally:
            os.umask(old)


def tls_context(cert, key):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(cert, key)
    return context


def make_server(config, folder, host="::"):
    cert, key = ensure_certificate(folder, config.get("openssl", "openssl"))
    deck = Deck(config, folder, pin_of(cert))
    context = tls_context(cert, key)
    try:
        server = DeckServer((host, deck.port), deck, context)
    except OSError:
        if host != "::":
            raise
        server = DeckServer(("0.0.0.0", deck.port), deck, context)
    deck.port = server.server_address[1]
    return server


def serve(config):
    server = make_server(config, state_dir())
    deck = server.deck
    path = control_path()
    control = ControlServer(path, deck)
    threading.Thread(target=control.serve_forever, daemon=True).start()

    def stop(*_):
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    print(f"nihil-deck: on port {deck.port}, {len(deck.devices.listing())} phone(s) paired", file=sys.stderr)
    try:
        server.serve_forever()
    finally:
        control.shutdown()
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        deck.devices.flush()


def ask(request, path=None):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(5)
        connection.connect(path or control_path())
        connection.sendall((json.dumps(request) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = connection.recv(65536)
            if not chunk:
                break
            data += chunk
    return json.loads(data)


def qr_rows(text):
    lines = text.split("\n")
    while lines and lines[-1].strip() == "":
        lines.pop()
    while lines and lines[0].strip() == "":
        lines.pop(0)
    size = len(lines)
    rows = []
    for line in lines:
        line = line.ljust(size * 2)
        rows.append("".join("1" if line[2 * i] == "#" else "0" for i in range(size)))
    if size < 21 or size > 177 or (size - 21) % 4 != 0:
        raise ValueError(f"not a QR: {size} rows")
    return rows


def qr(uri, qrencode):
    done = subprocess.run([qrencode, "-t", "ASCII", "-m", "0", "-l", "M", uri],
                          check=True, capture_output=True, text=True, timeout=10)
    return qr_rows(done.stdout)


def clipboard_source(config):
    def paste(*arguments):
        return subprocess.run([config["wlPaste"], *arguments], stdin=subprocess.DEVNULL,
                              capture_output=True, timeout=20).stdout

    try:
        types = paste("--list-types").decode(errors="replace").split()
        if "text/uri-list" in types:
            for line in paste("--type", "text/uri-list").decode(errors="replace").splitlines():
                if line.strip().startswith("file://"):
                    return "file", urllib.parse.unquote(urllib.parse.urlsplit(line.strip()).path)
        for prefix in ("image/", "video/"):
            found = [kind for kind in types if kind.startswith(prefix)]
            if found:
                kind = "image/png" if "image/png" in found else found[0]
                return "data", paste("--type", kind), kind
        for kind in ("text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING", "TEXT"):
            if kind in types:
                data = paste("--no-newline", "--type", kind)
                return ("data", data, "text/plain") if data else None
    except (OSError, subprocess.SubprocessError):
        return None
    return None


def vector_send(config, vector, argument=None):
    if argument:
        path = urllib.parse.unquote(urllib.parse.urlsplit(argument).path) if argument.startswith("file://") else argument
        source = ("file", path)
    else:
        source = clipboard_source(config)
    if source is None:
        return {"error": "empty"}
    part = vector.part("out")
    try:
        if source[0] == "file":
            path = source[1]
            if os.path.isdir(path):
                return {"error": "folder"}
            if not os.path.isfile(path):
                return {"error": "empty"}
            if os.path.getsize(path) > VECTOR_MAX:
                return {"error": "big"}
            shutil.copyfile(path, part)
            name, mime = os.path.basename(path), mimetypes.guess_type(path)[0] or "application/octet-stream"
        else:
            data, mime, name = source[1], source[2], ""
            if not data:
                return {"error": "empty"}
            if len(data) > VECTOR_MAX:
                return {"error": "big"}
            with open(part, "wb") as file:
                file.write(data)
        item = vector.store("out", part, name, mime)
    except OSError:
        return {"error": "vector"}
    finally:
        if os.path.exists(part):
            os.unlink(part)
    return {"ok": True, "kind": item["kind"], "name": item["name"]}


def vector_copy(config, vector):
    item = vector.item("in")
    if item is None:
        return {"error": "empty"}
    if item["kind"] == "file" or item["kind"] == "video":
        command = [config["wlCopy"], "--type", "text/uri-list"]
        data = ("file://" + urllib.parse.quote(item["path"]) + "\r\n").encode()
    else:
        command = [config["wlCopy"]] + (["--type", item["mime"]] if item["kind"] == "image" else [])
        with open(item["path"], "rb") as file:
            data = file.read()
    try:
        done = subprocess.run(command, input=data, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return {"error": "clipboard"}
    return {"ok": True} if done.returncode == 0 else {"error": "clipboard"}


def vector_command(config, action, argument):
    vector = Vector(config.get("vector"))
    if action == "send":
        result = vector_send(config, vector, argument)
    elif action == "copy":
        return vector_copy(config, vector)
    elif action == "status":
        item = vector.item("in")
        result = {"in": dict(vector_item(item), path=item["path"], **{"from": item.get("from", "")}) if item else {"id": ""},
                  "out": vector_item(vector.item("out"))}
    else:
        return {"error": "usage"}
    if "error" in result:
        return result
    try:
        result["devices"] = ask({"op": "vector"}).get("devices", [])
    except (OSError, ValueError):
        result["devices"] = []
    return result


def main():
    parser = argparse.ArgumentParser(prog="nihil-deck", description="The phone as a deck for this computer (docs/deck.md).")
    parser.add_argument("--config", help="configuration written by home/deck/default.nix")
    parser.add_argument("command", nargs="?", default="devices", choices=["serve", "pair", "cancel", "devices", "forget", "vector"])
    parser.add_argument("target", nargs="?", help="forget: a phone's id, or all; vector: send, copy or status")
    parser.add_argument("argument", nargs="?", help="vector send: a file (the clipboard without one)")
    parser.add_argument("--json", action="store_true", help="for the shell")
    options = parser.parse_args()

    config = {}
    if options.config:
        with open(options.config) as file:
            config = json.load(file)
    for key, command in (("ipc", "nihil-ipc"), ("volume", "osd-volume"),
                         ("notify", "notify-send"), ("openssl", "openssl"), ("qrencode", "qrencode"),
                         ("rsvg", "rsvg-convert"), ("ip", "ip"), ("wpctl", "wpctl"),
                         ("wlCopy", "wl-copy"), ("wlPaste", "wl-paste")):
        config.setdefault(key, shutil.which(command) or command)

    if options.command == "serve":
        serve(config)
        return 0
    if options.command == "vector":
        result = vector_command(config, options.target, options.argument)
        print(json.dumps(result))
        return 1 if "error" in result else 0

    request = {"pair": {"op": "pair"}, "cancel": {"op": "cancel"}, "devices": {"op": "devices"},
               "forget": {"op": "forget", "id": options.target or ""}}[options.command]
    if options.command == "forget" and not options.target:
        print("nihil-deck forget ID|all", file=sys.stderr)
        return 2
    try:
        reply = ask(request)
    except (OSError, ValueError):
        print("The deck is not running (systemctl --user status nihil-deck).", file=sys.stderr)
        return 1

    if options.command == "pair":
        try:
            reply["qr"] = qr(reply["uri"], config["qrencode"])
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            reply["qr"] = []
            if options.json:
                reply["error"] = str(error)
        if options.json:
            print(json.dumps(reply))
        else:
            for row in reply["qr"]:
                print("".join("██" if module == "1" else "  " for module in row))
            print(reply["uri"])
            print(f"Valid until {time.strftime('%H:%M', time.localtime(reply['expires']))}, once.")
        return 0
    if options.command == "devices" and not options.json:
        for device in reply.get("devices", []):
            seen = time.strftime("%Y-%m-%d %H:%M", time.localtime(device.get("seen") or 0))
            print(f"{device['id']}  {device['name']}  (last seen {seen})")
        return 0
    if options.json or options.command == "devices":
        print(json.dumps(reply))
    elif options.command == "forget" and not reply.get("ok"):
        print(f"No phone {options.target}.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
