//@ pragma Env QT_QPA_PLATFORM=wayland
//@ pragma Env QSG_DISTANCEFIELD_ANTIALIASING=gray

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import qs.theme
import qs.config
import qs.components

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
    property bool going: false

    readonly property string skipFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nihil-greeter-password"

    function start(): void {
        asking = false;
        echo = false;
        sent = false;
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

    function other(): void {
        if (Config.users.length < 2 || going)
            return;
        user = (user + 1) % Config.users.length;
        waiting = "";
        note = "";
        wrong = false;
        field.clear();
        Greetd.cancelSession();
        start();
    }

    function reader(message: string): bool {
        return /finger|swipe|huella|dedo|sensor|lector/i.test(message);
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
                root.note = echoResponse ? message.trim() : "";
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
            root.note = root.reader(message) ? Lang.fingerprintReady : message.trim();
            root.wrong = error;
        }

        function onAuthFailure(message: string): void {
            root.attempts += 1;
            root.wrong = true;
            root.note = Lang.authFailed.replace("$ATTEMPTS", String(root.attempts));
            root.waiting = "";
            root.asking = false;
            root.sent = false;
            field.clear();
            again.restart();
        }

        function onReadyToLaunch(): void {
            root.going = true;
            leave.start();
        }

        function onError(error: string): void {
            root.wrong = true;
            root.note = error;
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
            input.forceActiveFocus();
        }

        Item {
            id: face
            anchors.fill: parent
            opacity: 0

            property Item glassBackdrop: glassFlag.text().trim() === "on" && wall.status === Image.Ready ? glassSource : null

            Component.onCompleted: opacity = 1

            Behavior on opacity { NumberAnimation { duration: Tokens.animSlow; easing.type: Easing.OutCubic } }

            FileView {
                id: glassFlag
                path: Config.glass
                blockLoading: true
            }

            Image {
                id: wall
                anchors.fill: parent
                source: "file://" + Config.wallpaper
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                mipmap: true
                opacity: 0.55
            }

            Item {
                id: glassSource
                readonly property Item texture: wall
                readonly property vector2d origin: Qt.vector2d(0, 0)
                readonly property vector2d screenSize: Qt.vector2d(window.width, window.height)
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
                text: root.person.greeting !== "" ? Lang.welcome + ", " + root.person.greeting : Lang.welcome
                font.pixelSize: 17
            }

            Surface {
                id: field

                function clear(): void { input.text = ""; }

                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height / 2 + 56 - height / 2
                width: 280
                height: 46
                radius: 8
                color: Tokens.black
                border.width: 1
                property color borderTint: root.wrong ? Tokens.interrupt : root.sent || root.waiting !== "" ? Tokens.muted : Tokens.line
                border.color: borderTint

                Behavior on borderTint { ColorAnimation { duration: Tokens.animFast } }

                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    color: root.echo ? Tokens.ink : "transparent"
                    selectionColor: "transparent"
                    cursorVisible: false
                    cursorDelegate: Item {}
                    font.family: Tokens.fontMono
                    font.pixelSize: 14
                    echoMode: root.echo ? TextInput.Normal : TextInput.Password
                    enabled: !root.going
                    onTextEdited: root.wrong = false
                    onAccepted: root.submit(text)
                    Keys.onEscapePressed: text = ""
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

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height / 2 + 110 - height / 2
                text: root.note
                color: root.wrong ? Tokens.ink : Tokens.muted
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

            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 36
                spacing: 28

                Repeater {
                    model: [
                        { label: Lang.actReboot, command: Config.reboot },
                        { label: Lang.actPowerOff, command: Config.powerOff }
                    ]

                    Label {
                        id: action

                        required property var modelData

                        text: modelData.label
                        color: area.containsMouse ? Tokens.ink : Tokens.muted
                        font.pixelSize: 12

                        Behavior on color { ColorAnimation { duration: Tokens.animFast } }

                        MouseArea {
                            id: area
                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(action.modelData.command)
                        }
                    }
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 40
                text: "ex nihilo"
                color: Tokens.off
                font.italic: true
                font.pixelSize: 12
            }
        }

        NumberAnimation {
            id: leave
            target: face
            property: "opacity"
            to: 0
            duration: Tokens.animNormal
            onFinished: Greetd.launch(Config.session, Config.environment)
        }
    }
}
