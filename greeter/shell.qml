//@ pragma Env QT_QPA_PLATFORM=wayland
//@ pragma Env QSG_DISTANCEFIELD_ANTIALIASING=gray

// The faces, one per screen, reach the greeter's own state by id.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import qs.theme
import qs.config
import qs.components
import "Auth.js" as Auth

ShellRoot {
    id: root

    property int user: 0
    readonly property var person: Config.users[user] ?? { name: "", greeting: "" }

    property bool asking: false
    property bool echo: false
    property bool sent: false
    property string waiting: ""
    property string note: ""
    property bool wrong: false
    property int attempts: 0
    // What PAM said went wrong in this try, for when greetd says only that it failed.
    property string told: ""
    property bool going: false

    readonly property string skipFile: (Quickshell.env("XDG_RUNTIME_DIR") ?? "") + "/nihil-greeter-password"

    // Every screen is on (cage -m extend) and the window spans them all: the greeter shows on each,
    // so it's where one looks, whichever is off or shut (a laptop closed with a screen plugged in
    // is still a screen to cage). One field takes the keys and every face shows it, each over its
    // screen's own wallpaper. With one screen, or a layout that doesn't add up, one face fills
    // the window.
    readonly property var faces: {
        const screens = Quickshell.screens;
        const only = screens.length === 1 ? screens[0].name : Config.primaryOutput;
        const full = [{ rect: Qt.rect(0, 0, window.width, window.height), name: only }];
        if (screens.length < 2)
            return full;
        let left = Infinity;
        let top = Infinity;
        for (let i = 0; i < screens.length; i++) {
            left = Math.min(left, screens[i].x);
            top = Math.min(top, screens[i].y);
        }
        const out = [];
        for (let i = 0; i < screens.length; i++) {
            const r = Qt.rect(screens[i].x - left, screens[i].y - top, screens[i].width, screens[i].height);
            if (!(r.width > 0 && r.height > 0 && r.x >= 0 && r.y >= 0
                  && r.x + r.width <= window.width + 1 && r.y + r.height <= window.height + 1))
                return full;
            out.push({ rect: r, name: screens[i].name });
        }
        return out;
    }

    // The faces fade in, and out on the way to the session.
    property real shown: 0

    Behavior on shown { NumberAnimation { duration: Tokens.animSlow; easing.type: Easing.OutCubic } }

    function start(): void {
        asking = false;
        echo = false;
        sent = false;
        told = "";
        if (Greetd.available && person.name !== "")
            Greetd.createSession(person.name);
    }

    function submit(text: string): void {
        if (text === "" || going || sent)
            return;
        if (asking) {
            asking = false;
            sent = true;
            Greetd.respond(text);
            return;
        }
        waiting = text;
        if (!skip.running)
            skip.running = true;
    }

    // If launching fails, the faces come back instead of staying dark with the field off.
    function back(): void {
        leave.stop();
        root.going = false;
        root.shown = 1;
    }

    function other(): void {
        if (Config.users.length < 2 || going)
            return;
        user = (user + 1) % Config.users.length;
        waiting = "";
        note = "";
        wrong = false;
        input.text = "";
        Greetd.cancelSession();
        start();
    }

    // What PAM, fprintd and greetd say, in NIHIL's words and the greeter's language: what's known
    // by what it is, any other failure as a failure, and nothing else (Auth.js).
    function said(text: string, failed: bool): string {
        return root.words(Auth.kind(text) || (failed ? "authFailed" : ""));
    }

    function words(kind: string): string {
        return kind === "" ? "" : String(Lang[kind]).replace("$ATTEMPTS", String(root.attempts));
    }

    function dateText(date: var): string {
        const map = { "%a": "ddd", "%A": "dddd", "%d": "dd", "%e": "d", "%-d": "d", "%b": "MMM", "%B": "MMMM",
                      "%m": "MM", "%Y": "yyyy", "%y": "yy" };
        const format = String(Lang.lockDate).replace(/%-?[a-zA-Z]/g, code => map[code] ?? "");
        const text = date.toLocaleString(Qt.locale(Lang.locale), format).replace(/\./g, "");
        return text.length > 0 ? text.charAt(0).toLocaleUpperCase() + text.slice(1) : text;
    }

    Connections {
        target: Greetd

        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            if (responseRequired) {
                root.echo = echoResponse;
                // A password asked for again keeps what the last try said, a failure most of all.
                root.note = echoResponse ? root.said(message, false) : root.wrong ? root.note : "";
                if (!echoResponse && root.waiting !== "") {
                    const text = root.waiting;
                    root.waiting = "";
                    root.sent = true;
                    Greetd.respond(text);
                    return;
                }
                root.sent = false;
                root.asking = true;
                return;
            }
            root.told = Auth.told(message, error, root.told);
            root.note = root.words(Auth.fingerprint(message, error)) || root.said(message, error);
            root.wrong = error;
        }

        function onAuthFailure(message: string): void {
            root.back();
            root.attempts += 1;
            root.wrong = true;
            root.note = root.words(Auth.failure(message, root.told));
            root.told = "";
            root.waiting = "";
            root.asking = false;
            root.sent = false;
            input.text = "";
            again.restart();
        }

        function onReadyToLaunch(): void {
            root.going = true;
            leave.start();
        }

        function onError(error: string): void {
            root.back();
            root.wrong = true;
            root.note = root.said(error, true);
            retry.restart();
        }
    }

    Process {
        id: skip
        command: [Config.touch, root.skipFile]
        onExited: {
            Greetd.cancelSession();
            root.start();
        }
    }

    Process {
        id: ready
        command: [Config.touch, Quickshell.env("NIHIL_GREETER_READY") || "/dev/null"]
    }

    Timer {
        id: again
        interval: 300
        onTriggered: root.start()
    }

    Timer {
        id: retry
        interval: 2000
        onTriggered: root.start()
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    FloatingWindow {
        id: window

        title: "NIHIL"
        color: Tokens.black
        fullscreen: true
        visible: true

        Component.onCompleted: {
            if (Greetd.available)
                ready.running = true;
            root.start();
            root.shown = 1;
            input.forceActiveFocus();
        }

        // What's typed, for every face: kept out of sight, the one thing that takes the keys.
        TextInput {
            id: input
            width: 1
            height: 1
            opacity: 0
            echoMode: root.echo ? TextInput.Normal : TextInput.Password
            enabled: !root.going
            onTextEdited: root.wrong = false
            onAccepted: root.submit(text)
            Keys.onEscapePressed: text = ""
        }

        FileView {
            id: glassFlag
            path: Config.glass
            blockLoading: true
        }

        Repeater {
            model: root.faces

            Item {
                id: face

                required property var modelData

                x: face.modelData.rect.x
                y: face.modelData.rect.y
                width: face.modelData.rect.width
                height: face.modelData.rect.height
                opacity: root.shown

                property Item glassBackdrop: glassFlag.text().trim() === "on" && wall.status === Image.Ready ? glassSource : null

                // The screen's own render, dot for dot as the desktop shows it; for a screen
                // nihil.outputs doesn't have, the primary's.
                Image {
                    id: wall
                    property bool own: true
                    anchors.fill: parent
                    source: "file://" + (own ? Config.wallpapers + "/" + face.modelData.name + ".png" : Config.wallpaper)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    mipmap: true
                    opacity: 0.55
                    onStatusChanged: {
                        if (status === Image.Error)
                            own = false;
                    }
                }

                // Under the column of text, the wallpaper darker: a dot behind a small letter
                // would take it. The lock screen has it in its pictures (home/lock/glass.py).
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 560
                    height: parent.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.2; color: Qt.rgba(0, 0, 0, 0.7) }
                        GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, 0.7) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }

                Item {
                    id: glassSource
                    readonly property Item texture: wall
                    // The wallpaper covers this face's screen: from the window's corner to its own.
                    readonly property vector2d origin: Qt.vector2d(-face.x, -face.y)
                    readonly property vector2d screenSize: Qt.vector2d(face.width, face.height)
                    readonly property real dim: 0.55
                }

                Txt {
                    id: time
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 - 170 - height / 2
                    text: Qt.formatTime(clock.date, "HH:mm")
                    font.family: Tokens.fontDot
                    font.weight: Font.Bold
                    font.pixelSize: 160
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 - 72 - height / 2
                    text: root.dateText(clock.date)
                    color: Tokens.dim
                    font.pixelSize: 16
                }

                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 - height / 2
                    text: root.person.greeting !== "" ? Lang.welHello.arg(root.person.greeting) : Lang.welHelloAnon
                    font.pixelSize: 17
                }

                Surface {
                    id: field

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 + 56 - height / 2
                    width: 280
                    height: 46
                    radius: height / 2
                    color: Tokens.black
                    border.width: 1
                    property color borderTint: root.wrong ? Tokens.interrupt : root.sent || root.waiting !== "" ? Tokens.muted : Tokens.line
                    border.color: borderTint

                    Behavior on borderTint { ColorAnimation { duration: Tokens.animFast } }

                    // What a prompt that may be seen asks for, as typed.
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        visible: root.echo
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideLeft
                        text: input.text
                        color: Tokens.ink
                        font.family: Tokens.fontMono
                        font.pixelSize: 14
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 7
                        visible: !root.echo

                        Repeater {
                            model: Math.min(input.text.length, 15)

                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                color: Tokens.ink
                            }
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: input.text.length === 0
                        text: Lang.password
                        font.pixelSize: 13
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        onClicked: input.forceActiveFocus()
                    }
                }

                Alert {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 + 110 - height / 2
                    text: root.note
                    wrong: root.wrong && root.note !== ""
                    font.pixelSize: 12
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 + 140 - height / 2
                    visible: Config.users.length > 1
                    text: root.person.name
                    color: nextUser.containsMouse ? Tokens.ink : Tokens.dim
                    font.pixelSize: 12

                    MouseArea {
                        id: nextUser
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.other()
                    }
                }

                // The words 36 px from the corner, as ever, with room around them for the ring.
                Row {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 24
                    anchors.bottomMargin: 30
                    spacing: 16

                    Repeater {
                        model: [
                            { label: Lang.actReboot, command: Config.reboot },
                            { label: Lang.actPowerOff, command: Config.powerOff }
                        ]

                        // A second click within 3 s does it: one by chance doesn't turn the computer
                        // off. Armed, it's ringed in red; as wide at rest as armed, so arming one
                        // doesn't move the other.
                        Item {
                            id: action

                            required property var modelData
                            property bool armed: false
                            readonly property string label: armed ? confirm.text : modelData.label

                            width: Math.ceil(confirm.advanceWidth) + 24
                            height: words.implicitHeight + 12

                            TextMetrics {
                                id: confirm
                                font: words.font
                                text: Lang.confirmTo.arg(action.modelData.label.toLowerCase())
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: "transparent"
                                border.width: 1
                                border.color: Tokens.interrupt
                                opacity: action.armed ? 1 : 0

                                Behavior on opacity { NumberAnimation { duration: Tokens.animFast } }
                            }

                            Label {
                                id: words
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: action.label
                                color: action.armed || area.containsMouse ? Tokens.ink : Tokens.muted
                                font.pixelSize: 12

                                Behavior on color { ColorAnimation { duration: Tokens.animFast } }
                            }

                            Timer {
                                id: disarm
                                interval: 3000
                                onTriggered: action.armed = false
                            }

                            // Over the words at rest, and the whole ring armed.
                            MouseArea {
                                id: area
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                width: action.armed ? parent.width : words.implicitWidth + 24
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (action.armed) {
                                        Quickshell.execDetached(action.modelData.command);
                                        return;
                                    }
                                    action.armed = true;
                                    disarm.restart();
                                }
                            }
                        }
                    }
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 40
                    text: Tokens.motto
                    color: Tokens.off
                    font.italic: true
                    font.pixelSize: 12
                }
            }
        }

        NumberAnimation {
            id: leave
            target: root
            property: "shown"
            to: 0
            duration: Tokens.animNormal
            onFinished: Greetd.launch(Config.session, Config.environment)
        }
    }
}
