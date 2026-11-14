import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.config
import qs.services
import qs.components

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
        }

        Flow {
            Layout.fillWidth: true
            spacing: 14

            Repeater {
                model: Config.wallpapers

                Column {
                    id: card

                    required property string modelData
                    readonly property bool chosen: page.current === modelData

                    spacing: 8

                    Surface {
                        width: 208
                        height: 132
                        radius: 12
                        color: Tokens.surface
                        border.width: card.chosen ? 2 : 1
                        border.color: card.chosen ? Tokens.ink : (cardArea.containsMouse ? Tokens.muted : Tokens.line)

                        Image {
                            anchors.fill: parent
                            anchors.margins: 3
                            source: "file://" + Config.wallpaperDir + "/" + card.modelData + "/" + Config.primaryOutput + ".png"
                            sourceSize.width: 416
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        MouseArea {
                            id: cardArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Machine.setWallpaper(card.modelData)
                        }
                    }

                    Label {
                        text: Case.sentence(card.modelData.replace(/[-_]/g, " "))
                        color: card.chosen ? Tokens.ink : Tokens.muted
                    }
                }
            }
        }

        Setting {
            Layout.topMargin: 18
            title: Lang.cfgGlass

            Toggle {
                on: Machine.glass
                onToggled: Machine.setGlass(!on)
            }
        }

        Heading {
            Layout.topMargin: 18
            title: Lang.cfgWidgets
        }

        Repeater {
            model: Config.widgets

            Setting {
                required property string modelData

                title: Lang["cfgWidget" + modelData.charAt(0).toUpperCase() + modelData.slice(1)] ?? modelData

                Toggle {
                    on: Machine.widgets.indexOf(modelData) >= 0
                    onToggled: Machine.setWidget(modelData, !on)
                }
            }
        }
    }
}
