import QtQuick
import qs.theme

// Round icon button with a hairline border.
Rectangle {
    id: root

    property string glyph: ""
    property int size: 36
    property bool danger: false
    property bool filled: false

    signal clicked()

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    color: filled ? Tokens.ink : (area.containsMouse ? Tokens.raised : "transparent")
    border.width: filled ? 0 : 1
    border.color: danger ? Tokens.interrupt : Tokens.line

    Behavior on color { ColorAnimation { duration: Tokens.animFast } }

    Ico {
        anchors.centerIn: parent
        glyph: root.glyph
        font.pixelSize: Math.round(root.size * 0.45)
        color: root.filled ? Tokens.black : (root.danger ? Tokens.interrupt : (area.containsMouse ? Tokens.ink : Tokens.dim))
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
