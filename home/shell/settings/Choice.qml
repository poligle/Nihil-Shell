import QtQuick
import qs.theme
import qs.components

// One of a few: each option an LED and its name, the chosen one lit.
// options: [{ value, label }]; `mono` sets the names in Space Mono, for
// numbers.
Flow {
    id: root

    property var options: []
    property var value
    property bool mono: false

    signal picked(var value)

    spacing: 22

    Repeater {
        model: root.options

        Item {
            id: option

            required property var modelData
            readonly property bool chosen: JSON.stringify(modelData.value) === JSON.stringify(root.value)

            implicitWidth: name.implicitWidth + 14
            implicitHeight: 28

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: option.chosen ? Tokens.ink : area.containsMouse ? Tokens.muted : Tokens.off

                Behavior on color { ColorAnimation { duration: Tokens.animFast } }
            }

            Txt {
                id: name
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                text: option.modelData.label
                color: option.chosen ? Tokens.ink : area.containsMouse ? Tokens.dim : Tokens.muted
                font.family: root.mono ? Tokens.fontMono : Tokens.fontSans
                font.pixelSize: 13
            }

            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(option.modelData.value)
            }
        }
    }
}
