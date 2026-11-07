# The deck: the phone opens things on the computer

[NIHIL Launcher](https://github.com/poligle/Nihil-Launcher), on Android, can be a deck for a NIHIL computer: it opens the computer's
apps and web pages, plays and skips its music, turns its volume and locks it. This is what
the computer offers, for whoever writes the phone's side.

The computer's side is `nihil-deck` ([`home/deck/deck.py`](../home/deck/deck.py)), a
service in the user's session. Preferences, Phone turns it on (`settings.json`'s
`"deck": { "enable": true }`, a rebuild) and pairs phones with a QR.

It does only what is listed here. There is no way to run a command, read a file or type
on the computer: an app can only be one the launcher shows, and a page only `http` or
`https`.

## Pairing

Preferences, Phone, "Pair a phone" shows a QR with this URI:

```
nihil-deck://pair?v=1&name=thinkpad&hosts=192.168.1.20,100.64.0.7&port=64445&code=7JTX39F4&pin=8-eMVPli0fpzjeUBe-b_bmRtjDMwo1bNYXaVTyPSbVc
```

| Parameter | What it is |
|-----------|------------|
| `v`       | The protocol, `1` |
| `name`    | The computer's name (its host name) |
| `hosts`   | Its IPv4 addresses, comma-separated, the one with the default route first |
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

The computer shows a notification when a phone pairs, and lists it in Preferences, Phone,
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
most). Connections may be kept open; the computer closes them after 15 s idle.

Everything but `hello` and `pair` needs the token:

```
Authorization: Bearer <token>
```

### `GET /v1/hello`

No token. Whether it is there, and which computer.

```json
{ "deck": 1, "name": "thinkpad" }
```

### `POST /v1/pair`

No token.

```json
{ "code": "7JTX39F4", "device": "Galaxy A35" }
```

```json
{ "token": "…43 characters…", "device": "3f9a1c2e", "name": "thinkpad" }
```

`device` is the phone's id on the computer; the name it sent is cut at 40 characters.
`403` wrong code, `409` no code open (none shown, or used), `410` expired.

### `GET /v1/apps`

The apps the launcher shows, by name.

```json
{ "apps": [ { "id": "zen-beta", "name": "Zen" }, { "id": "kitty", "name": "kitty" } ] }
```

### `GET /v1/apps/{id}/icon`

The app's icon as PNG, 128 px (`Content-Type: image/png`), from the computer's icon
theme; `404` when it has none. `{id}` percent-encoded. They change rarely: keep them.

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

### `GET /v1/state`

What plays and the volume, for the deck to show (each `null` when there is none):

```json
{
  "media": { "title": "Song", "artist": "Someone", "player": "Spotify", "playing": true },
  "volume": { "level": 45, "muted": false }
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
| 404 | `path`, `unknown`, `icon` | No such path, app or icon |
| 409 | `closed` | No code open: show the QR again |
| 410 | `expired` | The code ran out: show the QR again |
| 429 | `wait` | Ten failures (a token, a code) from that address in a minute: wait one |
| 503 | `shell`, `volume`, `lock` | The shell (or the sound, or the lock) is not answering |

## On the phone

- The token is a password: keep it encrypted (Android Keystore), never in logs.
- No pin, no request: a certificate that doesn't match is not the computer.
- A `401` means the computer forgot the phone: forget the token too.
- Several computers can be paired, each with its own name, pin and token.
