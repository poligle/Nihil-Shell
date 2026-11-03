import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.config
import qs.services
import qs.components

// The wallpaper: it changes at once (nihil-wallpaper), and the lock screen's
// and the login's once applied.
Flickable {
    id: page

    readonly property string current: Machine.wallpaper !== "" ? Machine.wallpaper : Machine.get("wallpaper", "night")

    contentHeight: column.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: column
        width: page.width
        spacing: 16

        Heading {
            title: Lang.cfgWallpaper
            sub: Lang.cfgLookSub
        }

        Flow {
            Layout.fillWidth: true
            spacing: 14

            Repeater {
                model: Config.wallpapers

                Rectangle {
                    id: card

                    required property string modelData
                    readonly property bool chosen: page.current === modelData

                    width: 208
                    height: 132
                    radius: 14
                    color: Tokens.surface
                    border.width: chosen ? 2 : 1
                    border.color: chosen ? Tokens.ink : (cardArea.containsMouse ? Tokens.muted : Tokens.line)

                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        source: "file://" + Config.wallpaperDir + "/" + card.modelData + "/" + Config.primaryOutput + ".png"
                        sourceSize.width: 416
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 8
                        width: name.implicitWidth + 16
                        height: 20
                        radius: 10
                        color: Tokens.black
                        opacity: 0.85

                        Label {
                            id: name
                            anchors.centerIn: parent
                            text: card.modelData
                            color: card.chosen ? Tokens.ink : Tokens.dim
                        }
                    }

                    MouseArea {
                        id: cardArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Machine.setWallpaper(card.modelData)
                    }
                }
            }
        }
    }
}
