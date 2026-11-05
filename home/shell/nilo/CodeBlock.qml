import QtQuick
import qs.theme
import qs.config
import qs.components

// A block of code in one of Nilo's answers (Chat.qml): rounded, its
// language above it, and a button that copies it. The code can be
// selected with the pointer too.
Rectangle {
    id: root

    property string code: ""
    property string language: ""

    implicitHeight: head.height + body.implicitHeight + 14
    height: implicitHeight
    radius: 12
    color: Tokens.surface
    border.width: 1
    border.color: Tokens.line

    Item {
        id: head
        x: 14
        width: parent.width - 24
        height: 34

        Label {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.language !== "" ? root.language : Lang.niloCode
        }

        CopyButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            wordFirst: true
            text: root.code
        }
    }

    TextEdit {
        id: body
        x: 14
        y: head.height
        width: parent.width - 28
        text: root.code
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
        color: "#E6E6E6"
        selectionColor: Tokens.ink
        selectedTextColor: Tokens.black
        font.family: Tokens.fontMono
        font.pixelSize: 12
    }
}
