import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.config
import qs.services
import qs.components

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
            sub: Network.connected ? Lang.welNetDone.arg(Network.ssid || Network.ethernet) : Machine.welcoming ? Lang.welNetBody : ""
        }

        WifiList {
            Layout.fillWidth: true
            visible: !Network.connected
            active: !Network.connected
        }
    }
}
