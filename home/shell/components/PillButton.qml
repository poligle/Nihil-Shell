import QtQuick
import qs.theme

// Text button: hairline pill, uppercase mono label.
Rectangle {
    id: root

    property string text: ""
    property bool accent: false

    signal clicked()

    implicitWidth: label.implicitWidth + 24
    implicitHeight: 26
    radius: height / 2
    color: accent ? Tokens.ink : (area.containsMouse ? Tokens.raised : "transparent")
    border.width: accent ? 0 : 1
    border.color: Tokens.line

    Label {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.accent ? Tokens.black : (area.containsMouse ? Tokens.ink : Tokens.dim)
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
