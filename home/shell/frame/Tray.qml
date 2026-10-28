import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.theme
import qs.config
import qs.components

// System tray, monochrome. Left click activates, right click opens the menu.
// Items listed in nihil.trayHidden are left out: the Wi-Fi and Bluetooth
// applets already have their own icons in the bar (and keep running for
// password and pairing prompts).
Column {
    id: root

    spacing: 10
    visible: items.count > 0

    function hidden(item): bool {
        const name = `${item.id} ${item.title}`.toLowerCase();
        return Config.trayHidden.some(pattern => name.indexOf(pattern.toLowerCase()) >= 0);
    }

    Repeater {
        id: items

        model: SystemTray.items.values.filter(item => !root.hidden(item))

        Item {
            id: entry

            required property SystemTrayItem modelData

            width: 18
            height: 18

            // App icons fill their whole square, unlike the glyphs of the bar,
            // so they are drawn a little smaller to weigh the same.
            AppIcon {
                anchors.centerIn: parent
                size: 14
                icon: entry.modelData.icon
                colored: area.containsMouse
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton && !entry.modelData.onlyMenu) {
                        entry.modelData.activate();
                    } else if (entry.modelData.hasMenu) {
                        const p = entry.mapToItem(null, entry.width + 10, 0);
                        entry.modelData.display(QsWindow.window, p.x, p.y);
                    }
                }
            }
        }
    }
}
