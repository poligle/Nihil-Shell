import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components

// A page's or a group's title, and a line saying what it is about.
Column {
    id: root

    property string title: ""
    property string sub: ""

    Layout.fillWidth: true
    spacing: 4

    Txt {
        width: root.width
        text: root.title
        font.pixelSize: 22
    }

    Txt {
        visible: root.sub !== ""
        width: root.width
        text: root.sub
        color: Tokens.dim
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
    }
}
