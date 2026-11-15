//@ pragma Env QT_QPA_PLATFORM=wayland
//@ pragma Env QSG_DISTANCEFIELD_ANTIALIASING=gray

import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme
import qs.config
import qs.components

ShellRoot {
    id: root

    readonly property string stateFile: Quickshell.env("NIHIL_INSTALLER_STATE") || "/tmp/nihil-installer.json"
    readonly property var pages: ["welcome", "network", "zone", "you", "disk", "lock", "summary", "install", "done"]
    readonly property string pageName: pages[page]
    readonly property var keyboards: [
        { value: "us", en: "English (US)", es: "Inglés (EE. UU.)" },
        { value: "es", en: "Spanish", es: "Español" },
        { value: "gb", en: "English (UK)", es: "Inglés (Reino Unido)" },
        { value: "de", en: "German", es: "Alemán" },
        { value: "fr", en: "French", es: "Francés" },
        { value: "it", en: "Italian", es: "Italiano" },
        { value: "pt", en: "Portuguese", es: "Portugués" },
        { value: "latam", en: "Latin American", es: "Latinoamericano" }
    ]
    readonly property var reservedNames: ["root", "nobody", "messagebus", "polkituser", "sshd", "nscd", "dhcpcd", "uuidd", "tss",
        "greeter", "avahi", "rtkit", "ollama", "geoclue", "colord", "fwupd-refresh", "nm-openvpn", "nm-iodine"]

    property int page: 0
    property string lang: "en"
    property string layout: "us"
    property string startLayout: "us"
    property bool layoutTouched: false
    property bool otherLayout: false
    property string layoutFilter: ""

    property string media: "checking"
    property bool online: false
    property bool checking: false
    property bool scanning: false
    property bool wifi: true
    property var networks: []
    property string ssid: ""
    property bool secure: false
    property string wifiPassword: ""
    property bool joining: false
    property string joinError: ""

    property string zone: ""
    property var zones: []
    property string zoneFilter: ""

    property string fullName: ""
    property string user: ""
    property bool userTyped: false
    property string password: ""
    property string password2: ""
    property string host: "nihil"

    property var machine: null
    property bool probing: false
    property string probedLang: ""
    property string wanted: ""
    property int diskIndex: -1
    property string mode: ""
    property int roomIndex: -1
    property real roomBytes: 0
    property string rootPart: ""
    property string bootPart: ""

    property bool encrypt: false
    property string passphrase: ""
    property string passphrase2: ""

    property var steps: []
    property string logLine: ""
    property string lastError: ""
    property string failure: ""
    property bool installing: false

    readonly property var disk: machine && diskIndex >= 0 && diskIndex < machine.disks.length ? machine.disks[diskIndex] : null
    readonly property var roomOptions: {
        const out = [];
        if (!disk)
            return out;
        for (const free of disk.room.free)
            out.push({ kind: "free", first: free.first, max: free.bytes, fstype: "",
                       title: tr("Its free space", "Su espacio libre"), detail: size(free.bytes) });
        for (const giver of disk.room.shrink)
            out.push({ kind: "shrink", part: giver.part, max: giver.give, fstype: giver.fstype,
                       title: tr("Room in ", "Sitio en ") + giver.part,
                       detail: [giver.fstype, giver.label].filter(word => word !== "").join(", ") + ", " + tr("up to ", "hasta ") + size(giver.give) });
        return out;
    }
    readonly property var room: roomIndex >= 0 && roomIndex < roomOptions.length ? roomOptions[roomIndex] : null
    readonly property var amounts: {
        const out = [];
        if (!room || !disk)
            return out;
        for (const gb of [30, 50, 100, 200, 500])
            if (gb * 1e9 >= disk.need && gb * 1e9 < room.max)
                out.push(gb * 1e9);
        out.push(room.max);
        return out;
    }
    readonly property var boots: disk ? disk.part.boots.filter(part => part.path !== rootPart) : []
    readonly property bool userValid: /^[a-z_][a-z0-9_-]{0,31}$/.test(user) && reservedNames.indexOf(user) < 0
        && !/^(nixbld|systemd-)/.test(user)
    readonly property bool hostValid: /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(host)
    readonly property var layoutMatches: {
        const find = plain(layoutFilter.trim());
        const out = [];
        for (const entry of Config.layouts) {
            if (find === "" ? entry.id === layout : entry.id.indexOf(find) === 0 || plain(entry.name).indexOf(find) >= 0)
                out.push(entry);
            if (out.length === 6)
                break;
        }
        return out;
    }
    readonly property var zoneMatches: {
        const find = plain(zoneFilter.trim()).replace(/ /g, "_");
        if (find === "")
            return zone !== "" ? [zone] : [];
        const out = [];
        for (const entry of zones) {
            if (entry.toLowerCase().indexOf(find) >= 0)
                out.push(entry);
            if (out.length === 8)
                break;
        }
        return out;
    }

    function tr(en: string, es: string): string { return lang === "es" ? es : en; }

    function size(bytes: real): string {
        if (bytes >= 1e12)
            return Math.round(bytes / 1e11) / 10 + " TB";
        if (bytes >= 1e9)
            return Math.round(bytes / 1e9) + " GB";
        return Math.round(bytes / 1e6) + " MB";
    }

    function plain(text: string): string {
        return text.toLowerCase().replace(/[áàâäã]/g, "a").replace(/[éèêë]/g, "e").replace(/[íìîï]/g, "i")
            .replace(/[óòôöõ]/g, "o").replace(/[úùûü]/g, "u").replace(/ñ/g, "n").replace(/ç/g, "c");
    }

    function fields(line: string): var {
        const out = [];
        let current = "";
        for (let i = 0; i < line.length; i++) {
            if (line[i] === "\\" && i + 1 < line.length) {
                current += line[++i];
            } else if (line[i] === ":") {
                out.push(current);
                current = "";
            } else {
                current += line[i];
            }
        }
        out.push(current);
        return out;
    }

    function keyboardName(id: string): string {
        const known = keyboards.find(entry => entry.value === id);
        if (known)
            return lang === "es" ? known.es : known.en;
        const listed = Config.layouts.find(entry => entry.id === id);
        return listed ? listed.name : id;
    }

    function describe(part: var): string {
        return [size(part.size), part.fstype, part.label].filter(word => word !== "").join(", ");
    }

    function consequence(): string {
        if (!disk)
            return "";
        if (mode === "whole")
            return tr("Everything on " + disk.path + " will be erased.", "Se borrará todo lo que hay en " + disk.path + ".");
        if (mode === "room" && room && room.kind === "shrink")
            return tr(room.part + " will give " + size(roomBytes) + " to NIHIL, keeping what it holds; the rest of " + disk.path
                      + " stays as it is. Shrinking is safe, but a power cut halfway is not: keep a copy of what matters on it.",
                      room.part + " cederá " + size(roomBytes) + " a NIHIL, conservando lo que guarda; el resto de " + disk.path
                      + " se queda como está. Encoger es seguro, pero un corte de luz a medias no: ten copia de lo importante.");
        if (mode === "room")
            return tr("NIHIL goes in " + size(roomBytes) + " of free space on " + disk.path + "; the rest stays as it is.",
                      "NIHIL va en " + size(roomBytes) + " de espacio libre de " + disk.path + "; el resto se queda como está.");
        const formatted = rootPart + (bootPart !== "" ? ", " + bootPart : "");
        return tr(formatted + " will be formatted; the rest of " + disk.path + " stays as it is.",
                  "Se formateará " + formatted + "; el resto de " + disk.path + " se queda como está.");
    }

    function ready(name: string): bool {
        switch (name) {
        case "network":
            return online;
        case "zone":
            return zone !== "" && (zones.length === 0 || zones.indexOf(zone) >= 0);
        case "you":
            return userValid && password !== "" && password === password2 && hostValid;
        case "disk":
            if (probing || !machine || !machine.uefi || !disk)
                return false;
            if (mode === "whole")
                return true;
            if (mode === "room")
                return room !== null && roomBytes >= disk.need && roomBytes <= room.max;
            if (mode === "part")
                return rootPart !== "" && (!disk.part.bootNeeded || bootPart !== "");
            return false;
        case "lock":
            return !encrypt || (passphrase !== "" && passphrase === passphrase2);
        case "summary":
            return media === "ok" && root.ready("disk");
        default:
            return true;
        }
    }

    function go(next: int): void {
        page = Math.max(0, Math.min(pages.length - 1, next));
        scroller.contentY = 0;
        appear.restart();
        if (pageName === "network")
            check();
        if (page > 0 && page < pages.indexOf("install") && !probing && (machine === null || probedLang !== lang))
            probe();
        if (pageName === "zone")
            Qt.callLater(() => zoneField.grab());
        if (pageName === "you")
            Qt.callLater(() => nameEntry.grab());
    }

    function forward(): void {
        if (!root.ready(pageName))
            return;
        if (pageName === "welcome" && layout !== startLayout) {
            leave({ next: "layout", page: 1, lang: lang, layout: layout, otherLayout: otherLayout, zone: zone,
                    fullName: fullName, user: user, userTyped: userTyped, host: host, encrypt: encrypt });
        } else if (pageName === "summary") {
            install();
        } else if (pageName === "done") {
            restarter.running = true;
        } else {
            go(page + 1);
        }
    }

    function leave(state: var): void {
        leaver.command = [Config.bash, "-c", "printf '%s' \"$1\" > \"$2\" && kill \"$PPID\"", "nihil-installer",
                          JSON.stringify(state), stateFile];
        leaver.running = true;
    }

    function restore(): void {
        let state = null;
        try {
            state = JSON.parse(saved.text());
        } catch (e) {
            return;
        }
        if (!state)
            return;
        layoutTouched = true;
        lang = state.lang === "es" ? "es" : "en";
        otherLayout = state.otherLayout === true;
        zone = state.zone ?? "";
        fullName = state.fullName ?? "";
        user = state.user ?? "";
        userTyped = state.userTyped === true;
        host = state.host ?? "nihil";
        encrypt = state.encrypt === true;
        if (state.page)
            go(state.page);
    }

    function pickLayout(value: string): void {
        layoutTouched = true;
        otherLayout = value === "other";
        if (!otherLayout)
            layout = value;
    }

    function check(): void {
        if (checking)
            return;
        checking = true;
        connectivity.running = true;
    }

    function scan(again: bool): void {
        if (scanning)
            return;
        scanning = true;
        wifiList.command = [Config.bash, "-c",
            "\"$1\" \"$2\" -t -f TYPE device; echo ---; \"$1\" \"$2\" -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan \"$3\"",
            "nihil-installer", Config.sudo, Config.nmcli, again ? "yes" : "auto"];
        wifiList.running = true;
    }

    function pickNetwork(net: var): void {
        ssid = net.ssid;
        secure = net.secure;
        wifiPassword = "";
        joinError = "";
        if (secure)
            Qt.callLater(() => wifiEntry.grab());
        else
            join();
    }

    function join(): void {
        if (ssid === "" || joining || (secure && wifiPassword === ""))
            return;
        joining = true;
        joinError = "";
        const command = [Config.sudo, Config.nmcli, "device", "wifi", "connect", ssid];
        if (secure)
            command.push("password", wifiPassword);
        joiner.command = command;
        joiner.running = true;
    }

    function probe(): void {
        if (disk)
            wanted = disk.path;
        probing = true;
        probedLang = lang;
        prober.command = [Config.sudo, Config.install, "probe", lang];
        prober.running = true;
    }

    function probed(text: string): void {
        probing = false;
        let result = null;
        try {
            result = JSON.parse(text);
        } catch (e) {}
        if (!result || !Array.isArray(result.disks)) {
            machine = { uefi: true, disks: [], failed: true };
            chooseDisk(-1);
            return;
        }
        machine = result;
        let index = result.disks.findIndex(entry => entry.path === wanted);
        if (index < 0 && result.disks.length === 1)
            index = 0;
        chooseDisk(index);
    }

    function chooseDisk(index: int): void {
        diskIndex = index;
        pickMode("");
    }

    function pickMode(name: string): void {
        mode = name;
        roomIndex = -1;
        roomBytes = 0;
        rootPart = "";
        bootPart = "";
        if (name === "room" && roomOptions.length === 1)
            pickRoom(0);
    }

    function pickRoom(index: int): void {
        roomIndex = index;
        if (amounts.length === 0) {
            roomBytes = 0;
        } else if (room.kind === "free") {
            roomBytes = amounts[amounts.length - 1];
        } else {
            const presets = amounts.slice(0, -1).filter(amount => amount <= 100e9);
            roomBytes = presets.length > 0 ? presets[presets.length - 1] : amounts[amounts.length - 1];
        }
    }

    function checkFilesystem(part: string): void {
        if (probing)
            return;
        if (disk)
            wanted = disk.path;
        probing = true;
        checker.command = [Config.sudo, Config.install, "check-filesystem", part];
        checker.running = true;
    }

    function nameEdited(text: string): void {
        fullName = text;
        if (!userTyped)
            user = plain(text.trim().split(/\s+/)[0]).replace(/[^a-z0-9_-]/g, "");
    }

    function answers(): var {
        const out = {
            language: lang, layout: layout, zone: zone, fullName: fullName, user: user, password: password, host: host,
            disk: disk.path, mode: mode, encrypt: encrypt, passphrase: encrypt ? passphrase : ""
        };
        if (mode === "room")
            out.room = room.kind === "free" ? { kind: "free", first: room.first, bytes: roomBytes }
                                            : { kind: "shrink", part: room.part, bytes: roomBytes };
        if (mode === "part") {
            out.root = rootPart;
            if (disk.part.bootNeeded)
                out.boot = bootPart;
        }
        return out;
    }

    function install(): void {
        steps = [];
        logLine = "";
        lastError = "";
        failure = "";
        installing = true;
        go(pages.indexOf("install"));
        installer.running = true;
    }

    function retry(): void {
        failure = "";
        machine = null;
        go(pages.indexOf("disk"));
    }

    function handle(line: string): void {
        let event = null;
        try {
            event = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (event.kind === "step")
            steps = steps.concat([event.text]);
        else if (event.kind === "log")
            logLine = event.text;
        else if (event.kind === "error")
            lastError = event.text;
    }

    onLangChanged: {
        if (!layoutTouched)
            layout = lang === "es" ? "es" : "us";
    }

    Component.onCompleted: {
        startLayout = Quickshell.env("XKB_DEFAULT_LAYOUT") || "us";
        layout = startLayout;
        restore();
        mediaCheck.running = true;
        zoneList.running = true;
    }

    component Option: Item {
        id: option

        property string title: ""
        property string detail: ""
        property bool chosen: false
        property bool active: true

        signal picked()

        width: parent ? parent.width : 0
        implicitHeight: 44
        opacity: active ? 1 : 0.4

        Surface {
            anchors.fill: parent
            radius: 10
            color: option.chosen || (area.containsMouse && option.active) ? Tokens.surface : "transparent"
            border.width: 1
            border.color: option.chosen ? Tokens.line : "transparent"
        }

        Rectangle {
            id: led
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: option.chosen ? Tokens.ink : Tokens.off

            Behavior on color { ColorAnimation { duration: Tokens.animFast } }
        }

        Txt {
            anchors.left: led.right
            anchors.leftMargin: 12
            anchors.right: info.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: option.title
            color: option.chosen ? Tokens.ink : Tokens.dim
        }

        Label {
            id: info
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, option.width * 0.55)
            horizontalAlignment: Text.AlignRight
            text: option.detail
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: option.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (option.active)
                    option.picked();
            }
        }
    }

    component Note: Item {
        id: note

        property string text: ""
        property bool alarm: false
        property bool lit: false
        property real pulse: 1
        property color tint: alarm || lit ? Tokens.ink : Tokens.dim

        width: parent ? parent.width : 0
        implicitHeight: words.implicitHeight

        Rectangle {
            y: 6
            width: 6
            height: 6
            radius: 3
            opacity: note.pulse
            color: note.alarm ? Tokens.interrupt : note.lit ? Tokens.ink : Tokens.muted
        }

        Txt {
            id: words
            x: 18
            width: note.width - 18
            text: note.text
            color: note.tint
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            verticalAlignment: Text.AlignTop
        }
    }

    component Entry: Column {
        id: entry

        property string label: ""
        property alias value: input.value
        property alias placeholder: input.placeholder
        property alias password: input.password
        property alias invalid: input.invalid

        signal edited(string text)
        signal accepted()

        function grab(): void { input.grab(); }

        width: parent ? parent.width : 0
        spacing: 8

        Label {
            text: entry.label
        }

        Field {
            id: input
            width: parent.width
            onEdited: text => entry.edited(text)
            onAccepted: entry.accepted()
        }
    }

    FileView {
        id: saved
        path: root.stateFile
        blockLoading: true
        printErrors: false
    }

    Process {
        id: leaver
    }

    Process {
        id: announce
        command: [Config.touch, Quickshell.env("NIHIL_INSTALLER_READY") || "/dev/null"]
    }

    Process {
        id: mediaCheck
        command: [Config.sudo, Config.install, "check-media"]
        onExited: code => root.media = code === 0 ? "ok" : "bad"
    }

    Process {
        id: connectivity
        command: [Config.curl, "-fsI", "--max-time", "6", "https://cache.nixos.org"]
        onExited: code => {
            root.checking = false;
            root.online = code === 0;
            if (root.online && root.zone === "")
                zoneGuess.running = true;
            if (!root.online && root.networks.length === 0)
                root.scan(false);
        }
    }

    Process {
        id: zoneGuess
        command: [Config.curl, "-fs", "--max-time", "6", "https://ipapi.co/timezone"]
        stdout: StdioCollector {
            onStreamFinished: {
                const guess = text.trim();
                if (root.zone === "" && /^[A-Za-z]+(\/[A-Za-z0-9_+-]+)+$/.test(guess))
                    root.zone = guess;
            }
        }
    }

    Process {
        id: zoneList
        command: [Config.timedatectl, "list-timezones"]
        stdout: StdioCollector {
            onStreamFinished: root.zones = text.split("\n").filter(entry => entry !== "")
        }
    }

    Process {
        id: wifiList
        stdout: StdioCollector {
            onStreamFinished: {
                root.scanning = false;
                const parts = text.split("---");
                root.wifi = parts[0].split("\n").indexOf("wifi") >= 0;
                const best = {};
                for (const line of (parts[1] ?? "").split("\n")) {
                    const f = root.fields(line);
                    if (f.length < 4 || f[3] === "")
                        continue;
                    const net = { ssid: f[3], signal: parseInt(f[1]) || 0, secure: f[2] !== "" && f[2] !== "--" };
                    if (!best[net.ssid] || best[net.ssid].signal < net.signal)
                        best[net.ssid] = net;
                }
                root.networks = Object.keys(best).map(name => best[name]).sort((a, b) => b.signal - a.signal).slice(0, 8);
            }
        }
    }

    Process {
        id: joiner
        stderr: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(line => line !== "");
                if (lines.length > 0)
                    root.joinError = lines[lines.length - 1].replace(/^Error: */, "");
            }
        }
        onExited: code => {
            root.joining = false;
            if (code === 0) {
                root.joinError = "";
                root.wifiPassword = "";
                root.check();
            } else if (root.joinError === "") {
                root.joinError = root.tr("It didn't connect.", "No se ha conectado.");
            }
        }
    }

    Process {
        id: prober
        stdout: StdioCollector {
            onStreamFinished: root.probed(text)
        }
    }

    Process {
        id: checker
        onExited: {
            root.probing = false;
            root.probe();
        }
    }

    Process {
        id: installer
        command: [Config.sudo, Config.install, "apply"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root.handle(data)
        }
        onStarted: installer.write(JSON.stringify(root.answers()) + "\n")
        onExited: code => {
            root.installing = false;
            if (code === 0)
                root.go(root.pages.indexOf("done"));
            else
                root.failure = root.lastError !== "" ? root.lastError : root.tr("The installation stopped here.", "La instalación se ha parado aquí.");
        }
    }

    Process {
        id: restarter
        command: [Config.sudo, Config.install, "finish"]
    }

    Timer {
        interval: 4000
        repeat: true
        running: root.pageName === "network" && !root.online && !root.joining
        onTriggered: root.check()
    }

    FloatingWindow {
        id: window

        title: "NIHIL"
        color: Tokens.black
        fullscreen: true
        visible: true

        Component.onCompleted: announce.running = true

        Canvas {
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = String(Tokens.raised);
                for (let y = 4.5; y < height; y += 9) {
                    ctx.beginPath();
                    for (let x = 4.5; x < width; x += 9) {
                        ctx.moveTo(x + 1.15, y);
                        ctx.arc(x, y, 1.15, 0, 2 * Math.PI);
                    }
                    ctx.fill();
                }
            }
        }

        Item {
            id: panel

            anchors.centerIn: parent
            width: Math.min(720, parent.width - 48)
            height: Math.min(660, parent.height - 48)

            Rectangle {
                anchors.fill: parent
                radius: Tokens.drawerRadius
                color: Tokens.black
            }

            DotText {
                id: mark
                x: 40
                y: 30
                text: "NIHIL"
                font.pixelSize: 22
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 40
                anchors.verticalCenter: mark.verticalCenter
                spacing: 7

                Repeater {
                    model: 7

                    Rectangle {
                        required property int index

                        width: 6
                        height: 6
                        radius: 3
                        color: index <= root.page ? Tokens.ink : Tokens.off

                        Behavior on color { ColorAnimation { duration: Tokens.animNormal } }
                    }
                }
            }

            Flickable {
                id: scroller

                anchors.fill: parent
                anchors.topMargin: 96
                anchors.bottomMargin: 100
                anchors.leftMargin: 40
                anchors.rightMargin: 40
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: body

                    width: scroller.width
                    spacing: 16

                    Column {
                        width: parent.width
                        spacing: 28
                        visible: root.pageName === "welcome"

                        DotText {
                            text: root.tr("Install NIHIL", "Instalar NIHIL")
                            font.pixelSize: 34
                        }

                        Column {
                            width: parent.width
                            spacing: 8

                            Label {
                                text: root.tr("Language", "Idioma")
                            }

                            Choice {
                                width: parent.width
                                options: [{ label: "English", value: "en" }, { label: "Español", value: "es" }]
                                value: root.lang
                                onPicked: value => root.lang = value
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 8

                            Label {
                                text: root.tr("Keyboard", "Teclado")
                            }

                            Choice {
                                width: parent.width
                                options: root.keyboards.map(entry => ({ label: root.lang === "es" ? entry.es : entry.en, value: entry.value }))
                                    .concat(Config.layouts.length > 0 ? [{ label: root.tr("Other", "Otro"), value: "other" }] : [])
                                value: root.otherLayout ? "other" : root.layout
                                onPicked: value => root.pickLayout(value)
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 6
                            visible: root.otherLayout

                            Field {
                                width: parent.width
                                placeholder: root.tr("Search", "Buscar")
                                onEdited: text => root.layoutFilter = text
                            }

                            Repeater {
                                model: root.layoutMatches

                                Option {
                                    required property var modelData

                                    title: modelData.name
                                    detail: modelData.id
                                    chosen: root.layout === modelData.id
                                    onPicked: root.layout = modelData.id
                                }
                            }
                        }

                        Note {
                            visible: root.media === "bad"
                            alarm: true
                            text: root.tr("The USB stick can't be read whole. Write the image again, checking its SHA256, or try another stick or port.",
                                          "No se puede leer el USB entero. Vuelve a grabar la imagen comprobando su SHA256, o prueba otro USB u otro puerto.")
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 16
                        visible: root.pageName === "network"

                        DotText {
                            text: root.tr("Network", "Red")
                            font.pixelSize: 34
                        }

                        Note {
                            visible: root.online
                            lit: true
                            text: root.tr("Connected.", "Conectado.")
                        }

                        Txt {
                            width: parent.width
                            visible: !root.online
                            text: root.tr("NIHIL installs from the internet.", "NIHIL se instala desde internet.")
                            color: Tokens.dim
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                        }

                        Note {
                            visible: !root.online && !root.wifi
                            text: root.tr("No Wi-Fi card shows up. A cable, or a phone sharing its connection over USB, work too.",
                                          "No aparece ninguna tarjeta Wi-Fi. Un cable, o un móvil compartiendo su conexión por USB, también sirven.")
                        }

                        Column {
                            width: parent.width
                            spacing: 4
                            visible: !root.online && root.wifi

                            Repeater {
                                model: root.networks

                                Option {
                                    required property var modelData

                                    title: modelData.ssid
                                    detail: modelData.signal + "%"
                                    chosen: root.ssid === modelData.ssid
                                    onPicked: root.pickNetwork(modelData)
                                }
                            }
                        }

                        Entry {
                            id: wifiEntry
                            visible: !root.online && root.ssid !== "" && root.secure
                            label: root.tr("Password of ", "Contraseña de ") + root.ssid
                            password: true
                            value: root.wifiPassword
                            onEdited: text => root.wifiPassword = text
                            onAccepted: root.join()
                        }

                        Note {
                            visible: !root.online && root.joinError !== ""
                            alarm: true
                            text: root.joinError
                        }

                        Row {
                            visible: !root.online
                            spacing: 10

                            KeyButton {
                                visible: root.ssid !== ""
                                height: 36
                                accent: true
                                enabled: !root.joining && (!root.secure || root.wifiPassword !== "")
                                opacity: enabled ? 1 : 0.35
                                text: root.joining ? root.tr("Connecting…", "Conectando…") : root.tr("Connect", "Conectar")
                                onClicked: root.join()
                            }

                            KeyButton {
                                height: 36
                                enabled: !root.scanning
                                opacity: enabled ? 1 : 0.35
                                text: root.scanning ? root.tr("Looking…", "Buscando…") : root.tr("Look again", "Buscar otra vez")
                                onClicked: {
                                    root.scan(true);
                                    root.check();
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 16
                        visible: root.pageName === "zone"

                        DotText {
                            text: root.tr("Time zone", "Zona horaria")
                            font.pixelSize: 34
                        }

                        Field {
                            id: zoneField
                            width: parent.width
                            placeholder: root.tr("Your city", "Tu ciudad")
                            onEdited: text => root.zoneFilter = text
                            onAccepted: {
                                if (root.zoneMatches.length > 0 && root.zone !== root.zoneMatches[0])
                                    root.zone = root.zoneMatches[0];
                                else
                                    root.forward();
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 4

                            Repeater {
                                model: root.zoneMatches

                                Option {
                                    required property var modelData

                                    title: modelData.split("/").pop().replace(/_/g, " ")
                                    detail: modelData
                                    chosen: root.zone === modelData
                                    onPicked: root.zone = modelData
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 14
                        visible: root.pageName === "you"

                        DotText {
                            text: root.tr("You", "Tú")
                            font.pixelSize: 34
                        }

                        Entry {
                            id: nameEntry
                            label: root.tr("Your name", "Tu nombre")
                            placeholder: "Ada Lovelace"
                            value: root.fullName
                            onEdited: text => root.nameEdited(text)
                        }

                        Entry {
                            label: root.tr("User name", "Nombre de usuario")
                            value: root.user
                            invalid: root.user !== "" && !root.userValid
                            onEdited: text => {
                                root.user = text;
                                root.userTyped = true;
                            }
                        }

                        Note {
                            visible: root.user !== "" && !root.userValid
                            alarm: true
                            text: root.tr("Lowercase letters and digits, starting with a letter.", "Minúsculas y cifras, empezando por una letra.")
                        }

                        Entry {
                            label: root.tr("Password", "Contraseña")
                            password: true
                            value: root.password
                            onEdited: text => root.password = text
                        }

                        Entry {
                            label: root.tr("Password, again", "La contraseña, otra vez")
                            password: true
                            value: root.password2
                            invalid: root.password2 !== "" && root.password2 !== root.password
                            onEdited: text => root.password2 = text
                        }

                        Entry {
                            label: root.tr("Name of this computer", "Nombre de este ordenador")
                            value: root.host
                            invalid: !root.hostValid
                            onEdited: text => root.host = text
                            onAccepted: root.forward()
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 14
                        visible: root.pageName === "disk"

                        DotText {
                            text: root.tr("Where", "Dónde")
                            font.pixelSize: 34
                        }

                        Txt {
                            visible: root.probing
                            text: root.tr("Looking at the disks…", "Mirando los discos…")
                            color: Tokens.dim
                        }

                        Note {
                            visible: !root.probing && root.machine !== null && !root.machine.uefi
                            alarm: true
                            text: root.tr("NIHIL boots with systemd-boot, which needs UEFI: this machine started in legacy BIOS mode.",
                                          "NIHIL arranca con systemd-boot, que necesita UEFI: este ordenador ha arrancado en modo BIOS antiguo.")
                        }

                        Note {
                            visible: !root.probing && root.machine !== null && root.machine.disks.length === 0
                            alarm: true
                            text: root.machine && root.machine.failed ? root.tr("The disks couldn't be read.", "No se han podido leer los discos.")
                                : root.tr("There is no disk of 20 GB or more to install on.", "No hay ningún disco de 20 GB o más donde instalar.")
                        }

                        Column {
                            width: parent.width
                            spacing: 4
                            visible: !root.probing

                            Repeater {
                                model: root.machine ? root.machine.disks : []

                                Option {
                                    required property var modelData
                                    required property int index

                                    title: modelData.model !== "" ? modelData.model : modelData.path
                                    detail: [modelData.path, root.size(modelData.size)].concat(modelData.windows ? ["Windows"] : []).join(", ")
                                    chosen: root.diskIndex === index
                                    onPicked: {
                                        if (root.diskIndex !== index)
                                            root.chooseDisk(index);
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 4
                            visible: !root.probing && root.disk !== null

                            Label {
                                text: root.disk ? root.disk.path : ""
                                topPadding: 8
                                bottomPadding: 6
                            }

                            Option {
                                title: root.tr("Next to what is on it", "Junto a lo que hay")
                                detail: root.tr("make room", "hacer sitio")
                                active: root.roomOptions.length > 0
                                chosen: root.mode === "room"
                                onPicked: {
                                    if (root.mode !== "room")
                                        root.pickMode("room");
                                }
                            }

                            Option {
                                title: root.tr("Erase the whole disk", "Borrar el disco entero")
                                chosen: root.mode === "whole"
                                onPicked: {
                                    if (root.mode !== "whole")
                                        root.pickMode("whole");
                                }
                            }

                            Option {
                                title: root.tr("On one of its partitions", "En una de sus particiones")
                                detail: root.tr("formatting it", "formateándola")
                                active: root.disk !== null && root.disk.part.roots.length > 0
                                chosen: root.mode === "part"
                                onPicked: {
                                    if (root.mode !== "part")
                                        root.pickMode("part");
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 4
                            visible: !root.probing && root.mode === "room"

                            Repeater {
                                model: root.roomOptions

                                Option {
                                    required property var modelData
                                    required property int index

                                    title: modelData.title
                                    detail: modelData.detail
                                    chosen: root.roomIndex === index
                                    onPicked: {
                                        if (root.roomIndex !== index)
                                            root.pickRoom(index);
                                    }
                                }
                            }

                            Label {
                                visible: root.room !== null
                                text: root.tr("Room for NIHIL", "Espacio para NIHIL")
                                topPadding: 10
                                bottomPadding: 6
                            }

                            Choice {
                                visible: root.room !== null
                                width: parent.width
                                options: root.room ? root.amounts.map(amount => ({
                                    label: amount === root.room.max ? root.tr("All of it, ", "Todo, ") + root.size(amount) : root.size(amount),
                                    value: amount
                                })) : []
                                value: root.roomBytes
                                onPicked: value => root.roomBytes = value
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 4
                            visible: !root.probing && root.mode === "part"

                            Label {
                                text: root.tr("NIHIL goes on (it will be formatted)", "NIHIL va en (se formateará)")
                                topPadding: 8
                                bottomPadding: 6
                            }

                            Repeater {
                                model: root.disk ? root.disk.part.roots : []

                                Option {
                                    required property var modelData

                                    title: modelData.path
                                    detail: root.describe(modelData)
                                    chosen: root.rootPart === modelData.path
                                    onPicked: {
                                        root.rootPart = modelData.path;
                                        if (root.bootPart === modelData.path)
                                            root.bootPart = "";
                                    }
                                }
                            }

                            Label {
                                visible: root.disk !== null && root.disk.part.bootNeeded
                                text: root.tr("Boot partition (it will be formatted)", "Partición de arranque (se formateará)")
                                topPadding: 10
                                bottomPadding: 6
                            }

                            Repeater {
                                model: root.disk && root.disk.part.bootNeeded ? root.boots : []

                                Option {
                                    required property var modelData

                                    title: modelData.path
                                    detail: root.describe(modelData)
                                    chosen: root.bootPart === modelData.path
                                    onPicked: root.bootPart = modelData.path
                                }
                            }

                            Note {
                                visible: root.disk !== null && root.disk.part.bootNeeded && root.boots.length === 0
                                alarm: true
                                text: root.tr("NIHIL also needs a partition of 1 GB for booting: make room for NIHIL instead.",
                                              "NIHIL necesita también una partición de 1 GB para arrancar: haz sitio para NIHIL.")
                            }

                            Item {
                                width: 1
                                height: 8
                            }

                            Note {
                                text: root.tr("To partition it by hand, Ctrl+Alt+F2 opens a console with cfdisk and parted.",
                                              "Para particionarlo a mano, Ctrl+Alt+F2 abre una consola con cfdisk y parted.")
                            }
                        }

                        Repeater {
                            model: !root.probing && root.disk ? root.disk.notes : []

                            Note {
                                required property var modelData

                                text: modelData
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 10

                            Repeater {
                                model: !root.probing && root.disk ? root.disk.room.unchecked : []

                                KeyButton {
                                    required property var modelData

                                    height: 36
                                    text: root.tr("Check ", "Revisar ") + modelData
                                    onClicked: Qt.callLater(root.checkFilesystem, modelData)
                                }
                            }

                            KeyButton {
                                visible: !root.probing
                                height: 36
                                text: root.tr("Look again", "Mirar otra vez")
                                onClicked: root.probe()
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 14
                        visible: root.pageName === "lock"

                        DotText {
                            text: root.tr("Encryption", "Cifrado")
                            font.pixelSize: 34
                        }

                        Column {
                            width: parent.width
                            spacing: 4

                            Option {
                                title: root.tr("Don't encrypt", "No cifrar")
                                chosen: !root.encrypt
                                onPicked: root.encrypt = false
                            }

                            Option {
                                title: root.tr("Encrypt the disk", "Cifrar el disco")
                                detail: root.tr("a passphrase at every boot", "contraseña en cada arranque")
                                chosen: root.encrypt
                                onPicked: root.encrypt = true
                            }
                        }

                        Entry {
                            visible: root.encrypt
                            label: root.tr("Disk passphrase", "Contraseña del disco")
                            password: true
                            value: root.passphrase
                            onEdited: text => root.passphrase = text
                        }

                        Entry {
                            visible: root.encrypt
                            label: root.tr("Disk passphrase, again", "La contraseña del disco, otra vez")
                            password: true
                            value: root.passphrase2
                            invalid: root.passphrase2 !== "" && root.passphrase2 !== root.passphrase
                            onEdited: text => root.passphrase2 = text
                            onAccepted: root.forward()
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 14
                        visible: root.pageName === "summary"

                        DotText {
                            text: root.tr("Ready", "Listo")
                            font.pixelSize: 34
                        }

                        Column {
                            width: parent.width
                            spacing: 10

                            Repeater {
                                model: [
                                    [root.tr("Language", "Idioma"), root.lang === "es" ? "Español" : "English"],
                                    [root.tr("Keyboard", "Teclado"), root.keyboardName(root.layout)],
                                    [root.tr("Time zone", "Zona horaria"), root.zone],
                                    [root.tr("User", "Usuario"), root.fullName !== "" ? root.user + ", " + root.fullName : root.user],
                                    [root.tr("Computer", "Ordenador"), root.host],
                                    [root.tr("Disk", "Disco"), root.disk ? root.disk.path : ""],
                                    [root.tr("Encryption", "Cifrado"), root.encrypt ? root.tr("Yes", "Sí") : root.tr("No", "No")]
                                ]

                                Item {
                                    required property var modelData

                                    width: body.width
                                    height: 22

                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 160
                                        text: modelData[0]
                                    }

                                    Txt {
                                        x: 160
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 160
                                        text: modelData[1]
                                    }
                                }
                            }
                        }

                        Item {
                            width: 1
                            height: 4
                        }

                        Note {
                            alarm: true
                            text: root.consequence()
                        }

                        Note {
                            visible: root.mode === "room" && root.room !== null && root.room.fstype === "ntfs"
                            text: root.tr("Windows will check its disk the first time it starts: let it finish.",
                                          "Windows revisará su disco la primera vez que arranque: déjale terminar.")
                        }

                        Note {
                            visible: root.disk !== null && root.disk.windows && root.mode !== "whole"
                            text: root.tr("The boot menu will offer Windows too. If Windows uses BitLocker, it may ask for its recovery key the first time: keep it at hand.",
                                          "El menú de arranque ofrecerá también Windows. Si Windows usa BitLocker, puede pedir su clave de recuperación la primera vez: tenla a mano.")
                        }

                        Note {
                            visible: root.disk !== null && (root.disk.elsewhere ?? "") !== "" && !(root.disk.windows && root.mode !== "whole")
                            text: root.disk ? root.tr("Windows, on " + root.disk.elsewhere + ", stays in the computer's own boot menu (the key it shows as it starts: F12, F11, Esc…).",
                                                      "Windows, en " + root.disk.elsewhere + ", sigue en el menú de arranque del propio ordenador (la tecla que indica al encenderse: F12, F11, Esc…).") : ""
                        }

                        Note {
                            visible: root.media === "checking"
                            text: root.tr("Checking the USB stick…", "Comprobando el USB…")
                        }

                        Note {
                            visible: root.media === "bad"
                            alarm: true
                            text: root.tr("The USB stick can't be read whole: write the image again.", "No se puede leer el USB entero: vuelve a grabar la imagen.")
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 12
                        visible: root.pageName === "install"

                        DotText {
                            text: root.failure !== "" ? root.tr("Stopped", "Parado") : root.tr("Installing", "Instalando")
                            font.pixelSize: 34
                        }

                        Repeater {
                            model: root.steps

                            Note {
                                required property var modelData
                                required property int index
                                readonly property bool current: index === root.steps.length - 1 && root.installing

                                lit: true
                                pulse: current ? glow.value : 1
                                tint: current ? Tokens.ink : Tokens.dim
                                text: modelData
                            }
                        }

                        Label {
                            width: parent.width
                            visible: root.installing && root.logLine !== ""
                            leftPadding: 18
                            text: root.logLine
                            elide: Text.ElideMiddle
                        }

                        Note {
                            visible: root.failure !== ""
                            alarm: true
                            text: root.failure + " " + root.tr("The whole log is in /tmp/nihil-install.log.", "El registro entero está en /tmp/nihil-install.log.")
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 16
                        visible: root.pageName === "done"

                        DotText {
                            text: root.tr("NIHIL is installed", "NIHIL está instalado")
                            font.pixelSize: 34
                        }

                        Txt {
                            width: parent.width
                            text: root.tr("Take the USB stick out as it restarts.", "Quita el USB mientras se reinicia.")
                            color: Tokens.dim
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                        }
                    }
                }
            }

            Label {
                anchors.left: parent.left
                anchors.leftMargin: 40
                anchors.verticalCenter: keys.verticalCenter
                visible: root.pageName === "welcome"
                text: "ex nihilo"
                color: Tokens.off
                font.italic: true
                font.pixelSize: 12
            }

            Row {
                id: keys

                anchors.right: parent.right
                anchors.rightMargin: 40
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 36
                spacing: 10

                KeyButton {
                    visible: root.pageName === "install" && root.failure !== ""
                    height: 36
                    text: root.tr("Text installer", "Instalador de texto")
                    onClicked: root.leave({ next: "text" })
                }

                KeyButton {
                    visible: root.pageName === "install" && root.failure !== ""
                    height: 36
                    accent: true
                    text: root.tr("Try again", "Probar otra vez")
                    onClicked: root.retry()
                }

                KeyButton {
                    visible: root.page > 0 && root.page < root.pages.indexOf("install")
                    height: 36
                    text: root.tr("Back", "Atrás")
                    onClicked: root.go(root.page - 1)
                }

                KeyButton {
                    visible: root.pageName !== "install"
                    height: 36
                    accent: true
                    enabled: root.ready(root.pageName)
                    opacity: enabled ? 1 : 0.35
                    text: root.pageName === "summary" ? root.tr("Install", "Instalar")
                        : root.pageName === "done" ? root.tr("Restart", "Reiniciar")
                        : root.tr("Continue", "Continuar")
                    onClicked: root.forward()
                }
            }

            NumberAnimation {
                id: appear
                target: body
                property: "opacity"
                from: 0
                to: 1
                duration: Tokens.animNormal
                easing.type: Easing.OutCubic
            }
        }

        QtObject {
            id: glow

            property real value: 1
        }

        SequentialAnimation {
            running: root.installing
            loops: Animation.Infinite

            NumberAnimation { target: glow; property: "value"; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { target: glow; property: "value"; to: 1; duration: 700; easing.type: Easing.InOutSine }
        }
    }
}
