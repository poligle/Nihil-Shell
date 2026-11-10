#!/usr/bin/env python3
# deck.py by poligle
#
# The phone as a deck for this computer (docs/deck.md): NIHIL Launcher, on
# Android, opens apps and web pages here, plays and skips the music, turns
# the volume and locks the screen. Nothing else: there is no command line
# from the phone, only these, and they go through the shell (nihil-ipc) and
# the volume's own script, as the launcher and the keys would.
#
# The phone talks HTTPS to it on the local network. The certificate is this
# computer's own, made the first time (openssl), and the phone pins it: the
# QR it pairs with has the SHA-256 of its public key. Pairing also needs the
# one-time code in that QR, shown in Preferences, Phone; it gives the phone
# a token of its own, kept here only as its SHA-256, until it is forgotten.
#
# Standard library only. home/deck/default.nix wraps it with its
# configuration (the port, the store paths of what it runs); home/deck.nix
# runs the service in the session.
#
#   nihil-deck serve              the service
#   nihil-deck pair [--json]      a code to pair a phone: the QR to scan (with
#                                 --json, its URI and modules, for the shell)
#   nihil-deck cancel             the code no longer pairs
#   nihil-deck devices [--json]   the phones paired
#   nihil-deck forget ID|all      one of them, or all, forgotten
#
# The service keeps its certificate and the phones in
# $XDG_STATE_HOME/nihil/deck, and listens for those commands on
# $XDG_RUNTIME_DIR/nihil-deck.sock (one JSON object per line).

import argparse
import base64
import functools
import hashlib
import hmac
import html.parser
import http.client
import http.server
import ipaddress
import json
import math
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
CODE_ATTEMPTS = 5               # wrong codes before it stops pairing
MAX_BODY = 4096
TASKS_MAX = 256 * 1024     # a phone's whole kanban
COVER_MAX = 4 * 1024 * 1024
CARDS_MAX = 1000
FAIL_WINDOW = 60                # seconds, and how many failures in them
FAIL_LIMIT = 10
SEEN_EVERY = 60                 # seconds between writes of "last seen"
ICON_SIZE = 128
APPS_FOR = 20                   # seconds the shell's list of apps is kept
APP_ID = re.compile(r"[A-Za-z0-9._+-]{1,160}")
# Interfaces the phone can't reach this computer through: containers' and
# virtual machines' bridges and their ends. A VPN (Tailscale, WireGuard) stays.
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
    """Written whole or not at all, only for the user (0600)."""
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


# --- The certificate -----------------------------------------------------------

def ensure_certificate(folder, openssl):
    """cert.pem and key.pem in FOLDER, made once: EC P-256, ten years."""
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
    """A DER element at AT: its tag, where its value starts and ends."""
    tag = data[at]
    length = data[at + 1]
    at += 2
    if length & 0x80:
        count = length & 0x7F
        length = int.from_bytes(data[at:at + count], "big")
        at += count
    return tag, at, at + length


def public_key_info(der):
    """The certificate's SubjectPublicKeyInfo, whole, as the phone hashes it
    (Java's PublicKey.getEncoded())."""
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
    # serialNumber, signature, issuer, validity, subject, subjectPublicKeyInfo
    if len(fields) < 6 or fields[5][0] != 0x30:
        raise ValueError("not a certificate this can read")
    _, begin, end = fields[5]
    return der[begin:end]


def pin_of(cert_path):
    with open(cert_path) as file:
        der = ssl.PEM_cert_to_DER_cert(file.read())
    return b64url(hashlib.sha256(public_key_info(der)).digest())


# --- The phones ------------------------------------------------------------------

class Devices:
    """The phones paired: a name, when it was paired and last seen, and the
    SHA-256 of its token."""

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
    """The one code that pairs, while Preferences shows it: once, for a few
    minutes, and not after a few wrong ones."""

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
        """"ok" (and it no longer pairs), "closed", "expired" or "wrong"."""
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
    """Who keeps failing (a token, a code) waits a minute."""

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


# --- What it may do -------------------------------------------------------------

def valid_url(url):
    """A web page: http or https, with a host, no spaces, not too long."""
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
    """The shell and the session, from here: everything the deck does."""

    def __init__(self, config):
        self.config = config
        self.lock = threading.Lock()
        self.cached = None
        self.cached_at = 0

    def run(self, command, timeout=6):
        try:
            done = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout)
        except (OSError, subprocess.SubprocessError):
            return None
        return done.stdout.strip() if done.returncode == 0 else None

    cover_cache = None

    def ipc(self, *arguments):
        return self.run([self.config["ipc"], *arguments])

    def apps(self, fresh=False):
        """What the launcher has: [{ id, name, icon }], by name."""
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
        """One of them, by id; asking the shell again when it is new."""
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
        # The cover's address stays here: the phone gets a token that changes with it.
        art = str(found.pop("art", "") or "")
        found["cover"] = hashlib.sha256(art.encode()).hexdigest()[:16] if art else ""
        return found

    def cover(self, token):
        """The cover of what plays as (bytes, type), when [token] is still its token."""
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
        """The desktop's kanban (Tasks.qml); with a phone's [board], merged first."""
        text = self.ipc("tasks", "state") if board is None else self.ipc("tasks", "sync", json.dumps(board))
        try:
            found = json.loads(text or "")
        except ValueError:
            return None
        return found if isinstance(found, dict) else None

    def volume(self, action=None):
        """The output's volume, after turning it with the keys' own script
        (it shows the OSD here): { level, muted }."""
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
        """Caffeine and night light as the quick settings have them:
        { caffeine, night }, empty when the shell can't say."""
        try:
            found = json.loads(self.ipc("toggles", "state") or "")
        except ValueError:
            return {}
        if not isinstance(found, dict):
            return {}
        return {key: found[key] for key in ("caffeine", "night") if isinstance(found.get(key), bool)}

    def switch(self, kind, action):
        """Caffeine or night light on, off or over; whether it is on now, None
        when the shell didn't answer."""
        if self.ipc(kind, action) is None:
            return None
        return self.toggles().get(kind)

    def notify(self, title, body):
        command = [self.config["notify"], "-a", "NIHIL", title]
        if body:
            command.append(body)
        self.run(command)


# --- Icons ------------------------------------------------------------------------

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
    """index.theme's Inherits and its directories: the scalable ones first,
    then the sizes closest to the phone's 128 px, bigger before smaller."""
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
    """The file of an icon by name, as the icon theme spec looks for it:
    the theme, what it inherits, hicolor, then pixmaps."""
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
    """A PNG for the phone: the theme's own, or the SVG drawn at 128 px
    (kept in the cache by file and time)."""
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


# --- The kanban ------------------------------------------------------------------

def clean_board(body):
    """A phone's kanban, its shape checked: { cards: [...], removed: { id: when } };
    a card's rank, when it has one, a finite number."""
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


# --- The webs' icons ------------------------------------------------------------
#
# The phone keeps its own webs, and asks here for their icons: so it talks to
# no one but this computer. A site's icon is looked for on its home page (an
# SVG, the apple-touch-icon, the biggest one it names) and then at
# /favicon.ico; only at public addresses, redirects included, and kept a
# week by site, the misses too.

FAVICON_DAYS = 7
PAGE_MAX = 512 * 1024
FAVICON_MAX = 256 * 1024
FETCH_TIMEOUT = 5
PUBLIC_ONLY = True  # the tests turn it off, to serve their sites from 127.0.0.1
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def public(host):
    """Whether every address of [host] is on the internet: never this
    computer, its network, or anything reserved."""
    if not PUBLIC_ONLY:
        return True
    try:
        found = socket.getaddrinfo(host, None)
    except (OSError, UnicodeError):
        return False
    return bool(found) and all(ipaddress.ip_address(item[4][0].split("%")[0]).is_global for item in found)


class PublicRedirects(urllib.request.HTTPRedirectHandler):
    """A few redirects, each to a public web page."""

    max_redirections = 3

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not valid_url(newurl) or not public(urllib.parse.urlsplit(newurl).hostname):
            raise urllib.error.URLError("redirected somewhere not public")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url, limit, whole=True):
    """[url]'s body and where it ended up: [limit] bytes at most, or (not
    [whole]) its first [limit] bytes, enough for a page's <head>."""
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
    """The icons a page names before its <body>, with how good each is."""

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
    """The biggest PNG inside an .ico (Windows Vista's and later), or None."""
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
    """What the phone can draw, as (bytes, type): PNG, JPEG, GIF and WebP as
    they come, an SVG drawn at 128 px, the biggest PNG inside an .ico. None
    for anything else (an .ico of bitmaps): the phone draws its letter."""
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
    """The icon of [url]'s site as (bytes, type), or None."""
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


# --- Where it is -----------------------------------------------------------------

def addresses(ip):
    """This computer's IPv4 addresses on its networks, the one with the
    default route first: where the phone looks for it. Containers' and
    virtual machines' bridges are left out (VIRTUAL)."""
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


# --- The service ------------------------------------------------------------------

class Deck:
    """What the HTTPS side and the control socket share."""

    def __init__(self, config, folder, pin):
        self.config = config
        self.pin = pin
        self.name = config.get("name") or socket.gethostname()
        self.port = int(config.get("port", PORT))
        self.devices = Devices(os.path.join(folder, "devices.json"))
        self.pairing = Pairing()
        self.throttle = Throttle()
        self.session = Session(config)
        self.strings = config.get("strings", {})

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
            # Whether the code still pairs, so Preferences knows when its QR
            # stops being any use (used, expired, or five wrong codes).
            return {"devices": self.devices.listing(), "pairing": self.pairing.open_now}
        if op == "forget":
            return {"ok": self.devices.forget(str(request.get("id", "")))}
        if op == "status":
            return {"port": self.port, "pin": self.pin, "devices": len(self.devices.listing()),
                    "pairing": self.pairing.open_now}
        return {"error": "unknown"}

    def paired(self, name):
        title = self.strings.get("deckPaired", "%1 can now use this computer as a deck").replace("%1", name)
        self.session.notify(title, self.strings.get("deckPairedBody", ""))


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "nihil-deck/" + str(API)
    sys_version = ""

    # TLS here, in this connection's thread, with its timeout.
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
        # When this answer ends the connection (429, a body it won't read),
        # the phone hears it and doesn't send the next request down it.
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

    def do_POST(self):
        # A phone's kanban can be more than any other request.
        body = self.read_body(TASKS_MAX if urllib.parse.urlsplit(self.path).path == "/v1/tasks" else MAX_BODY)
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
        elif method == "POST" and path == "/v1/lock":
            if session.lock_screen():
                self.reply(200, {"ok": True})
            else:
                self.reply(503, {"error": "lock"})
        elif method == "POST" and path == "/v1/unpair":
            deck.devices.forget(device["id"])
            self.reply(200, {"ok": True})
        else:
            self.reply(404, {"error": "path"})


class DeckServer(http.server.ThreadingHTTPServer):
    """HTTPS on both IPv6 and IPv4 where it can."""

    daemon_threads = True
    timeout_seconds = 15

    def __init__(self, address, deck, context):
        self.deck = deck
        self.context = context
        host, port = address
        self.address_family = socket.AF_INET6 if ":" in host else socket.AF_INET
        super().__init__((host, port), Handler)

    # As HTTPServer's, without asking DNS for a name it does not use.
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


# --- The commands -----------------------------------------------------------------

def ask(request, path=None):
    """One request to the service, on its socket."""
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
    """qrencode -t ASCII's QR, as rows of 0 and 1 (two characters a module,
    "#" for the dark ones)."""
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


def main():
    parser = argparse.ArgumentParser(prog="nihil-deck", description="The phone as a deck for this computer (docs/deck.md).")
    parser.add_argument("--config", help="configuration written by home/deck/default.nix")
    parser.add_argument("command", nargs="?", default="devices", choices=["serve", "pair", "cancel", "devices", "forget"])
    parser.add_argument("target", nargs="?", help="forget: a phone's id, or all")
    parser.add_argument("--json", action="store_true", help="for the shell")
    options = parser.parse_args()

    config = {}
    if options.config:
        with open(options.config) as file:
            config = json.load(file)
    for key, command in (("ipc", "nihil-ipc"), ("volume", "osd-volume"),
                         ("notify", "notify-send"), ("openssl", "openssl"), ("qrencode", "qrencode"),
                         ("rsvg", "rsvg-convert"), ("ip", "ip"), ("wpctl", "wpctl")):
        config.setdefault(key, shutil.which(command) or command)

    if options.command == "serve":
        serve(config)
        return 0

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
