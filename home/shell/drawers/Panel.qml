import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.theme
import qs.config
import qs.services
import qs.components

// Control panel (right drawer): quick toggles, sliders, Wi-Fi / Bluetooth /
// audio output lists, notification history, session actions and updating
// NIHIL (services/Updates.qml): the pointer on its button says how far
// behind, a click shows which commits and asks for the password.
Item {
    id: root

    property bool active: false
    property string expanded: ""        // "", "wifi", "bt", "audio", "update"
    property string armed: ""           // session action waiting for confirmation

    focus: active
    Keys.onEscapePressed: Drawers.close()

    onActiveChanged: {
        Network.watch = active;
        if (active) {
            forceActiveFocus();
            Brightness.refresh();
        } else {
            expanded = "";
            armed = "";
            Network.askPassword = "";
            Bt.scan(false);
        }
    }

    function toggleSection(name: string): void {
        expanded = expanded === name ? "" : name;
        if (expanded === "wifi") Network.scan();
        if (expanded === "update") {
            Updates.maybeCheck();
            Qt.callLater(() => updatePassword.grab());
        }
        Bt.scan(expanded === "bt");
    }

    // Asked once: with a reader and nothing typed, a finger; the password
    // typed goes alone, also while a finger is awaited (services/Machine.qml).
    function update(): void {
        if (updatePassword.text === "" && !Machine.fingerprint) {
            updatePassword.grab();
            return;
        }
        Machine.update(updatePassword.text);
        updatePassword.clear();
    }

    // Power actions need a second click within 3 s.
    function session(name: string, command: var): void {
        if (armed === name) {
            armed = "";
            Drawers.close();
            Quickshell.execDetached(command);
        } else {
            armed = name;
            disarm.restart();
        }
    }

    Timer {
        id: disarm
        interval: 3000
        onTriggered: root.armed = ""
    }

    component SliderRow: RowLayout {
        id: row

        property string glyph: ""
        property real value: 0
        property bool muted: false

        signal moved(real value)
        signal glyphClicked()

        spacing: 12

        Ico {
            Layout.preferredWidth: 22
            glyph: row.glyph
            color: row.muted ? Tokens.interrupt : Tokens.dim

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: row.glyphClicked()
            }
        }

        SegSlider {
            Layout.fillWidth: true
            value: row.value
            muted: row.muted
            onMoved: v => row.moved(v)
        }

        Label {
            Layout.preferredWidth: 30
            horizontalAlignment: Text.AlignRight
            text: String(Math.round(row.value * 100))
        }
    }

    component ListRow: Rectangle {
        id: item

        property string glyph: ""
        property string title: ""
        property string detail: ""
        property bool current: false
        property bool busy: false

        signal clicked()

        Layout.fillWidth: true
        implicitHeight: 40
        radius: 10
        color: area.containsMouse ? Tokens.raised : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Ico { glyph: item.glyph; color: item.current ? Tokens.ink : Tokens.muted }

            Txt {
                Layout.fillWidth: true
                text: item.title
                color: item.current ? Tokens.ink : Tokens.dim
                font.weight: item.current ? Font.Medium : Font.Normal
            }

            Label {
                visible: !item.busy
                text: item.detail
            }

            // Busy (connecting): an LED that breathes.
            Rectangle {
                visible: item.busy
                width: 6
                height: 6
                radius: 3
                color: Tokens.ink

                SequentialAnimation on opacity {
                    running: item.busy
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.2; duration: 600; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.2; to: 1; duration: 600; easing.type: Easing.InOutSine }
                }
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: item.clicked()
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.topMargin: 22
        anchors.bottomMargin: 22
        anchors.leftMargin: 26
        anchors.rightMargin: 22
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 18

            RowLayout {
                Layout.fillWidth: true

                Label { text: Lang.panel }
                Item { Layout.fillWidth: true }
                Label { text: Network.ssid || Network.ethernet || Lang.offline }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 3
                rowSpacing: 6
                columnSpacing: 0

                Tile {
                    Layout.alignment: Qt.AlignHCenter
                    glyph: Network.wifiEnabled ? Icons.wifiOn : Icons.wifiOff
                    label: Lang.tileWifi
                    active: Network.wifiEnabled
                    expandable: true
                    expanded: root.expanded === "wifi"
                    onToggled: Network.setWifi(!Network.wifiEnabled)
                    onExpand: root.toggleSection("wifi")
                }

                Tile {
                    Layout.alignment: Qt.AlignHCenter
                    glyph: Bt.enabled ? Icons.btOn : Icons.btOff
                    label: Lang.tileBluetooth
                    active: Bt.enabled
                    expandable: true
                    expanded: root.expanded === "bt"
                    onToggled: Bt.setEnabled(!Bt.enabled)
                    onExpand: root.toggleSection("bt")
                }

                Tile {
                    Layout.alignment: Qt.AlignHCenter
                    glyph: Icons.speaker
                    label: Lang.tileOutput
                    active: !Audio.muted
                    expandable: true
                    expanded: root.expanded === "audio"
                    onToggled: Audio.toggleMute()
                    onExpand: root.toggleSection("audio")
                }

                Tile {
                    Layout.alignment: Qt.AlignHCenter
                    glyph: Audio.micMuted ? Icons.micOff : Icons.mic
                    label: Lang.tileMic
                    active: !Audio.micMuted
                    onToggled: Audio.toggleMic()
                }

                Tile {
                    Layout.alignment: Qt.AlignHCenter
                    glyph: Notifs.dnd ? Icons.bellOff : Icons.bell
                    label: Lang.tileDnd
                    active: Notifs.dnd
                    onToggled: Notifs.dnd = !Notifs.dnd
                }

                Tile {
                    Layout.alignment: Qt.AlignHCenter
                    glyph: Icons.night
                    label: Lang.tileNight
                    active: Toggles.night
                    onToggled: Toggles.night = !Toggles.night
                }

                // An area to the clipboard, as the Print key.
                Tile {
                    Layout.alignment: Qt.AlignHCenter
                    glyph: Icons.shot
                    label: Lang.tileShot
                    onToggled: { Drawers.close(); Recorder.shot(); }
                }

                // The whole screen; lit, and a stop, while it records.
                Tile {
                    Layout.alignment: Qt.AlignHCenter
                    glyph: Recorder.recording ? Icons.stop : Icons.record
                    label: Lang.tileRecord
                    active: Recorder.recording
                    onToggled: { Drawers.close(); Recorder.toggle(); }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 14

                SliderRow {
                    Layout.fillWidth: true
                    glyph: Icons.volume(Audio.volume, Audio.muted)
                    value: Audio.volume
                    muted: Audio.muted
                    onMoved: v => Audio.setVolume(v)
                    onGlyphClicked: Audio.toggleMute()
                }

                SliderRow {
                    Layout.fillWidth: true
                    glyph: Audio.micMuted ? Icons.micOff : Icons.mic
                    value: Audio.micVolume
                    muted: Audio.micMuted
                    onMoved: v => Audio.setMicVolume(v)
                    onGlyphClicked: Audio.toggleMic()
                }

                SliderRow {
                    Layout.fillWidth: true
                    visible: Brightness.available
                    glyph: Icons.brightness
                    value: Brightness.value
                    onMoved: v => Brightness.set(v)
                }
            }

            // Wi-Fi networks
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.expanded === "wifi"
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true

                    Label { text: Network.scanning ? Lang.scanning : Lang.networks }
                    Item { Layout.fillWidth: true }
                    CircleButton { glyph: Icons.refresh; size: 28; onClicked: Network.rescan() }
                    CircleButton { glyph: Icons.cog; size: 28; onClicked: { Drawers.close(); Network.editor(); } }
                }

                Repeater {
                    model: root.expanded === "wifi" ? Network.networks.slice(0, 12) : []

                    ColumnLayout {
                        id: net

                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 4

                        ListRow {
                            glyph: Icons.wifi(net.modelData.signal)
                            title: net.modelData.ssid
                            detail: net.modelData.active ? Icons.check : (net.modelData.secure ? Icons.lock : "")
                            current: net.modelData.active
                            busy: Network.pending === net.modelData.ssid
                            onClicked: net.modelData.active ? Network.disconnect() : Network.connect(net.modelData, "")
                        }

                        Field {
                            Layout.fillWidth: true
                            visible: Network.askPassword === net.modelData.ssid
                            password: true
                            catchEscape: true
                            placeholder: Lang.password
                            onVisibleChanged: if (visible) { clear(); grab(); }
                            onAccepted: Network.connect(net.modelData, text)
                            onEscaped: Network.askPassword = ""
                        }
                    }
                }

                Alert {
                    Layout.fillWidth: true
                    visible: Network.error !== ""
                    text: Network.error
                }
            }

            // Bluetooth devices
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.expanded === "bt"
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true

                    Label { text: Bt.discovering ? Lang.scanning : Lang.devices }
                    Item { Layout.fillWidth: true }
                    CircleButton { glyph: Icons.refresh; size: 28; onClicked: Bt.scan(!Bt.discovering) }
                    CircleButton { glyph: Icons.cog; size: 28; onClicked: { Drawers.close(); Quickshell.execDetached([Config.cmd.blueman]); } }
                }

                Repeater {
                    model: root.expanded === "bt" ? Bt.devices.slice(0, 10) : []

                    ListRow {
                        required property var modelData

                        glyph: modelData.connected ? Icons.btConnected : Icons.btOn
                        title: modelData.name || modelData.address
                        detail: modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : (modelData.paired ? "" : Lang.newDevice)
                        current: modelData.connected
                        busy: modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting
                        onClicked: Bt.toggleDevice(modelData)
                    }
                }

                Label {
                    visible: Bt.enabled && Bt.devices.length === 0
                    text: Lang.noDevices
                }
            }

            // Audio outputs
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.expanded === "audio"
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true

                    Label { text: Lang.audioOutput }
                    Item { Layout.fillWidth: true }
                    CircleButton { glyph: Icons.cog; size: 28; onClicked: { Drawers.close(); Quickshell.execDetached([Config.cmd.pavucontrol]); } }
                }

                Repeater {
                    model: root.expanded === "audio" ? Audio.sinks : []

                    ListRow {
                        required property var modelData

                        glyph: /headphone|headset|bluez/i.test(modelData.name) ? Icons.headphones : Icons.speaker
                        title: modelData.description || modelData.nickname || modelData.name
                        current: Audio.sink === modelData
                        onClicked: Audio.setDefaultSink(modelData)
                    }
                }
            }

            // Notifications
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true

                    Label { text: Lang.notifications.arg(Notifs.history.length) }
                    Item { Layout.fillWidth: true }
                    CircleButton { glyph: Icons.broom; label: Lang.clear; size: 28; visible: Notifs.history.length > 0; onClicked: Notifs.clear() }
                }

                Repeater {
                    model: Notifs.history.slice(0, 6)

                    NotifCard {
                        required property var modelData

                        Layout.fillWidth: true
                        notification: modelData
                    }
                }

                Label {
                    visible: Notifs.history.length === 0
                    text: Notifs.dnd ? Lang.dndOn : Lang.nothingNew
                }
            }

            // Session
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Tokens.line
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    CircleButton { glyph: Icons.lock; onClicked: { Drawers.close(); Quickshell.execDetached([Config.cmd.lock]); } }
                    CircleButton { glyph: Icons.sleep; onClicked: { Drawers.close(); Quickshell.execDetached([Config.cmd.systemctl, "suspend"]); } }
                    CircleButton { glyph: Icons.logout; filled: root.armed === "logout"; onClicked: root.session("logout", [Config.cmd.uwsm, "stop"]) }
                    CircleButton { glyph: Icons.restart; filled: root.armed === "reboot"; onClicked: root.session("reboot", [Config.cmd.systemctl, "reboot"]) }
                    CircleButton { glyph: Icons.power; danger: true; filled: root.armed === "power"; onClicked: root.session("power", [Config.cmd.powerOff]) }

                    Item { Layout.fillWidth: true }

                    // A newer NIHIL: a lit dot when GitHub has one.
                    CircleButton {
                        id: updateButton
                        glyph: Icons.download
                        filled: root.expanded === "update"
                        onClicked: root.toggleSection("update")

                        Rectangle {
                            visible: Updates.state === "behind" && !updateButton.filled
                            anchors.top: parent.top
                            anchors.right: parent.right
                            width: 9
                            height: 9
                            radius: 4.5
                            color: Tokens.ink
                            border.width: 2
                            border.color: Tokens.black
                        }
                    }

                    // Preferences (settings/Preferences.qml).
                    CircleButton {
                        glyph: Icons.cog
                        onClicked: {
                            Drawers.close();
                            Machine.show("", false);
                        }
                    }
                }

                // The second click a power action asks for, said on a line of
                // its own that is always there: the row of buttons never grows,
                // which pushed the panel past the edge of the screen. With the
                // pointer on the update button, how far behind NIHIL is.
                Alert {
                    Layout.fillWidth: true
                    text: root.armed !== "" ? Lang.confirmAgain : Updates.summary
                    wrong: root.armed !== ""
                    opacity: root.armed !== "" || updateButton.hovered ? 1 : 0
                }

                // Updating: what is new, and the password it needs; while it
                // updates, how it goes (as Preferences says it).
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.expanded === "update" || Machine.updating
                    spacing: 6

                    Txt {
                        Layout.fillWidth: true
                        text: Updates.dev !== "" ? Lang.updDev : Lang.updWhat
                        color: Tokens.muted
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: Updates.state === "behind" ? Updates.commits.slice(0, 6) : []

                        RowLayout {
                            id: commit

                            required property var modelData

                            Layout.fillWidth: true
                            spacing: 10

                            Label { text: commit.modelData.sha }

                            Txt {
                                Layout.fillWidth: true
                                text: commit.modelData.subject
                                color: Tokens.dim
                                font.pixelSize: 12
                            }
                        }
                    }

                    Label {
                        visible: Updates.state === "behind" && Updates.behind > 6
                        text: Lang.updMore.arg(Updates.behind - 6)
                    }

                    Alert {
                        Layout.fillWidth: true
                        visible: Machine.kind === "update" && Machine.phase !== ""
                        text: Machine.statusTitle
                        wrong: Machine.phase === "failed"
                        color: Tokens.ink
                        font.family: Tokens.fontSans
                        font.pixelSize: 13
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: Machine.kind === "update" && Machine.phase !== "" && text !== ""
                        text: Machine.statusSub
                    }

                    // Also while a finger is awaited: the password instead.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: !Machine.busy || (Machine.kind === "update" && Machine.phase === "auth" && Machine.auth === "finger")
                        spacing: 8

                        Field {
                            id: updatePassword
                            Layout.fillWidth: true
                            password: true
                            catchEscape: true
                            placeholder: Lang.cfgApplyPassword
                            onAccepted: root.update()
                            onEscaped: root.expanded = ""
                        }

                        KeyButton {
                            accent: true
                            text: Lang.updUpdate
                            onClicked: root.update()
                        }
                    }
                }
            }
        }
    }
}
