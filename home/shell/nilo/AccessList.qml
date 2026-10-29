import QtQuick
import qs.theme
import qs.config
import qs.services
import qs.components

// What Nilo may do: one LED switch per kind of tool. Git always asks
// before running anything, whatever this says.
Column {
    id: root

    property int current: -1

    readonly property var items: [
        { key: "web", title: Lang.accessWeb, sub: Lang.accessWebSub },
        { key: "system", title: Lang.accessSystem, sub: Lang.accessSystemSub },
        { key: "git", title: Lang.accessGit, sub: Lang.accessGitSub.arg(Nilo.settings.repo ?? "~/nixos-config") }
    ]
    readonly property int count: items.length

    spacing: 2

    function toggle(index: int): void {
        const item = items[index];
        if (item) Nilo.set(item.key, !(Nilo.settings[item.key] === true));
    }

    function move(step: int): void {
        current = current < 0 ? 0 : Math.max(0, Math.min(count - 1, current + step));
    }

    Repeater {
        model: root.items

        Rectangle {
            id: row

            required property var modelData
            required property int index

            readonly property bool on: Nilo.settings[modelData.key] === true

            width: root.width
            height: 56
            radius: 14
            color: root.current === index || area.containsMouse ? Tokens.raised : "transparent"

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.current = row.index;
                    root.toggle(row.index);
                }
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: led.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Txt {
                    width: parent.width
                    text: row.modelData.title
                    color: row.on ? Tokens.ink : Tokens.dim
                    font.pixelSize: 15
                }

                Txt {
                    width: parent.width
                    text: row.modelData.sub
                    color: Tokens.muted
                    font.pixelSize: 12
                }
            }

            Led {
                id: led
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                on: row.on
            }
        }
    }
}
