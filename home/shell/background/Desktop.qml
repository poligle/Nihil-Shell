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
    // Where the widgets go, worked out as the frame works out its edges: placed by hand, not
    // within what other surfaces reserve, so the glass bends exactly what's behind them.
    readonly property int gap: 24
    readonly property bool anyBar: Quickshell.screens.some(s => Config.barOutputs.indexOf(s.name) >= 0)
    readonly property int inset: root.target !== null && (Config.barOutputs.indexOf(root.target.name) >= 0
        || (!root.anyBar && Quickshell.screens.indexOf(root.target) === 0)) ? Tokens.barWidth : Tokens.frameThickness

    function enabled(name: string): bool {
        return Machine.widgets.indexOf(name) >= 0;
    }

    component Card: Surface {
        default property alias content: inner.data

        width: 320
        implicitHeight: inner.implicitHeight + 40
        pane: true
        radius: Tokens.drawerRadius
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
        exclusionMode: ExclusionMode.Ignore

        anchors { top: true; left: true }
        margins { top: Tokens.frameThickness + root.gap; left: root.inset + root.gap }
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
                origin: Qt.vector2d(root.inset + root.gap, Tokens.frameThickness + root.gap)
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

                NetRates {}

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

                    Label { text: Media.shown(Media.position) + " / " + Media.shown(Media.length) }
                    Item { Layout.fillWidth: true }

                    MediaKeys { size: 28 }
                }
            }
        }
    }
}
