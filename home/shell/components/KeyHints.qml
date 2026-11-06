import QtQuick
import qs.theme

// What the keys do, as a keyboard's legend: in "[enter] abre|[esc] cierra"
// each key in brackets is drawn as a key, small (as KeyButton draws one),
// and the rest as words; "|" sets the groups apart. No dots between them.
Row {
    id: root

    property string text: ""

    spacing: 18

    Repeater {
        model: root.text.split("|").map(group => group.trim()).filter(group => group !== "")

        Row {
            id: group

            required property string modelData

            spacing: 6

            Repeater {
                model: group.modelData.split(/(\[[^\]]+\])/).map(part => part.trim()).filter(part => part !== "")

                Item {
                    id: part

                    required property string modelData
                    readonly property bool isKey: modelData.startsWith("[") && modelData.endsWith("]")

                    implicitWidth: isKey ? key.width : word.implicitWidth
                    implicitHeight: 20

                    Rectangle {
                        id: key
                        visible: part.isKey
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(20, name.implicitWidth + 12)
                        height: 20
                        radius: 5
                        color: Tokens.surface
                        border.width: 1
                        border.color: Tokens.line

                        Label {
                            id: name
                            anchors.centerIn: parent
                            text: part.isKey ? part.modelData.slice(1, -1) : ""
                            color: Tokens.dim
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }
                    }

                    Txt {
                        id: word
                        visible: !part.isKey
                        anchors.verticalCenter: parent.verticalCenter
                        text: part.isKey ? "" : part.modelData
                        color: Tokens.muted
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
