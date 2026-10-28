import QtQuick
import qs.theme

// A row or column of LEDs: the first round(value * count) are lit.
Item {
    id: root

    property int count: 10
    property real value: 0
    property bool vertical: false
    property int dot: 6
    property int gap: 3
    property color litColor: Tokens.ink
    property color unlitColor: Tokens.off
    // Optional moving highlight (charging, scanning): index of the lit "head", or -1.
    property int head: -1

    readonly property int lit: Math.round(Math.max(0, Math.min(1, value)) * count)

    implicitWidth: vertical ? dot : count * dot + (count - 1) * gap
    implicitHeight: vertical ? count * dot + (count - 1) * gap : dot

    Repeater {
        model: root.count

        Rectangle {
            required property int index

            width: root.dot
            height: root.dot
            radius: root.dot / 2
            x: root.vertical ? 0 : index * (root.dot + root.gap)
            y: root.vertical ? (root.count - 1 - index) * (root.dot + root.gap) : 0
            color: index < root.lit || index === root.head ? root.litColor : root.unlitColor

            Behavior on color { ColorAnimation { duration: Tokens.animFast } }
        }
    }
}
