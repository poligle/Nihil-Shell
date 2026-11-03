import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components

// One setting: what it is on the left, its control on the right.
Item {
    id: root

    property string title: ""
    property string sub: ""
    default property alias control: holder.data

    Layout.fillWidth: true
    implicitHeight: Math.max(texts.implicitHeight, holder.height) + 14

    Column {
        id: texts
        anchors.left: parent.left
        anchors.right: holder.left
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Txt {
            width: parent.width
            text: root.title
            font.pixelSize: 15
        }

        Txt {
            visible: root.sub !== ""
            width: parent.width
            text: root.sub
            color: Tokens.muted
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
    }

    Item {
        id: holder
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Tokens.line
        opacity: 0.6
    }
}
