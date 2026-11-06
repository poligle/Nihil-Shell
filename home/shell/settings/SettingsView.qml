import QtQuick
import qs.theme
import qs.config
import qs.services
import qs.components

// Preferences: the pages on the left, the one chosen on the right, and what
// is waiting to be applied at the bottom.
Item {
    id: root

    readonly property var pages: [
        { name: "you", title: Lang.cfgYou, file: "PageYou.qml" },
        { name: "region", title: Lang.cfgRegion, file: "PageRegion.qml" },
        { name: "look", title: Lang.cfgLook, file: "PageLook.qml" },
        { name: "screens", title: Lang.cfgScreens, file: "PageScreens.qml" },
        { name: "keys", title: Lang.cfgKeys, file: "PageKeys.qml" },
        { name: "system", title: Lang.cfgSystem, file: "PageSystem.qml" }
    ]
    readonly property var current: pages.find(page => page.name === Machine.page) ?? pages[0]

    Column {
        id: side
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 28
        width: 196
        spacing: 4

        Logo {
            size: 30
        }

        Label {
            text: Lang.cfgTitle
            bottomPadding: 22
        }

        // The pages, each with its LED: lit on the one open.
        Repeater {
            model: root.pages

            Item {
                id: item

                required property var modelData
                readonly property bool chosen: root.current.name === modelData.name

                width: side.width
                height: 34

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: 6
                    radius: 3
                    color: item.chosen ? Tokens.ink : "transparent"
                }

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 18
                    text: item.modelData.title
                    color: item.chosen || navArea.containsMouse ? Tokens.ink : Tokens.dim

                    Behavior on color { ColorAnimation { duration: Tokens.animFast } }
                }

                MouseArea {
                    id: navArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Machine.page = item.modelData.name
                }
            }
        }
    }

    CircleButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 20
        size: 32
        glyph: Icons.close
        onClicked: Machine.hide()
    }

    Loader {
        anchors.left: side.right
        anchors.leftMargin: 36
        anchors.right: parent.right
        anchors.rightMargin: 64
        anchors.top: parent.top
        anchors.topMargin: 30
        anchors.bottom: bar.top
        anchors.bottomMargin: 14
        source: Qt.resolvedUrl(root.current.file)
    }

    ApplyBar {
        id: bar
        anchors.left: side.right
        anchors.leftMargin: 36
        anchors.right: parent.right
        anchors.rightMargin: 28
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
    }
}
