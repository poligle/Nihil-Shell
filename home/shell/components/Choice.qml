import QtQuick
import qs.theme

Flow {
    id: root

    property var options: []
    property var value
    property bool mono: false

    signal picked(var value)

    spacing: 20

    Repeater {
        model: root.options

        Item {
            id: option

            required property var modelData
            readonly property bool chosen: JSON.stringify(modelData.value) === JSON.stringify(root.value)

            implicitWidth: name.implicitWidth
            implicitHeight: 30

            Txt {
                id: name
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -1
                text: option.modelData.label
                color: option.chosen ? Tokens.ink : area.containsMouse ? Tokens.dim : Tokens.muted
                font.family: root.mono ? Tokens.fontMono : Tokens.fontSans
                font.pixelSize: 13

                Behavior on color { ColorAnimation { duration: Tokens.animFast } }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 2
                color: option.chosen ? Tokens.ink : Tokens.off
                opacity: option.chosen || area.containsMouse ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: Tokens.animFast } }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(option.modelData.value)
            }
        }
    }
}
