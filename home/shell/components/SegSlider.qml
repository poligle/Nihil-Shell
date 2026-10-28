import QtQuick
import qs.theme

// Segmented slider: discrete LEDs instead of a continuous track.
Item {
    id: root

    property real value: 0
    property int segments: 24
    property color litColor: Tokens.ink
    property bool muted: false

    signal moved(real value)

    implicitHeight: 14
    implicitWidth: 240

    readonly property real segWidth: (width - (segments - 1) * 3) / segments
    readonly property int lit: Math.round(Math.max(0, Math.min(1, value)) * segments)

    Repeater {
        model: root.segments

        Rectangle {
            required property int index

            x: index * (root.segWidth + 3)
            width: root.segWidth
            height: root.height
            radius: 3
            color: index < root.lit ? (root.muted ? Tokens.muted : root.litColor) : Tokens.raised

            Behavior on color { ColorAnimation { duration: Tokens.animFast } }
        }
    }

    function emitAt(x: real): void {
        root.moved(Math.max(0, Math.min(1, x / width)));
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => root.emitAt(mouse.x - 6)
        onPositionChanged: mouse => { if (pressed) root.emitAt(mouse.x - 6); }
        onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
