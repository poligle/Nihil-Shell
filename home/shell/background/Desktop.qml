import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.config
import qs.services
import qs.components

Scope {
    id: root

    readonly property var target: {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (screens[i].name === Config.primaryOutput) return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }

    function enabled(name: string): bool {
        return Machine.widgets.indexOf(name) >= 0;
    }

    component Card: Surface {
        default property alias content: inner.data

        width: 320
        implicitHeight: inner.implicitHeight + 40
        pane: true
        radius: 22
        color: Tokens.black
        border.width: 1
        border.color: Tokens.line

        ColumnLayout {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            spacing: 6
        }
    }

    PanelWindow {
        screen: root.target
        visible: root.target !== null && Machine.widgets.length > 0
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "nihil-widgets"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0

        anchors { top: true; left: true }
        margins { top: 24; left: 24 }
        implicitWidth: 320
        implicitHeight: column.implicitHeight

        SystemClock {
            id: clock
            precision: SystemClock.Minutes
        }

        Loader {
            id: backdrop
            active: Machine.glass && root.target !== null
            sourceComponent: Backdrop {
                output: root.target.name
                origin: Qt.vector2d((Config.barOutputs.indexOf(root.target.name) >= 0 ? Tokens.barWidth : Tokens.frameThickness) + 24,
                                    Tokens.frameThickness + 24)
                screenSize: Qt.vector2d(root.target.width, root.target.height)
            }
        }

        Column {
            id: column
            spacing: 14

            property Item glassBackdrop: Machine.glass ? backdrop.item : null

            Card {
                visible: root.enabled("clock")

                DotText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    font.pixelSize: 84
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: Case.sentence(clock.date.toLocaleString(Qt.locale(Lang.locale), Lang.dayName))
                    color: Tokens.dim
                    font.pixelSize: 12
                }

                Txt {
                    Layout.alignment: Qt.AlignHCenter
                    text: clock.date.toLocaleString(Qt.locale(Lang.locale), Lang.dateShort)
                    color: Tokens.muted
                    font.pixelSize: 13
                }
            }

            Card {
                visible: root.enabled("network")

                RowLayout {
                    Layout.fillWidth: true

                    Label { text: SysStats.iface || Lang.offline }
                    Item { Layout.fillWidth: true }
                    Label { text: "↓ " + SysStats.human(SysStats.rx); color: Tokens.dim }
                    Label { text: "↑ " + SysStats.human(SysStats.tx) }
                }

                DotScope {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    series: SysStats.rxHistory
                    secondary: SysStats.txHistory
                }
            }

            Card {
                visible: root.enabled("media")

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    DotScreen {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 64
                        source: Media.art
                        pitch: 4
                        radius: 12
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label { text: Case.sentence(Media.player) || Lang.media }

                        Txt {
                            Layout.fillWidth: true
                            text: Media.title
                            font.weight: Font.Medium
                        }

                        Txt {
                            Layout.fillWidth: true
                            text: Media.artist
                            color: Tokens.dim
                            font.pixelSize: 12
                            visible: text !== ""
                        }
                    }
                }

                DotMeter {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 100
                    count: Math.max(8, Math.floor((width + 3) / 7))
                    dot: 4
                    gap: 3
                    value: Media.progress
                }

                RowLayout {
                    Layout.fillWidth: true

                    Label { text: Media.active ? Media.clock(Media.position) + " / " + Media.clock(Media.length) : "--:-- / --:--" }
                    Item { Layout.fillWidth: true }

                    Row {
                        spacing: 6
                        enabled: Media.active !== null
                        opacity: enabled ? 1 : 0.35

                        CircleButton { glyph: Icons.prev; size: 28; onClicked: Media.previous() }
                        CircleButton { glyph: Media.playing ? Icons.pause : Icons.play; size: 28; filled: true; onClicked: Media.toggle() }
                        CircleButton { glyph: Icons.next; size: 28; onClicked: Media.next() }
                    }
                }
            }
        }
    }
}
