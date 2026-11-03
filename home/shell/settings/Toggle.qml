import QtQuick
import qs.theme

// On or off: a lit track with its dot to the right, or a dark one.
Rectangle {
    id: root

    property bool on: false

    signal toggled()

    implicitWidth: 44
    implicitHeight: 24
    radius: height / 2
    color: on ? Tokens.ink : Tokens.surface
    border.width: on ? 0 : 1
    border.color: Tokens.line

    Behavior on color { ColorAnimation { duration: Tokens.animFast } }

    Rectangle {
        width: 16
        height: 16
        radius: 8
        anchors.verticalCenter: parent.verticalCenter
        x: root.on ? parent.width - width - 4 : 4
        color: root.on ? Tokens.black : Tokens.muted

        Behavior on x { NumberAnimation { duration: Tokens.animFast; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
