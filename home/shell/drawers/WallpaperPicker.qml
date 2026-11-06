import QtQuick
import qs.theme
import qs.config
import qs.services
import qs.components

// Bottom drawer (SUPER + W), where the launcher comes out: the wallpapers.
// The arrows show each at once, Enter or a click keeps it, Escape goes back
// to the one there was; closing it any other way keeps the one showing.
// The lock screen and the login follow it (nihil-wallpaper).
Item {
    id: root

    property bool active: false
    property string before: ""
    property int index: 0
    readonly property var names: Config.wallpapers

    function show(i: int): void {
        if (names.length === 0)
            return;
        index = (i + names.length) % names.length;
        Machine.liveWallpaper(names[index]);
    }

    onActiveChanged: {
        if (active) {
            before = Machine.wallpaper;
            index = Math.max(0, names.indexOf(before));
            list.positionViewAtIndex(index, ListView.Center);
            keys.forceActiveFocus();
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: root.active
        Keys.onLeftPressed: root.show(root.index - 1)
        Keys.onRightPressed: root.show(root.index + 1)
        Keys.onReturnPressed: Drawers.close()
        Keys.onEnterPressed: Drawers.close()
        Keys.onEscapePressed: {
            Machine.liveWallpaper(root.before);
            Drawers.close();
        }
    }

    KeyHints {
        x: 24
        y: 13
        text: Lang.wpHint
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.topMargin: 44
        anchors.bottomMargin: 22
        orientation: ListView.Horizontal
        spacing: 14
        clip: true
        model: root.names
        currentIndex: root.index
        highlightMoveDuration: Tokens.animFast
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
            id: card

            required property string modelData
            required property int index

            readonly property bool chosen: card.index === root.index

            width: 208
            height: ListView.view.height
            radius: 14
            color: Tokens.surface
            border.width: chosen ? 2 : 1
            border.color: chosen ? Tokens.ink : Tokens.line

            Image {
                anchors.fill: parent
                anchors.margins: 3
                source: "file://" + Config.wallpaperDir + "/" + card.modelData + "/" + Config.primaryOutput + ".png"
                sourceSize.width: 416
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            Label {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 10
                text: card.modelData
                color: card.chosen ? Tokens.ink : Tokens.dim
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.show(card.index);
                    Drawers.close();
                }
            }
        }
    }
}
