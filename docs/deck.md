# The deck: the phone opens things on the computer

[NIHIL Launcher](https://github.com/poligle/Nihil-Launcher), on Android, can be a deck for a NIHIL computer: it opens the computer's
apps and web pages, plays and skips its music, turns its volume, locks it, is its
trackpad and carries things to it and from it (Vector). This is what the computer offers,
for whoever writes the phone's side.

The computer's side is `nihil-deck` ([`home/deck/deck.py`](../home/deck/deck.py)), a
service in the user's session. Preferences, Devices turns it on (`settings.json`'s
`"deck": { "enable": true }`, a rebuild) and pairs phones with a QR.

It does only what is listed here. There is no way to run a command, read a file or type
on the computer: an app can only be one the launcher shows, a page only `http` or
`https`, Vector gives only what was sent to it and keeps what comes in its own folder, and
the trackpad points and clicks as a touchpad there would, nothing more.

## Pairing

Preferences, Devices, "Pair a device" shows a QR with this URI:

```
nihil-deck://pair?v=1&name=nihil&hosts=192.168.1.20,100.64.0.7&port=64445&code=7JTX39F4&pin=8-eMVPli0fpzjeUBe-b_bmRtjDMwo1bNYXaVTyPSbVc
```

| Parameter | What it is |
|-----------|------------|
| `v`       | The protocol, `1` |
| `name`    | The computer's name (its host name) |
| `hosts`   | Its IPv4 addresses, comma-separated, the one with the default route first; not those of containers' and virtual machines' bridges (Docker, libvirt), which a phone can't reach. A VPN's (Tailscale) stays |
| `port`    | Its port, `64445` unless the machine sets `nihil.deck.port` |
| `code`    | The one-time code: 8 characters of `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` |
| `pin`     | SHA-256 of the certificate's public key (SubjectPublicKeyInfo, DER), base64url without padding |

The code pairs **one** phone, for **five minutes**. Five wrong codes and it stops; the
QR in Preferences makes a new one before it runs out, and goes away once a phone pairs.

1. Connect to each of `hosts` in order, on `port`, over TLS (see below), until one
   answers `GET /v1/hello`.
2. `POST /v1/pair` with the code and the phone's name.
3. Keep what it returns, the token above all, with the pin, the name, the port and the
   address that answered.

The computer shows a notification when a phone pairs, and lists it in Preferences, Devices,
where it can be forgotten.

## TLS and the pin

The computer has its own certificate (EC P-256, self-signed, made the first time the
service starts). The phone accepts it only when the SHA-256 of its public key is the
`pin` from the QR, and otherwise closes the connection **before sending anything**, the
token least of all. Host names are not checked: the pin is the check, and addresses
change.

```kotlin
class PinnedTrust(private val pin: String) : X509TrustManager {
    override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
        val hash = MessageDigest.getInstance("SHA-256").digest(chain[0].publicKey.encoded)
        val seen = Base64.encodeToString(hash, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        if (seen != pin) throw CertificateException("not this computer")
    }
    override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) =
        throw CertificateException("no clients")
    override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
}

val tls = SSLContext.getInstance("TLS").apply { init(null, arrayOf(PinnedTrust(pin)), null) }
(connection as HttpsURLConnection).apply {
    sslSocketFactory = tls.socketFactory
    hostnameVerifier = HostnameVerifier { _, _ -> true }   // the pin decides
}
```

`publicKey.encoded` is the SubjectPublicKeyInfo in DER, the same bytes the computer
hashes. TLS 1.2 or 1.3.

From a computer, curl checks the same pin (it wants standard base64, with its `=`):

```bash
pin=8-eMVPli0fpzjeUBe-b_bmRtjDMwo1bNYXaVTyPSbVc
curl --insecure --pinnedpubkey "sha256//$(printf '%s=' "$pin" | tr '_-' '/+')" https://192.168.1.20:64445/v1/hello
```

## Finding the computer again

Its address may change. The phone tries the address that last answered, then the others
from the QR, then looks on the local network: the computer announces itself with mDNS
(Avahi) as `_nihil-deck._tcp`, named after the computer, with a TXT record `v=1`.
On Android, `NsdManager.discoverServices("_nihil-deck._tcp", NsdManager.PROTOCOL_DNS_SD, …)`.
Whatever it finds, the pin still decides whether it is the right computer.

## Requests

HTTPS, HTTP/1.1, JSON in and out (`Content-Type: application/json`, a body of 4 KB at
most; Vector's are the exception). Connections may be kept open; the computer closes them after 15 s idle, and after an
answer that ends one (a `429`, a body too big), which then says `Connection: close`. It
holds 32 at once, from every phone together: one more is closed before its handshake.

Everything but `hello` and `pair` needs the token:

```
Authorization: Bearer <token>
```

### `GET /v1/hello`

No token. Whether it is there, and which computer.

```json
{ "deck": 1, "name": "nihil" }
```

### `POST /v1/pair`

No token.

```json
{ "code": "7JTX39F4", "device": "Phone" }
```

```json
{ "token": "…43 characters…", "device": "3f9a1c2e", "name": "nihil" }
```

`device` is the phone's id on the computer; the name it sent is cut at 40 characters.
`403` wrong code, `409` no code open (none shown, or used), `410` expired.

### `GET /v1/apps`

The apps the launcher shows, by name.

```json
{ "apps": [ { "id": "zen-beta", "name": "Zen" }, { "id": "kitty", "name": "kitty" } ] }
```

### `GET /v1/apps/{id}/icon`

The app's icon as PNG (`Content-Type: image/png`), from the computer's icon theme: 128 px
when the theme draws it (SVG), or the theme's own PNG closest to 128, bigger ones first, so
scale it to fit. `404` when it has none. `{id}` percent-encoded. They change rarely: keep them.

### `GET /v1/favicon?url={url}`

The icon of a web's site, for the webs the phone keeps: the computer looks for it, so the
phone talks to no one else. `{url}` percent-encoded, http or https. On the site's home page
it takes an SVG (drawn at 128 px), the `apple-touch-icon` or the biggest icon it names, and
then `/favicon.ico` (the biggest PNG inside it). Only at public addresses, redirects too:
never this computer's network. `200` with the picture as it comes (`image/png`,
`image/jpeg`, `image/gif` or `image/webp`; scale it to fit), `404` when the site has none
the phone can draw (draw its letter), `400` for a URL that isn't one. The computer keeps
each site's icon, and each miss, a week: ask freely.

### `POST /v1/open`

An app, by its id:

```json
{ "app": "zen-beta" }
```

or a web page, in the computer's browser:

```json
{ "url": "https://nixos.org" }
```

`{ "ok": true }`; `404` an app the launcher doesn't have, `400` a page that is not
`http` or `https` (or has spaces, or is longer than 2048).

### `POST /v1/media`

What plays on the computer (the one playing, or the first player):

```json
{ "action": "toggle" }
```

`toggle`, `next` or `previous`. `{ "ok": true }`.

### `POST /v1/volume`

The output's volume, as the computer's keys turn it (with its OSD and sound):

```json
{ "action": "up" }
```

`up`, `down` (5 % each) or `mute` (on and off). It answers with the volume after:

```json
{ "level": 45, "muted": false }
```

### `POST /v1/lock`

Locks the screen. `{ "ok": true }`. Unlocking is only on the computer.

### Vector: `GET /v1/vector`, `GET /v1/vector/data`, `POST /v1/vector`

One thing at a time between the computer and the phone: a text, a picture, a video or any
file, 100 MB at most. Each side keeps only the last one it was sent, and a new one takes
its place.

The computer's is what was pasted or dropped on the dashboard's Vector, or sent with
`nihil-deck vector send`. `GET /v1/vector` describes it, `{ "id": "" }` with none:

```json
{ "id": "5c1e9a07d3b2f468", "kind": "image", "name": "image.png", "mime": "image/png", "size": 48213, "time": 1794012345, "now": 1794012410 }
```

`kind` is `text`, `image`, `video` or `file`, and `time` when it came, by the computer's
clock (in seconds, as `now`, which the answer also has). With
`?since=<id>&wait=<seconds>` (50 at most) it answers when there is another than `since`, or
when the time is up: the phone keeps one open while it listens, and asks again with the id
it has. While one is open, and two minutes after, the phone counts as connected, and the
computer says it sent the thing to it.

`GET /v1/vector/data?id=<id>` gives the bytes, with their `Content-Type` and the name in
`Content-Disposition` (`filename*=UTF-8''…`); `404` `vector` when it is no longer that one.

`POST /v1/vector` gives the computer one: the bytes as the body, not JSON, with their
`Content-Type`, `Content-Length` and the name percent-encoded in `X-Vector-Name`
(`text.txt`, `image.png`… without one). It answers with what it kept, as `GET` does, and the
dashboard shows it, with a notification of where it came from. `413` `big` past 100 MB,
`400` `body` without one; the connection closes after it.

On the computer they are in `~/.cache/nihil/vector/`, `out/` and `in/`, each with its
`.item.json`, and the shell uses them through the command:

```bash
nihil-deck vector send [file]   # a file, or what the clipboard holds
nihil-deck vector copy          # the last one that came, onto the clipboard
nihil-deck vector status
```

### `POST /v1/caffeine`, `POST /v1/night`

Caffeine (the screen stays awake) and night light, as the quick settings turn them:

```json
{ "action": "toggle" }
```

`on`, `off` or `toggle`. It answers with whether it is on after:

```json
{ "on": true }
```

### `GET /v1/state`

What plays and the volume, for the deck to show (each `null` when there is none), and
whether caffeine and night light are on (left out when the shell doesn't say):

```json
{
  "media": { "title": "Song", "artist": "Someone", "player": "Spotify", "playing": true },
  "volume": { "level": 45, "muted": false },
  "caffeine": false,
  "night": true
}
```

### `POST /v1/unpair`

The phone forgets itself: its token stops working. `{ "ok": true }`.

## Errors

A status and `{ "error": "…" }`:

| Status | `error` | What to do |
|--------|---------|------------|
| 400 | `body`, `action`, `invalid` | A request it does not take |
| 401 | `unpaired` | The token is not known (forgotten in Preferences): drop it, offer to pair again |
| 403 | `wrong` | Not the code in the QR |
| 404 | `path`, `unknown`, `icon`, `vector` | No such path, app, icon or thing in Vector |
| 409 | `closed` | No code open: show the QR again |
| 410 | `expired` | The code ran out: show the QR again |
| 413 | `big` | More than Vector takes, 100 MB |
| 429 | `wait` | Ten failures (a token, a code) from that address in a minute: wait one |
| 503 | `shell`, `volume`, `lock`, `trackpad`, `vector` | The shell (or the sound, the lock, the trackpad, Vector) is not answering |
| 503 | `access` | This session may not make the trackpad yet: log out and in once |

## On the phone

- The token is a password: keep it encrypted (Android Keystore), never in logs.
- No pin, no request: a certificate that doesn't match is not the computer.
- A `401` means the computer forgot the phone: forget the token too.
- Several computers can be paired, each with its own name, pin and token.

## The cover

`GET /v1/state` gives what plays a `cover`: a token that changes with its cover (empty
without one); the address stays on the computer. `GET /v1/cover?c=<token>` answers with the
image while that token is still the current one (404 otherwise): a local file the player
names, or an image fetched from a public address, 4 MB at most.

## The kanban

The dashboard's kanban (`services/Tasks.qml`, `~/.local/state/nihil/tasks.json`, version 3)
and the phone's are replicas of the same board. Each card is
`{ id, text, column, textStamp, placeStamp, rank }`: the stamps say when its text and its
place were last set, in the computer's milliseconds, and its place is its column and its
`rank` there, the number a column is in order by. A card put somewhere gets a rank between
its neighbours' (one less than the first, one more than the last); when two are too close for
one between, the whole column gets new ranks, as if moved then. A side from before ranks
leaves `rank` out, and its cards count as ranked by when they got to their column
(`placeStamp`). A removed card leaves `removed: { id: when }`, kept 60 days. Two boards merge
(`services/TaskMerge.js`, the same rules as the launcher's `core/TaskBoard.kt`): for each card
the text set last and the place set last win, and a removal wins over everything set before
it. With the same stamp, a place with a rank wins over one without, so a side from before
ranks doesn't undo an order. The merge gives the same board whichever way round and however
often, so two sides that both changed while apart each keep what the other did.

- `GET /v1/tasks`: the board, and `now`, the computer's clock.
- `POST /v1/tasks` with the phone's whole board (256 KB, 1000 cards at most; a `rank`, when
  there is one, a finite number): the shell merges
  it in and answers with the result and `now`. The phone merges that again (for what changed
  meanwhile) and stamps its own changes in the computer's time from then on.

## The trackpad

`GET /v1/trackpad?w=<width>&h=<height>&r=<resolution>`, with `Connection: Upgrade` and
`Upgrade: nihil-trackpad`, makes a touchpad on the computer (uinput, `NIHIL deck trackpad`)
`w` by `h` units, `r` of them a millimetre: the phone's screen as it is. `r` from 5 to 100,
each side from 10 to 500 mm. The computer's libinput takes it as any touchpad, with the
settings the laptop's has: a tap clicks, two fingers right-click and scroll, three
middle-click, a pinch zooms, and Hyprland's gestures run.

It answers `101 Switching Protocols` a quarter of a second later (libinput opens the new
touchpad meanwhile), and the connection is then the phone's frames, big-endian:

| Bytes | What |
|-------|------|
| 1 | The kind: `1` the fingers, `2` a keepalive |
| 4 | The phone's time, in milliseconds (a clock that only goes forward; it may wrap) |
| 1 | The fingers: how many touch now, 10 at most (kind `1` only) |
| 5 each | A finger: its id (Android's pointer id), then x and y in units, two bytes each |

A frame names every finger that touches: one it leaves out is up, and with none, all are.
The computer answers each keepalive with one byte, `2`. The phone sends one every second,
frames or not, so each side knows the other is there: after 4 s without either, the
computer lifts every finger and the touchpad goes, as when the connection closes. A new
stream from the same phone ends the one before.

The frames reach the touchpad 25 ms after the quickest of them came, as far apart as the
phone saw them: libinput reads speed from those times, and takes frames the network bunched
together for jumps. One that comes later still goes at once, and the ones after it close up
to their time again.

`400` `invalid` for a size it doesn't take or another protocol, `503` `access` when this
session may not make the touchpad yet (once after turning the deck on, until logging in
again), `503` `trackpad` when it can't.

## The watch

A watch has no camera for the QR. [NIHIL for Wear OS](https://github.com/poligle/Nihil-Wear)
takes the same invitation from `nihil-deck pair --json`, handed to it by adb (its
`tools/watch invite`), and pairs with `POST /v1/pair` as the phone does: to this
computer it is one more device, listed and forgotten as a phone is. It reaches the
computer over the phone's Bluetooth when that gets here, over Wi-Fi asked for when it
doesn't.
