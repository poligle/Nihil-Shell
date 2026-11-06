import QtQuick
import qs.theme

// On or off: an LED, lit or not, lined up with Choice's (the same middle).
// The whole of it is the button.
Item {
    id: root

    property bool on: false

    signal toggled()

    implicitWidth: 28
    implicitHeight: 28

    // A faint ring around it while it is on.
    Rectangle {
        anchors.centerIn: led
        width: 20
        height: 20
        radius: 10
        color: Tokens.ink
        opacity: root.on ? 0.08 : 0

        Behavior on opacity { NumberAnimation { duration: Tokens.animFast } }
    }

    Rectangle {
        id: led
        x: -2
        anchors.verticalCenter: parent.verticalCenter
        width: 10
        height: 10
        radius: 5
        color: root.on ? Tokens.ink : area.containsMouse ? Tokens.muted : Tokens.off

        Behavior on color { ColorAnimation { duration: Tokens.animFast } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.leftMargin: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
