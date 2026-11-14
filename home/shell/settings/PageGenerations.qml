import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.config
import qs.services
import qs.components

// The system's generations (services/Generations.qml): each rebuild is one,
// a whole system to go back to. One, opened, says what it changed and goes
// to it, now and at boot or the next boot only; under them, how long they
// stay and cleaning now. Those ask sudo, with a finger or the password,
// as applying does (services/Machine.qml).
Flickable {
    id: page

    property int opened: 0
    // Waiting for the password: "switch", "boot" or "clean".
    property string asking: ""
    property string armed: ""
    readonly property int days: Machine.get("generations.days", 7)
    readonly property bool fingerWait: Machine.phase === "auth" && Machine.auth === "finger" && Machine.generational

    contentHeight: column.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Component.onCompleted: Generations.refresh(false)

    function open(number: int): void {
        page.asking = "";
        page.armed = "";
        page.opened = page.opened === number ? 0 : number;
        if (page.opened !== 0)
            Generations.compare(number);
    }

    // With a reader, a finger at once, the field there for the password
    // instead; without one, the password first. Not while something else
    // is applied (the bar below says what).
    function go(action: string, value: int, password: string): void {
        if (Machine.busy && !page.fingerWait)
            return;
        if (password === "" && !Machine.fingerprint) {
            page.asking = action;
            return;
        }
        page.asking = Machine.fingerprint && password === "" ? action : "";
        Machine.generation(action, value, password);
    }

    Connections {
        target: Machine
        function onPhaseChanged(): void {
            if (Machine.phase !== "auth" && Machine.failure !== "finger" && Machine.failure !== "password")
                page.asking = "";
        }
        function onFailureChanged(): void {
            if (Machine.generational && (Machine.failure === "finger" || Machine.failure === "password"))
                page.asking = Machine.kind === "generation" ? "switch" : Machine.kind;
        }
    }

    // Restarting needs a second click within 3 s, as in the panel.
    function arm(name: string): void {
        page.armed = name;
        disarm.restart();
    }

    Timer {
        id: disarm
        interval: 3000
        onTriggered: page.armed = ""
    }

    // The password, and the action again to confirm it.
    component Ask: RowLayout {
        id: ask

        property string action: ""
        property int value: 0
        property string label: ""

        visible: page.asking === action && (!Machine.busy || page.fingerWait)
        spacing: 8

        onVisibleChanged: {
            if (visible)
                Qt.callLater(() => field.grab());
        }

        Field {
            id: field
            Layout.preferredWidth: 220
            password: true
            catchEscape: true
            placeholder: Lang.cfgApplyPassword
            onAccepted: {
                page.go(ask.action, ask.value, text);
                field.clear();
            }
            onEscaped: page.asking = ""
        }

        KeyButton {
            accent: true
            text: ask.label
            onClicked: {
                page.go(ask.action, ask.value, field.text);
                field.clear();
            }
        }

        KeyButton {
            text: Lang.cfgCancel
            onClicked: {
                if (page.fingerWait)
                    Machine.cancelFinger();
                page.asking = "";
            }
        }
    }

    // A generation: its number and when; what it is (in use, at boot, the
    // next boot); opened, what it changed and where to go with it.
    component GenerationRow: Item {
        id: row

        required property var modelData
        readonly property var gen: modelData
        readonly property bool open: page.opened === gen.number
        readonly property var changed: Generations.changes[String(gen.number)] ?? null
        readonly property string mark: gen.current ? Lang.genNow : gen.next ? Lang.genNext : gen.default ? Lang.genDefault : ""

        Layout.fillWidth: true
        implicitHeight: 44 + (open ? details.implicitHeight + 16 : 0)

        Surface {
            anchors.fill: parent
            radius: 10
            color: row.open || area.containsMouse ? Tokens.surface : "transparent"
        }

        Txt {
            id: number
            x: 14
            y: 12
            width: 56
            text: row.gen.number
            color: row.open || row.gen.current ? Tokens.ink : Tokens.dim
            font.family: Tokens.fontMono
            font.pixelSize: 13
        }

        Txt {
            anchors.left: number.right
            y: 12
            text: Dates.moment(row.gen.date)
            color: row.open ? Tokens.ink : Tokens.dim
        }

        Txt {
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 12
            text: row.mark
            color: row.gen.current ? Tokens.ink : Tokens.muted
            font.family: Tokens.fontMono
            font.pixelSize: 13
        }

        MouseArea {
            id: area
            anchors.left: parent.left
            anchors.right: parent.right
            height: 44
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.open(row.gen.number)
        }

        Column {
            id: details
            visible: row.open
            x: 70
            y: 44
            width: parent.width - x - 14
            spacing: 12

            // What it is made of: NixOS, the kernel, NIHIL.
            Flow {
                width: parent.width
                spacing: 18

                Label {
                    visible: row.gen.nixos !== ""
                    text: "NixOS " + row.gen.nixos
                }

                Label {
                    visible: row.gen.kernel !== ""
                    text: "Linux " + row.gen.kernel
                }

                Label {
                    visible: row.gen.nihil !== ""
                    text: "NIHIL " + row.gen.nihil
                }
            }

            Label {
                visible: row.changed === null || row.changed.failed || row.changed.before === null || row.changed.same
                text: row.changed === null ? Lang.genComparing
                    : row.changed.failed ? Lang.genCompareFailed
                    : row.changed.before === null ? Lang.genOldest
                    : Lang.genSame
            }

            // Against the one before: the packages whose versions changed.
            Column {
                visible: row.changed !== null && !row.changed.failed && row.changed.changed.length > 0
                width: parent.width
                spacing: 4

                Repeater {
                    model: row.changed?.changed ?? []

                    Item {
                        required property var modelData

                        width: parent.width
                        height: 18

                        Txt {
                            width: 190
                            text: modelData.name
                            color: Tokens.ink
                            font.pixelSize: 13
                        }

                        Label {
                            x: 200
                            width: parent.width - x
                            text: modelData.from === null ? "+ " + modelData.to
                                : modelData.to === null ? "− " + modelData.from
                                : modelData.from + " → " + modelData.to
                            font.pixelSize: 12
                        }
                    }
                }

                Label {
                    visible: (row.changed?.more ?? 0) > 0
                    text: Lang.genMore.arg(row.changed?.more ?? 0)
                }
            }

            // Where to go with it: not the one in use.
            Flow {
                visible: !row.gen.current && page.asking === "" && !Machine.busy
                width: parent.width
                spacing: 8

                KeyButton {
                    accent: true
                    text: Lang.genSwitch
                    onClicked: page.go("switch", row.gen.number, "")
                }

                KeyButton {
                    visible: row.gen.menu && !row.gen.next
                    text: Lang.genBoot
                    onClicked: page.go("boot", row.gen.number, "")
                }

                KeyButton {
                    visible: row.gen.next
                    text: page.armed === "reboot" ? Lang.confirmAgain : Lang.actReboot
                    accent: page.armed === "reboot"
                    onClicked: {
                        if (page.armed === "reboot") {
                            page.armed = "";
                            Quickshell.execDetached([Config.cmd.systemctl, "reboot"]);
                        } else {
                            page.arm("reboot");
                        }
                    }
                }
            }

            Label {
                visible: !row.gen.current && page.asking === "" && !Machine.busy
                width: parent.width
                text: row.gen.next ? Lang.genBootSub : Lang.genSwitchSub
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }

            Ask {
                visible: page.opened === row.gen.number && page.asking === "switch" && (!Machine.busy || page.fingerWait)
                action: "switch"
                value: row.gen.number
                label: Lang.genSwitch
            }

            Ask {
                visible: page.opened === row.gen.number && page.asking === "boot" && (!Machine.busy || page.fingerWait)
                action: "boot"
                value: row.gen.number
                label: Lang.genBoot
            }
        }
    }

    ColumnLayout {
        id: column
        width: page.width
        spacing: 0

        Heading {
            Layout.bottomMargin: 14
            title: Lang.cfgGenerations
            sub: Lang.genSub
        }

        Label {
            visible: Generations.loaded && (Generations.failed || Generations.list.length === 0)
            Layout.bottomMargin: 10
            text: Generations.failed ? Lang.genListFailed : Lang.genNone
        }

        Repeater {
            model: Generations.list

            GenerationRow {}
        }

        Item {
            Layout.preferredHeight: 18
        }

        // How long they stay: the weekly clean (modules/nix.nix), applied.
        Setting {
            title: Lang.genKeep
            sub: Lang.genKeepSub

            Choice {
                mono: true
                options: [{ value: 7, label: Lang.genDays.arg(7) }, { value: 30, label: Lang.genDays.arg(30) },
                          { value: 90, label: Lang.genDays.arg(90) }]
                value: page.days
                onPicked: value => Machine.set("generations.days", value)
            }
        }

        // The disk, and cleaning now as the weekly clean would.
        Setting {
            title: Lang.genDisk
            sub: Lang.genCleanSub.arg(page.days)

            Column {
                spacing: 10

                Row {
                    spacing: 16

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Generations.size > 0
                        text: Lang.genFree.arg(Dates.bytes(Generations.free)).arg(Dates.bytes(Generations.size))
                        font.pixelSize: 13
                    }

                    KeyButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: page.asking !== "clean" && !Machine.busy
                        text: Lang.genClean
                        onClicked: page.go("clean", page.days, "")
                    }
                }

                Ask {
                    action: "clean"
                    value: page.days
                    label: Lang.genClean
                }
            }
        }
    }
}
