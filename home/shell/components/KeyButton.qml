import QtQuick
import qs.theme

// A button as a key on the keyboard (nilo/Keycap.qml): hairline, Space Mono
// capitals. `accent` lights it (ink, the name in black) for the one thing
// to do; `danger` makes it red, for one that can't be undone (red only
// interrupts).
Rectangle {
    id: root

    property string text: ""
    property bool accent: false
    property bool danger: false

    signal clicked()

    implicitWidth: label.implicitWidth + 28
    implicitHeight: 30
    radius: 8
    color: danger ? Tokens.interrupt : accent ? Tokens.ink : area.containsMouse ? Tokens.raised : Tokens.surface
    border.width: 1
    border.color: danger ? Tokens.interrupt : accent ? Tokens.ink : area.containsMouse ? Tokens.muted : Tokens.line

    Behavior on color { ColorAnimation { duration: Tokens.animFast } }

    Label {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.danger ? Tokens.ink : root.accent ? Tokens.black : area.containsMouse ? Tokens.ink : Tokens.dim
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
