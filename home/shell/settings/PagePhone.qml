import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.config
import qs.services
import qs.components

// The phone as a deck (services/Deck.qml, docs/deck.md): turning it on (a
// rebuild: the firewall and the network name), pairing a phone with a QR,
// and the phones paired, each to forget.
Flickable {
    id: page

    readonly property bool wanted: Machine.get("deck.enable", false)

    contentHeight: column.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Component.onCompleted: Deck.refresh()
    Component.onDestruction: Deck.cancel()

    ColumnLayout {
        id: column
        width: page.width
        spacing: 14

        Heading {
            title: Lang.cfgPhone
            sub: Lang.deckSub
        }

        Setting {
            title: Lang.deckUse
            sub: page.wanted && !Deck.enabled ? Lang.deckApply : Lang.deckUseSub.arg(Config.deck.port)

            Toggle {
                on: page.wanted
                onToggled: Machine.set("deck.enable", !on)
            }
        }

        Alert {
            Layout.fillWidth: true
            visible: Deck.enabled && Deck.loaded && !Deck.running
            text: Lang.deckDown
        }

        // A watch has no camera for the QR: nihil-watch (home/deck/watch.sh)
        // pairs adb over Wi-Fi with the code it shows, installs NIHIL for
        // Wear OS and hands it the invitation, in a terminal that stays.
        Setting {
            visible: Deck.enabled && Deck.running
            title: Lang.deckWatchTitle
            sub: Lang.deckWatchSub

            KeyButton {
                text: Lang.deckWatchInstall
                onClicked: Quickshell.execDetached([Config.cmd.terminal, "--hold", "--title", Lang.deckWatchTitle, Config.cmd.watch])
            }
        }

        // A QR that pairs one phone, once, for a few minutes.
        Setting {
            visible: Deck.enabled && Deck.running
            title: Lang.deckPairTitle
            sub: Deck.pairing ? Lang.deckScan : ""

            Column {
                spacing: 14

                KeyButton {
                    visible: !Deck.pairing
                    accent: true
                    text: Lang.deckPair
                    onClicked: Deck.pair()
                }

                Alert {
                    visible: Deck.pairFailed && !Deck.pairing
                    text: Lang.deckPairFailed
                }

                QrCode {
                    visible: Deck.pairing
                    rows: Deck.rows
                }

                KeyButton {
                    visible: Deck.pairing
                    text: Lang.cfgCancel
                    onClicked: Deck.cancel()
                }
            }
        }

        // The phones paired: when each was last used, and forgetting it.
        Label {
            visible: Deck.enabled && Deck.running
            Layout.topMargin: 8
            text: Deck.devices.length > 0 ? Lang.deckPhones : Lang.deckNone
        }

        Repeater {
            model: Deck.enabled && Deck.running ? Deck.devices : []

            Item {
                id: phone

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 44

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: area.hovered ? Tokens.surface : "transparent"
                }

                HoverHandler {
                    id: area
                }

                Txt {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - seen.width - forget.width - 48
                    text: phone.modelData.name
                }

                Label {
                    id: seen
                    anchors.right: forget.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: Dates.moment(phone.modelData.seen ?? 0)
                    font.pixelSize: 12
                }

                KeyButton {
                    id: forget
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: Lang.deckForget
                    onClicked: Deck.forget(phone.modelData.id)
                }
            }
        }
    }
}
