import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.config
import qs.services
import qs.components

// Top drawer: time, music with a dot-matrix cover and spectrum, and an
// instrument cluster (CPU, RAM, temperature, network scope).
Item {
    id: root

    property bool active: false

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 22
        anchors.bottomMargin: 26
        spacing: 26

        // Time
        ColumnLayout {
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            spacing: 4

            Label { text: "ex nihilo" }

            DotText {
                text: Qt.formatDateTime(clock.date, "HH:mm")
                font.pixelSize: 68
            }

            Txt {
                Layout.fillWidth: true
                text: clock.date.toLocaleString(Qt.locale(Lang.locale), Lang.dateLong)
                color: Tokens.dim
                font.pixelSize: 15
            }

            Item { Layout.fillHeight: true }

            Label {
                text: Battery.present
                    ? Lang.battery.arg(Math.round(Battery.level * 100)) + (Battery.charging ? " · " + Lang.charging : "")
                    : Lang.network.arg(Network.ssid || Network.ethernet || Lang.noConnection)
            }
        }

        Rectangle {
            Layout.fillHeight: true
            implicitWidth: 1
            color: Tokens.line
        }

        // Music
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                DotScreen {
                    Layout.preferredWidth: 104
                    Layout.preferredHeight: 104
                    source: Media.art
                    pitch: 4
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Label { text: Media.player || Lang.media }

                    Txt {
                        Layout.fillWidth: true
                        text: Media.title
                        font.pixelSize: 17
                        font.weight: Font.Medium
                    }

                    Txt {
                        Layout.fillWidth: true
                        text: Media.artist
                        color: Tokens.dim
                        visible: text !== ""
                    }

                    Row {
                        Layout.topMargin: 6
                        spacing: 8

                        CircleButton { glyph: Icons.prev; size: 32; onClicked: Media.previous() }
                        CircleButton { glyph: Media.playing ? Icons.pause : Icons.play; size: 32; filled: true; onClicked: Media.toggle() }
                        CircleButton { glyph: Icons.next; size: 32; onClicked: Media.next() }
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

                Label { text: Media.clock(Media.position) }
                Item { Layout.fillWidth: true }
                Label { text: Media.clock(Media.length) }
            }

            Visualizer {
                Layout.fillWidth: true
                Layout.fillHeight: true
                running: root.active && Media.playing
            }
        }

        Rectangle {
            Layout.fillHeight: true
            implicitWidth: 1
            color: Tokens.line
        }

        // Instruments
        ColumnLayout {
            Layout.preferredWidth: 262
            Layout.fillHeight: true
            spacing: 10

            Row {
                spacing: 6

                Dial { width: 82; height: 82; value: SysStats.cpu; text: String(Math.round(SysStats.cpu * 100)); label: "cpu" }
                Dial { width: 82; height: 82; value: SysStats.mem; text: String(Math.round(SysStats.mem * 100)); label: "ram" }
                Dial {
                    width: 82
                    height: 82
                    value: Math.min(1, SysStats.temp / 100)
                    text: String(Math.round(SysStats.temp))
                    label: "°c"
                    alert: SysStats.temp >= 90
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Label { text: SysStats.iface || Lang.offline }
                Item { Layout.fillWidth: true }
                Label { text: "↓ " + SysStats.human(SysStats.rx); color: Tokens.dim }
                Label { text: "↑ " + SysStats.human(SysStats.tx) }
            }

            DotScope {
                Layout.fillWidth: true
                Layout.fillHeight: true
                series: SysStats.rxHistory
                secondary: SysStats.txHistory
            }
        }
    }
}
