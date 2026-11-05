import QtQuick
import qs.theme
import qs.config
import qs.services
import qs.components

// Top drawer: the clipboard history (services/Clipboard.qml), newest first.
// The one chosen is lit; a picture shows in dots, a colour as a lit LED of
// it. A click pastes one too, and the cross forgets it.
Item {
    id: root

    property bool active: false

    readonly property real rowHeight: 56

    // As deep as its copies (Frame.qml): one row at least, for "nothing yet".
    implicitHeight: 50 + Math.max(1, Clipboard.items.length) * (rowHeight + 4) + 12

    Label {
        x: 26
        y: 18
        text: Lang.bindClipboard
    }

    Label {
        anchors.right: parent.right
        anchors.rightMargin: 26
        y: 18
        text: Clipboard.hint
    }

    Txt {
        x: 26
        y: 56
        visible: Clipboard.items.length === 0
        text: Lang.clipEmpty
        color: Tokens.muted
        font.pixelSize: 13
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.topMargin: 46
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.bottomMargin: 12
        clip: true
        spacing: 4
        model: Clipboard.items
        currentIndex: Clipboard.index
        highlightMoveDuration: 0
        boundsBehavior: Flickable.StopAtBounds
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Rectangle {
            id: row

            required property var modelData
            required property int index

            readonly property bool chosen: row.index === Clipboard.index
            readonly property string kind: modelData.kind

            width: ListView.view.width
            height: root.rowHeight
            radius: 14
            color: chosen ? Tokens.raised : (area.containsMouse ? Tokens.surface : "transparent")
            border.width: chosen ? 1 : 0
            border.color: Tokens.line

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Clipboard.pick(row.index)
            }

            // Its place: 1 is what the clipboard holds now.
            Txt {
                id: place
                x: 14
                width: 20
                anchors.verticalCenter: parent.verticalCenter
                text: String(row.index + 1)
                color: row.chosen ? Tokens.ink : Tokens.muted
                font.family: Tokens.fontMono
                font.pixelSize: 12
            }

            DotScreen {
                id: picture
                visible: row.kind === "image"
                anchors.left: place.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? 70 : 0
                height: 42
                radius: 8
                pitch: 3
                source: visible ? "file://" + row.modelData.file : ""
            }

            Rectangle {
                id: swatch
                visible: row.kind === "colour"
                anchors.left: picture.right
                anchors.leftMargin: visible ? 2 : 0
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? 20 : 0
                height: 20
                radius: 10
                color: visible ? row.modelData.text.trim() : "transparent"
                border.width: 1
                border.color: Tokens.line
            }

            Txt {
                anchors.left: swatch.right
                anchors.leftMargin: 12
                anchors.right: what.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: row.kind !== "image" ? row.modelData.text
                    : row.modelData.width > 0 ? Lang.clipPictureSize.arg(row.modelData.width).arg(row.modelData.height)
                    : row.modelData.format.toUpperCase()
                color: row.chosen ? Tokens.ink : Tokens.dim
                wrapMode: Text.Wrap
                maximumLineCount: 2
                font.family: row.kind === "colour" ? Tokens.fontMono : Tokens.fontSans
                font.pixelSize: 13
            }

            // What it is; on hover, a cross that forgets it instead.
            Label {
                id: what
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                visible: !forget.visible
                text: row.kind === "image" ? Lang.clipPicture : row.kind === "colour" ? Lang.clipColour
                    : row.kind === "link" ? Lang.clipLink : Lang.clipText
            }

            Ico {
                id: forget
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                visible: area.containsMouse || forgetArea.containsMouse
                glyph: Icons.close
                font.pixelSize: 14
                color: forgetArea.containsMouse ? Tokens.interrupt : Tokens.dim

                MouseArea {
                    id: forgetArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Clipboard.forget(row.modelData.id)
                }
            }
        }
    }
}
