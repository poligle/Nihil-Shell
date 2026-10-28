import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.theme
import qs.config
import qs.services
import qs.components

// Control panel (right drawer): quick toggles, sliders, Wi-Fi / Bluetooth /
// audio output lists, notification history and session actions.
Item {
    id: root

    property bool active: false
    property string expanded: ""        // "", "wifi", "bt", "audio"
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
        Bt.scan(expanded === "bt");
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
        radius: 12
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

            Label { text: item.busy ? "···" : item.detail }
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

                        Rectangle {
                            Layout.fillWidth: true
                            visible: Network.askPassword === net.modelData.ssid
                            implicitHeight: 40
                            radius: 20
                            color: Tokens.surface
                            border.width: 1
                            border.color: Tokens.line

                            QQC.TextField {
                                id: password
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                background: null
                                echoMode: TextInput.Password
                                color: Tokens.ink
                                placeholderText: Lang.password
                                placeholderTextColor: Tokens.muted
                                font.family: Tokens.fontMono
                                font.pixelSize: 13
                                verticalAlignment: TextInput.AlignVCenter
                                onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                                onAccepted: Network.connect(net.modelData, text)
                                Keys.onEscapePressed: Network.askPassword = ""
                            }
                        }
                    }
                }

                Label {
                    visible: Network.error !== ""
                    text: Network.error
                    color: Tokens.interrupt
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
                    PillButton { text: Lang.clear; visible: Notifs.history.length > 0; onClicked: Notifs.clear() }
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

                    Label {
                        visible: root.armed !== ""
                        text: Lang.confirmAgain
                        color: Tokens.interrupt
                    }
                }
            }
        }
    }
}
