#!/usr/bin/env python3
# test_deck.py by poligle
#
# Tests for the deck's service: the real HTTPS server on 127.0.0.1, with a
# throwaway certificate, a client that pins it as the phone does, and fake
# nihil-ipc, osd-volume, wpctl, notify-send and ip that write down
# what they were asked. Nothing leaves this computer. Needs openssl.
#
#   python3 -m unittest home/deck/test_deck.py

import base64
import hashlib
import http.client
import http.server
import json
import os
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import deck  # noqa: E402

OPENSSL = shutil.which("openssl")

APPS = [
    {"id": "zen-beta", "name": "Zen", "icon": "zen-browser"},
    {"id": "kitty", "name": "kitty", "icon": "kitty"},
    {"id": "org.gnome.Nautilus", "name": "Files", "icon": "/nowhere/files.png"},
]

FAKE_IPC = r'''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["DECK_LOG"], "a") as log:
    log.write("ipc " + " ".join(sys.argv[1:]) + "\n")
if os.environ.get("DECK_SHELL_DOWN"):
    sys.exit(1)
args = sys.argv[1:]
apps = json.loads(os.environ["DECK_APPS"])
if args[:2] == ["apps", "list"]:
    print(json.dumps(apps))
elif args[:2] == ["apps", "launch"]:
    print("ok" if any(a["id"] == args[2] for a in apps) else "unknown")
elif args[:2] == ["apps", "url"]:
    print("ok")
elif args[:2] == ["media", "now"]:
    print(json.dumps({"title": "Song", "artist": "Someone", "player": "Spotify", "playing": True, "art": os.environ.get("DECK_ART", "")}))
elif args[:2] == ["tasks", "state"]:
    print(json.dumps({"cards": [{"id": "a", "text": "Desk", "column": 0, "textStamp": 1, "placeStamp": 1}], "removed": {}, "now": 5}))
elif args[:2] == ["tasks", "sync"]:
    board = json.loads(args[2])
    board["cards"].append({"id": "a", "text": "Desk", "column": 0, "textStamp": 1, "placeStamp": 1})
    board["now"] = 5
    print(json.dumps(board))
elif args[0] == "media" or args == ["session", "lock"]:
    pass
else:
    sys.exit(1)
'''

FAKE_LOGGER = r'''#!/bin/sh
echo "{name} $*" >> "$DECK_LOG"
'''

FAKE_WPCTL = r'''#!/bin/sh
echo "wpctl $*" >> "$DECK_LOG"
echo "Volume: 0.45"
'''

FAKE_IP = r'''#!/bin/sh
case "$*" in
    *"route get"*) echo '[{"dst":"192.0.2.1","gateway":"192.168.1.1","dev":"wlan0","prefsrc":"192.168.1.20"}]' ;;
    *"addr show"*) echo '[{"ifname":"wlan0","addr_info":[{"family":"inet","local":"192.168.1.20"}]},{"ifname":"docker0","addr_info":[{"family":"inet","local":"172.17.0.1"}]},{"ifname":"virbr0","addr_info":[{"family":"inet","local":"192.168.122.1"}]},{"ifname":"tailscale0","addr_info":[{"family":"inet","local":"100.64.0.7"}]}]' ;;
esac
'''


def script(folder, name, text):
    path = os.path.join(folder, name)
    with open(path, "w") as file:
        file.write(text)
    os.chmod(path, 0o755)
    return path


def spki_pin_with_openssl(cert):
    """The pin as openssl sees it: the SHA-256 of the public key, DER."""
    public = subprocess.run([OPENSSL, "x509", "-pubkey", "-noout", "-in", cert], check=True, capture_output=True).stdout
    der = subprocess.run([OPENSSL, "pkey", "-pubin", "-outform", "DER"], input=public, check=True, capture_output=True).stdout
    return base64.urlsafe_b64encode(hashlib.sha256(der).digest()).rstrip(b"=").decode()


class Phone:
    """A client as the phone is: any certificate, as long as its public key
    is the one pinned."""

    def __init__(self, port, pin, token=""):
        self.port = port
        self.pin = pin
        self.token = token

    def request(self, method, path, body=None, token=None):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        connection = http.client.HTTPSConnection("127.0.0.1", self.port, context=context, timeout=10)
        connection.connect()
        der = connection.sock.getpeercert(binary_form=True)
        seen = deck.b64url(hashlib.sha256(deck.public_key_info(der)).digest())
        if seen != self.pin:
            raise AssertionError("the certificate is not the one pinned")
        headers = {}
        token = self.token if token is None else token
        if token:
            headers["Authorization"] = "Bearer " + token
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        connection.request(method, path, body=data, headers=headers)
        response = connection.getresponse()
        self.last = response
        payload = response.read()
        kind = response.getheader("Content-Type")
        connection.close()
        if kind == "application/json":
            return response.status, json.loads(payload)
        return response.status, payload


@unittest.skipIf(OPENSSL is None, "needs openssl")
class Base(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp(prefix="deck-test-")
        self.addCleanup(shutil.rmtree, self.folder, True)
        self.log = os.path.join(self.folder, "log")
        open(self.log, "w").close()
        bin_dir = os.path.join(self.folder, "bin")
        os.makedirs(bin_dir)
        self.env = {"DECK_LOG": self.log, "DECK_APPS": json.dumps(APPS)}
        self.old_env = {key: os.environ.get(key) for key in list(self.env) + ["DECK_SHELL_DOWN", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR"]}
        os.environ.update(self.env)
        os.environ["XDG_CACHE_HOME"] = os.path.join(self.folder, "cache")
        os.environ["XDG_RUNTIME_DIR"] = self.folder
        self.addCleanup(self.restore_env)
        self.config = {
            "port": 0,
            "name": "nihil-test",
            "strings": {"deckPaired": "%1 is a deck now", "deckPairedBody": "Forget it in Preferences."},
            "ipc": script(bin_dir, "nihil-ipc", FAKE_IPC.replace("#!/usr/bin/env python3", "#!" + sys.executable)),
            "volume": script(bin_dir, "osd-volume", FAKE_LOGGER.replace("{name}", "osd-volume")),
            "notify": script(bin_dir, "notify-send", FAKE_LOGGER.replace("{name}", "notify-send")),
            "wpctl": script(bin_dir, "wpctl", FAKE_WPCTL),
            "ip": script(bin_dir, "ip", FAKE_IP),
            "openssl": OPENSSL,
            "rsvg": "/nonexistent/rsvg-convert",
            "iconTheme": "Test-Theme",
        }

    def restore_env(self):
        for key, value in self.old_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def logged(self):
        with open(self.log) as file:
            return file.read().splitlines()


class CertificateTest(Base):
    def test_made_once_private_and_pinned_by_its_public_key(self):
        state = os.path.join(self.folder, "state")
        cert, key = deck.ensure_certificate(state, OPENSSL)
        self.assertEqual(os.stat(key).st_mode & 0o777, 0o600)
        self.assertEqual(os.stat(state).st_mode & 0o777, 0o700)
        pin = deck.pin_of(cert)
        self.assertEqual(pin, spki_pin_with_openssl(cert))
        self.assertEqual(len(pin), 43)
        # A second time it is the same one.
        again, _ = deck.ensure_certificate(state, OPENSSL)
        self.assertEqual(deck.pin_of(again), pin)


class PairingTest(unittest.TestCase):
    def test_once_and_not_after_wrong_codes(self):
        pairing = deck.Pairing()
        self.assertEqual(pairing.take("ANY"), "closed")
        code, _ = pairing.open()
        self.assertEqual(len(code), deck.CODE_LENGTH)
        self.assertTrue(set(code) <= set(deck.CODE_ALPHABET))
        for _ in range(deck.CODE_ATTEMPTS - 1):
            self.assertEqual(pairing.take("WRONG"), "wrong")
        self.assertEqual(pairing.take(code.lower()), "ok")
        self.assertEqual(pairing.take(code), "closed")

        code, _ = pairing.open()
        for _ in range(deck.CODE_ATTEMPTS):
            self.assertEqual(pairing.take("WRONG"), "wrong")
        self.assertEqual(pairing.take(code), "closed")

    def test_expires(self):
        pairing = deck.Pairing()
        code, _ = pairing.open()
        pairing.expires = time.time() - 1
        self.assertFalse(pairing.open_now)
        self.assertEqual(pairing.take(code), "expired")
        self.assertEqual(pairing.take(code), "closed")


class UrlTest(unittest.TestCase):
    def test_only_web_pages(self):
        for url in ("https://nixos.org", "http://192.168.1.1:8080/admin?x=1#y", "https://example.com/a%20b"):
            self.assertTrue(deck.valid_url(url), url)
        for url in ("javascript:alert(1)", "file:///etc/passwd", "https://", "https://exa mple.com",
                    "https://example.com/\n", "ftp://example.com", "", None, 42, "https://" + "a" * 2050,
                    "nihil-deck://pair", "about:blank"):
            self.assertFalse(deck.valid_url(url), url)


class QrTest(unittest.TestCase):
    def ascii(self, rows):
        return "\n".join("".join("##" if module == "1" else "  " for module in row).rstrip() for row in rows) + "\n"

    def test_modules_from_qrencode_ascii(self):
        rows = ["".join("1" if (x * 7 + y * 3) % 5 == 0 or x < 7 and y < 7 else "0" for x in range(21)) for y in range(21)]
        self.assertEqual(deck.qr_rows(self.ascii(rows)), rows)

    def test_not_a_qr(self):
        with self.assertRaises(ValueError):
            deck.qr_rows("##  ##\n##  ##\n")
        with self.assertRaises(ValueError):
            deck.qr_rows("")


class IconTest(unittest.TestCase):
    def setUp(self):
        self.base = tempfile.mkdtemp(prefix="deck-icons-")
        self.addCleanup(shutil.rmtree, self.base, True)

    def theme(self, name, inherits, files):
        root = os.path.join(self.base, "icons", name)
        directories = sorted({os.path.dirname(path) for path in files})
        os.makedirs(root, exist_ok=True)
        with open(os.path.join(root, "index.theme"), "w") as file:
            file.write("[Icon Theme]\nName=%s\n" % name)
            if inherits:
                file.write("Inherits=%s\n" % inherits)
            file.write("Directories=%s\n\n" % ",".join(directories))
            for directory in directories:
                scalable = "scalable" in directory
                file.write("[%s]\nSize=%s\nType=%s\n\n" % (directory, 48 if scalable else directory.split("x")[0].split("/")[-1],
                                                           "Scalable" if scalable else "Fixed"))
        for path in files:
            full = os.path.join(root, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            open(full, "w").close()
        return root

    def test_theme_then_what_it_inherits_then_hicolor(self):
        deck.theme_index.cache_clear()
        child = self.theme("Child", "Parent", ["apps/scalable/zen-browser.svg"])
        parent = self.theme("Parent", "", ["32x32/apps/kitty.png", "128x128/apps/kitty.png"])
        hicolor = self.theme("hicolor", "", ["48x48/apps/thunar.png"])
        dirs = [self.base]
        self.assertEqual(deck.icon_file("zen-browser", "Child", dirs), os.path.join(child, "apps/scalable/zen-browser.svg"))
        self.assertEqual(deck.icon_file("kitty", "Child", dirs), os.path.join(parent, "128x128/apps/kitty.png"))
        self.assertEqual(deck.icon_file("thunar", "Child", dirs), os.path.join(hicolor, "48x48/apps/thunar.png"))
        self.assertIsNone(deck.icon_file("nothing", "Child", dirs))
        self.assertIsNone(deck.icon_file("../../etc/passwd", "Child", dirs))
        self.assertIsNone(deck.icon_file("/etc/passwd", "Child", dirs))

    def test_the_size_closest_to_the_phones(self):
        deck.theme_index.cache_clear()
        big = self.theme("Big", "", ["48x48/apps/foot.png", "256x256/apps/foot.png", "512x512/apps/foot.png"])
        small = self.theme("Small", "", ["32x32/apps/foot.png", "64x64/apps/foot.png"])
        self.assertEqual(deck.icon_file("foot", "Big", [self.base]), os.path.join(big, "256x256/apps/foot.png"))
        self.assertEqual(deck.icon_file("foot", "Small", [self.base]), os.path.join(small, "64x64/apps/foot.png"))


class AddressesTest(Base):
    def test_the_default_route_first(self):
        # docker0 and virbr0 are not where a phone finds it; Tailscale is.
        self.assertEqual(deck.addresses(self.config["ip"]), ["192.168.1.20", "100.64.0.7"])


class ServerTest(Base):
    def setUp(self):
        super().setUp()
        state = os.path.join(self.folder, "state")
        self.server = deck.make_server(self.config, state, host="127.0.0.1")
        self.deck = self.server.deck
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop)
        self.phone = Phone(self.deck.port, self.deck.pin)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()

    def pair(self, name="Galaxy A35"):
        reply = self.deck.control({"op": "pair"})
        status, body = self.phone.request("POST", "/v1/pair", {"code": reply["code"], "device": name})
        self.assertEqual(status, 200, body)
        self.phone.token = body["token"]
        return body

    def test_pairing_with_the_code_in_the_qr(self):
        status, body = self.phone.request("GET", "/v1/hello")
        self.assertEqual((status, body), (200, {"deck": deck.API, "name": "nihil-test"}))
        self.assertEqual(self.phone.request("GET", "/v1/apps")[0], 401)

        reply = self.deck.control({"op": "pair"})
        self.assertIn("code=" + reply["code"], reply["uri"])
        self.assertIn("pin=" + self.deck.pin, reply["uri"])
        self.assertIn("hosts=192.168.1.20,100.64.0.7", reply["uri"])
        self.assertTrue(reply["uri"].startswith("nihil-deck://pair?v=1&name=nihil-test&"))

        self.assertEqual(self.phone.request("POST", "/v1/pair", {"code": "WRONGCODE", "device": "x"})[0], 403)
        status, body = self.phone.request("POST", "/v1/pair", {"code": reply["code"], "device": "Galaxy\x07 A35"})
        self.assertEqual(status, 200, body)
        self.assertEqual(body["name"], "nihil-test")
        # Once: the same code no longer pairs.
        self.assertEqual(self.phone.request("POST", "/v1/pair", {"code": reply["code"], "device": "other"})[0], 409)

        devices = self.deck.control({"op": "devices"})["devices"]
        self.assertEqual([(d["id"], d["name"]) for d in devices], [(body["device"], "Galaxy A35")])
        self.assertIn("notify-send -a NIHIL Galaxy A35 is a deck now Forget it in Preferences.", self.logged())
        # Only the token's hash is kept.
        with open(os.path.join(self.folder, "state", "devices.json")) as file:
            stored = file.read()
        self.assertNotIn(body["token"], stored)
        self.assertEqual(os.stat(os.path.join(self.folder, "state", "devices.json")).st_mode & 0o777, 0o600)

    def test_what_a_paired_phone_may_do(self):
        self.pair()
        status, body = self.phone.request("GET", "/v1/apps")
        self.assertEqual(status, 200)
        self.assertEqual([a["id"] for a in body["apps"]], ["zen-beta", "kitty", "org.gnome.Nautilus"])

        self.assertEqual(self.phone.request("POST", "/v1/open", {"app": "zen-beta"}), (200, {"ok": True}))
        self.assertEqual(self.phone.request("POST", "/v1/open", {"app": "rm -rf ~"})[0], 404)
        self.assertEqual(self.phone.request("POST", "/v1/open", {"app": "steam"})[0], 404)
        self.assertEqual(self.phone.request("POST", "/v1/open", {"url": "https://nixos.org"}), (200, {"ok": True}))
        self.assertEqual(self.phone.request("POST", "/v1/open", {"url": "file:///etc/shadow"})[0], 400)
        self.assertEqual(self.phone.request("POST", "/v1/open", {})[0], 400)

        self.assertEqual(self.phone.request("POST", "/v1/media", {"action": "toggle"}), (200, {"ok": True}))
        self.assertEqual(self.phone.request("POST", "/v1/media", {"action": "shutdown"})[0], 400)
        self.assertEqual(self.phone.request("POST", "/v1/volume", {"action": "up"}), (200, {"level": 45, "muted": False}))
        self.assertEqual(self.phone.request("POST", "/v1/lock", {}), (200, {"ok": True}))

        status, body = self.phone.request("GET", "/v1/state")
        self.assertEqual(status, 200)
        self.assertEqual(body["media"]["title"], "Song")
        self.assertEqual(body["volume"], {"level": 45, "muted": False})

        calls = self.logged()
        self.assertIn("ipc apps launch zen-beta", calls)
        self.assertIn("ipc apps url https://nixos.org", calls)
        self.assertNotIn("ipc apps launch steam", calls)
        self.assertIn("ipc media toggle", calls)
        self.assertIn("osd-volume up", calls)
        self.assertIn("ipc session lock", calls)
        self.assertFalse(any("shadow" in call or "rm -rf" in call for call in calls))

        self.assertEqual(self.phone.request("GET", "/v1/nothing")[0], 404)
        self.assertEqual(self.phone.request("POST", "/v1/unpair", {}), (200, {"ok": True}))
        self.assertEqual(self.phone.request("GET", "/v1/apps")[0], 401)

    def test_without_the_shell(self):
        self.pair()
        os.environ["DECK_SHELL_DOWN"] = "1"
        self.deck.session.cached = None
        self.assertEqual(self.phone.request("GET", "/v1/apps")[0], 503)
        self.assertEqual(self.phone.request("POST", "/v1/media", {"action": "next"})[0], 503)

    def test_icons(self):
        theme = os.path.join(self.folder, "share", "icons", "Test-Theme", "48x48", "apps")
        os.makedirs(theme)
        with open(os.path.join(self.folder, "share", "icons", "Test-Theme", "index.theme"), "w") as file:
            file.write("[Icon Theme]\nName=Test\nDirectories=48x48/apps\n\n[48x48/apps]\nSize=48\nType=Fixed\n")
        with open(os.path.join(theme, "kitty.png"), "wb") as file:
            file.write(b"\x89PNG\r\n\x1a\nfake")
        old = os.environ.get("XDG_DATA_DIRS")
        os.environ["XDG_DATA_DIRS"] = os.path.join(self.folder, "share")
        self.addCleanup(lambda: os.environ.__setitem__("XDG_DATA_DIRS", old) if old is not None else os.environ.pop("XDG_DATA_DIRS", None))
        deck.theme_index.cache_clear()
        self.pair()
        self.assertEqual(self.phone.request("GET", "/v1/apps/kitty/icon"), (200, b"\x89PNG\r\n\x1a\nfake"))
        # An SVG needs rsvg-convert, which is not here; an app not listed, nothing.
        self.assertEqual(self.phone.request("GET", "/v1/apps/zen-beta/icon")[0], 404)
        self.assertEqual(self.phone.request("GET", "/v1/apps/..%2F..%2Fetc/icon")[0], 404)

    def test_the_icon_of_a_web(self):
        site = Site({"/": (200, "text/html", b'<link rel="icon" href="/i.png" sizes="64x64">'),
                     "/i.png": (200, "image/png", PNG + b"64")})
        self.addCleanup(site.stop)
        deck.PUBLIC_ONLY = False
        self.addCleanup(setattr, deck, "PUBLIC_ONLY", True)
        old = os.environ.get("XDG_CACHE_HOME")
        os.environ["XDG_CACHE_HOME"] = os.path.join(self.folder, "cache")
        self.addCleanup(lambda: os.environ.__setitem__("XDG_CACHE_HOME", old) if old is not None else os.environ.pop("XDG_CACHE_HOME", None))
        self.pair()
        quoted = urllib.parse.quote(site.url + "/blog/post", safe="")
        self.assertEqual(self.phone.request("GET", "/v1/favicon?url=" + quoted), (200, PNG + b"64"))
        self.assertEqual(self.phone.last.getheader("Content-Type"), "image/png")
        self.assertEqual(self.phone.request("GET", "/v1/favicon?url=" + urllib.parse.quote("file:///etc/passwd", safe=""))[0], 400)
        self.assertEqual(self.phone.request("GET", "/v1/favicon")[0], 400)
        self.assertEqual(self.phone.request("GET", "/v1/favicon?url=x", token="nope")[0], 401)

    def test_the_kanban(self):
        self.pair()
        status, body = self.phone.request("GET", "/v1/tasks")
        self.assertEqual((status, body["cards"][0]["text"], body["now"]), (200, "Desk", 5))
        phone = {"cards": [{"id": "p", "text": "  Phone   card ", "column": 1, "textStamp": 3, "placeStamp": 4}], "removed": {"z": 2}}
        status, body = self.phone.request("POST", "/v1/tasks", phone)
        self.assertEqual(status, 200)
        self.assertEqual([c["id"] for c in body["cards"]], ["p", "a"])
        self.assertEqual(body["cards"][0]["text"], "Phone card")
        self.assertEqual(body["removed"], {"z": 2})
        for bad in ({"cards": [{"id": "x", "text": "No column", "textStamp": 1, "placeStamp": 1}]},
                    {"cards": "nope"}, {"removed": {"x": "yesterday"}}):
            self.assertEqual(self.phone.request("POST", "/v1/tasks", bad)[0], 400)
        # A whole kanban is more than other requests may carry.
        many = {"cards": [{"id": "c%d" % i, "text": "Task %d" % i, "column": 0, "textStamp": i, "placeStamp": i} for i in range(80)]}
        self.assertEqual(self.phone.request("POST", "/v1/tasks", many)[0], 200)

    def test_the_cover(self):
        art = os.path.join(self.folder, "cover.png")
        with open(art, "wb") as file:
            file.write(deck.PNG_MAGIC + b"cover")
        old = os.environ.get("DECK_ART")
        os.environ["DECK_ART"] = "file://" + art
        self.addCleanup(lambda: os.environ.__setitem__("DECK_ART", old) if old is not None else os.environ.pop("DECK_ART", None))
        self.pair()
        status, body = self.phone.request("GET", "/v1/state")
        token = body["media"]["cover"]
        self.assertNotIn("art", body["media"])
        self.assertEqual(len(token), 16)
        self.assertEqual(self.phone.request("GET", "/v1/cover?c=" + token), (200, deck.PNG_MAGIC + b"cover"))
        self.assertEqual(self.phone.request("GET", "/v1/cover?c=0123456789abcdef")[0], 404)
        self.assertEqual(self.phone.request("GET", "/v1/cover?c=../../etc")[0], 404)

    def test_wrong_tokens_wait(self):
        for _ in range(deck.FAIL_LIMIT):
            self.assertEqual(self.phone.request("GET", "/v1/apps", token="nope")[0], 401)
        self.assertEqual(self.phone.request("GET", "/v1/hello")[0], 429)
        self.assertEqual(self.phone.last.getheader("Connection"), "close")

    def test_a_body_too_big(self):
        self.pair()
        status, body = self.phone.request("POST", "/v1/open", {"url": "https://example.com/" + "a" * deck.MAX_BODY})
        self.assertEqual((status, body), (400, {"error": "body"}))
        self.assertEqual(self.phone.last.getheader("Connection"), "close")
        # An answer that keeps the connection doesn't say close.
        self.assertEqual(self.phone.request("GET", "/v1/hello")[0], 200)
        self.assertIsNone(self.phone.last.getheader("Connection"))

    def test_whether_the_code_still_pairs(self):
        self.deck.control({"op": "pair"})
        self.assertTrue(self.deck.control({"op": "devices"})["pairing"])
        self.pair()
        self.assertFalse(self.deck.control({"op": "devices"})["pairing"])

    def test_forgetting_from_here(self):
        paired = self.pair()
        self.assertEqual(self.deck.control({"op": "forget", "id": "nope"}), {"ok": False})
        self.assertEqual(self.deck.control({"op": "forget", "id": paired["device"]}), {"ok": True})
        self.assertEqual(self.phone.request("GET", "/v1/apps")[0], 401)


PNG = deck.PNG_MAGIC + b"an icon"


def ico(*entries):
    """An .ico whose entries are (size, data)."""
    head = struct.pack("<HHH", 0, 1, len(entries))
    offset = 6 + 16 * len(entries)
    table, body = b"", b""
    for size, data in entries:
        table += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(data), offset + len(body))
        body += data
    return head + table + body


class Site:
    """A web site on 127.0.0.1: path -> (status, type, body); counts requests."""

    def __init__(self, pages):
        site = self
        self.pages = pages
        self.asked = []

        class Pages(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                site.asked.append(self.path)
                status, kind, body = site.pages.get(self.path, (404, "text/plain", b"no"))
                self.send_response(status)
                self.send_header("Content-Type", kind)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Pages)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = "http://127.0.0.1:%d" % self.server.server_address[1]

    def stop(self):
        self.server.shutdown()
        self.server.server_close()


class FaviconTest(unittest.TestCase):
    def setUp(self):
        self.cache = tempfile.mkdtemp(prefix="deck-icons-")
        self.addCleanup(shutil.rmtree, self.cache, True)
        deck.PUBLIC_ONLY = False
        self.addCleanup(setattr, deck, "PUBLIC_ONLY", True)

    def site(self, pages):
        site = Site(pages)
        self.addCleanup(site.stop)
        return site

    def test_the_best_icon_the_home_page_names(self):
        page = (b'<html><head><link rel="icon" href="/small.png" sizes="16x16">'
                b'<link rel="apple-touch-icon" href="/touch.png"></head><body>'
                b'<link rel="icon" href="/late.png" sizes="512x512"></body></html>')
        site = self.site({"/": (200, "text/html", page), "/small.png": (200, "image/png", PNG + b"16"),
                          "/touch.png": (200, "image/png", PNG + b"180"), "/late.png": (200, "image/png", PNG + b"late")})
        self.assertEqual(deck.favicon(site.url + "/some/page?q=1", "rsvg-convert", self.cache), (PNG + b"180", "image/png"))
        # A week from here, without asking the site again.
        asked = len(site.asked)
        self.assertEqual(deck.favicon(site.url + "/other", "rsvg-convert", self.cache), (PNG + b"180", "image/png"))
        self.assertEqual(len(site.asked), asked)

    def test_the_png_inside_the_ico_when_the_page_names_none(self):
        site = self.site({"/": (200, "text/html", b"<html><head></head></html>"),
                          "/favicon.ico": (200, "image/x-icon", ico((16, b"BM bitmap"), (32, PNG + b"32"), (24, PNG + b"24")))})
        self.assertEqual(deck.favicon(site.url, "rsvg-convert", self.cache), (PNG + b"32", "image/png"))

    def test_none_and_it_is_remembered(self):
        site = self.site({"/favicon.ico": (200, "image/x-icon", ico((16, b"BM only bitmaps")))})
        self.assertIsNone(deck.favicon(site.url + "/", "rsvg-convert", self.cache))
        asked = len(site.asked)
        self.assertIsNone(deck.favicon(site.url + "/", "rsvg-convert", self.cache))
        self.assertEqual(len(site.asked), asked)

    def test_jpeg_and_webp_as_they_come_and_nothing_else(self):
        self.assertEqual(deck.as_image(b"\xff\xd8\xffjpeg", "x"), (b"\xff\xd8\xffjpeg", "image/jpeg"))
        self.assertEqual(deck.as_image(b"RIFF\x00\x00\x00\x00WEBPVP8 ", "x")[1], "image/webp")
        self.assertIsNone(deck.as_image(b"<html>not an icon</html>", "x"))

    def test_only_public_addresses(self):
        deck.PUBLIC_ONLY = True
        for host in ("127.0.0.1", "localhost", "10.0.0.7", "192.168.1.1", "169.254.169.254", "::1"):
            self.assertFalse(deck.public(host), host)
        site = self.site({"/": (200, "text/html", b"")})
        with self.assertRaises(ValueError):
            deck.fetch(site.url + "/", 100)
        redirect = deck.PublicRedirects()
        with self.assertRaises(deck.urllib.error.URLError):
            redirect.redirect_request(None, None, 302, "Found", {}, "http://192.168.1.1/admin")


class ControlTest(Base):
    def test_the_socket(self):
        state = os.path.join(self.folder, "state")
        server = deck.make_server(self.config, state, host="127.0.0.1")
        path = os.path.join(self.folder, "control.sock")
        control = deck.ControlServer(path, server.deck)
        threading.Thread(target=control.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(control.server_close)
        self.addCleanup(control.shutdown)
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        reply = deck.ask({"op": "pair"}, path)
        self.assertTrue(reply["uri"].startswith("nihil-deck://pair?"))
        self.assertTrue(deck.ask({"op": "status"}, path)["pairing"])
        self.assertEqual(deck.ask({"op": "cancel"}, path), {"ok": True})
        self.assertFalse(deck.ask({"op": "status"}, path)["pairing"])
        self.assertEqual(deck.ask({"op": "devices"}, path), {"devices": [], "pairing": False})
        self.assertEqual(deck.ask({"op": "nonsense"}, path), {"error": "unknown"})
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as raw:
            raw.connect(path)
            raw.sendall(b"not json\n")
            self.assertEqual(json.loads(raw.recv(4096)), {"error": "unknown"})


if __name__ == "__main__":
    unittest.main()
