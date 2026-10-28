import QtQuick
import qs.theme
import qs.services
import qs.components

// Network, Bluetooth and volume. Click opens the panel; scroll on the
// speaker changes the volume.
Item {
    id: root

    required property string output

    implicitWidth: 24
    implicitHeight: column.implicitHeight

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 12

        Ico {
            anchors.horizontalCenter: parent.horizontalCenter
            glyph: Network.ethernet ? Icons.ethernet
                 : !Network.wifiEnabled ? Icons.wifiOff
                 : Network.ssid ? Icons.wifi(Network.strength)
                 : Icons.wifiLevels[0]
            color: Network.connected ? Tokens.ink : Tokens.muted
        }

        Ico {
            anchors.horizontalCenter: parent.horizontalCenter
            glyph: !Bt.enabled ? Icons.btOff : Bt.connected.length > 0 ? Icons.btConnected : Icons.btOn
            color: Bt.connected.length > 0 ? Tokens.ink : Tokens.muted
        }

        Ico {
            id: speaker
            anchors.horizontalCenter: parent.horizontalCenter
            glyph: Icons.volume(Audio.volume, Audio.muted)
            color: Audio.muted ? Tokens.muted : Tokens.ink
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onClicked: Drawers.toggle("panel", root.output)
        onWheel: wheel => {
            const v = Math.max(0, Math.min(1, Audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)));
            Audio.setVolume(v);
            Osd.show("volume", v, false);
        }
    }
}
