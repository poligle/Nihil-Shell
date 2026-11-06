import QtQuick
import qs.theme

// On or off: a switch, ink when on, a hairline when off. The whole of it
// is the button.
Item {
    id: root

    property bool on: false

    signal toggled()

    implicitWidth: 34
    implicitHeight: 30

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: 34
        height: 20
        radius: 10
        color: root.on ? Tokens.ink : "transparent"
        border.width: 1
        border.color: root.on ? Tokens.ink : area.containsMouse ? Tokens.muted : Tokens.off

        Behavior on color { ColorAnimation { duration: Tokens.animFast } }
        Behavior on border.color { ColorAnimation { duration: Tokens.animFast } }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: root.on ? parent.width - width - 4 : 4
            width: 12
            height: 12
            radius: 6
            color: root.on ? Tokens.black : area.containsMouse ? Tokens.dim : Tokens.muted

            Behavior on x { NumberAnimation { duration: Tokens.animFast; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Tokens.animFast } }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
