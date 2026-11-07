pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// The phone as a deck (home/deck, docs/deck.md): the phones paired, and the
// QR that pairs one more, from the service's own command, nihil-deck. The
// service runs on its own; Preferences, Phone asks it while it is open.
// While the QR is out, who paired every two seconds: a phone that wasn't
// there before, and it goes; a new code before this one runs out, or as soon
// as it stops pairing some other way (five wrong codes, a suspend).
Singleton {
    id: root

    readonly property bool enabled: Config.deck.enabled
    property bool running: false
    property bool loaded: false
    property var devices: []

    property bool pairing: false
    property bool pairFailed: false
    property var rows: []           // the QR's modules: strings of 0 and 1
    property real expires: 0
    property var known: []          // ids of the phones when the QR came out
    property real opened: 0         // when it came out, ms

    function refresh(): void {
        if (root.enabled && !lister.running)
            lister.running = true;
    }

    function pair(): void {
        if (!root.enabled || pairer.running)
            return;
        if (!root.pairing)
            root.known = root.devices.map(device => device.id);
        root.pairFailed = false;
        pairer.running = true;
    }

    function cancel(): void {
        if (!root.pairing)
            return;
        root.pairing = false;
        root.rows = [];
        Quickshell.execDetached([Config.deck.command, "cancel"]);
    }

    function forget(id: string): void {
        if (forgetter.running)
            return;
        forgetter.target = id;
        forgetter.running = true;
    }

    Timer {
        running: root.pairing
        interval: 2000
        repeat: true
        onTriggered: {
            root.refresh();
            if (Date.now() / 1000 > root.expires - 20)
                root.pair();
        }
    }

    Process {
        id: lister
        command: [Config.deck.command, "devices", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const reply = JSON.parse(text);
                    const found = reply.devices ?? [];
                    if (root.pairing && found.some(device => root.known.indexOf(device.id) < 0)) {
                        root.pairing = false;
                        root.rows = [];
                    } else if (root.pairing && reply.pairing === false && Date.now() - root.opened > 3000) {
                        root.pair();
                    }
                    root.devices = found;
                    root.running = true;
                } catch (error) {
                    root.running = false;
                }
                root.loaded = true;
            }
        }
    }

    Process {
        id: pairer
        command: [Config.deck.command, "pair", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const found = JSON.parse(text);
                    if (!Array.isArray(found.qr) || found.qr.length === 0)
                        throw new Error(found.error ?? "no QR");
                    root.rows = found.qr;
                    root.expires = found.expires;
                    root.opened = Date.now();
                    root.pairing = true;
                    root.running = true;
                } catch (error) {
                    root.pairing = false;
                    root.rows = [];
                    root.pairFailed = true;
                }
            }
        }
    }

    Process {
        id: forgetter

        property string target: ""

        command: [Config.deck.command, "forget", target]
        onExited: root.refresh()
    }
}
