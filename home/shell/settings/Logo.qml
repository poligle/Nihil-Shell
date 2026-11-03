import QtQuick
import qs.components

// NIHIL in dots, a letter at a time on whole pixels: both I's alike.
Row {
    id: root

    property int size: 30

    spacing: Math.round(size * 0.08)

    Repeater {
        model: ["N", "I", "H", "I", "L"]

        DotText {
            required property string modelData

            text: modelData
            font.pixelSize: root.size
            width: Math.ceil(implicitWidth)
        }
    }
}
