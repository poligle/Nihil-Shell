import QtQuick
import qs.components

// One of a few: pills, the chosen one lit. options: [{ value, label }].
Flow {
    id: root

    property var options: []
    property var value

    signal picked(var value)

    spacing: 6

    Repeater {
        model: root.options

        PillButton {
            required property var modelData

            text: modelData.label
            accent: JSON.stringify(modelData.value) === JSON.stringify(root.value)
            onClicked: root.picked(modelData.value)
        }
    }
}
