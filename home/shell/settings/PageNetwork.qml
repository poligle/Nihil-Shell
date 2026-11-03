import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.config
import qs.services
import qs.components

// A network, in the welcome when there is none: the Wi-Fi of quick settings
// (services/Network.qml).
Flickable {
    id: page

    contentHeight: column.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Component.onCompleted: {
        Network.watch = true;
        Network.scan();
    }
    Component.onDestruction: Network.watch = false

    ColumnLayout {
        id: column
        width: page.width
        spacing: 4

        Heading {
            Layout.bottomMargin: 10
            title: Lang.welNetTitle
            sub: Network.connected ? Lang.welNetDone.arg(Network.ssid || Network.ethernet) : Lang.welNetBody
        }

        Repeater {
            model: Network.connected ? [] : Network.networks.slice(0, 10)

            Item {
                id: net

                required property var modelData
                readonly property bool asking: Network.askPassword === modelData.ssid

                Layout.fillWidth: true
                implicitHeight: 40 + (asking ? 48 : 0)

                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: area.containsMouse || net.asking ? Tokens.surface : "transparent"
                }

                Txt {
                    x: 14
                    y: 11
                    text: net.modelData.ssid
                }

                Label {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    y: 13
                    text: Network.pending === net.modelData.ssid ? Lang.cfgChecking : net.modelData.signal + "%"
                }

                MouseArea {
                    id: area
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 40
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Network.connect(net.modelData, "")
                }

                Field {
                    visible: net.asking
                    x: 14
                    y: 44
                    width: 300
                    height: 36
                    password: true
                    placeholder: Lang.welNetPassword
                    onVisibleChanged: if (visible) grab()
                    onAccepted: Network.connect(net.modelData, text)
                }
            }
        }

        Label {
            visible: Network.error !== ""
            text: Network.error
            color: Tokens.interrupt
        }
    }
}
