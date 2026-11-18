import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.theme
import qs.config

Column {
    id: root

    spacing: 8

    readonly property var list: Hyprland.workspaces.values.filter(w => w.id > 0)
    readonly property int count: Math.max(Config.persistentWorkspaces, ...list.map(w => w.id))
    readonly property int focused: Hyprland.focusedWorkspace?.id ?? 1

    function go(target: string): void {
        Hyprland.dispatch(Hyprland.usingLua
            ? `hl.dsp.focus({ workspace = "${target}" })`
            : `workspace ${target}`);
    }

    Repeater {
        model: root.count

        Item {
            id: slot

            required property int index

            readonly property int wsId: index + 1
            readonly property var ws: root.list.find(w => w.id === wsId) ?? null
            readonly property bool isFocused: root.focused === wsId
            readonly property bool occupied: (ws?.toplevels?.values?.length ?? 0) > 0
            readonly property bool urgent: ws?.urgent ?? false

            width: 16
            height: isFocused ? 24 : 8

            Behavior on height { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.centerIn: parent
                width: 6
                height: slot.isFocused ? parent.height : 6
                radius: 3
                color: slot.urgent ? Tokens.interrupt : (slot.isFocused || slot.occupied ? Tokens.ink : Tokens.off)

                Behavior on color { ColorAnimation { duration: Tokens.animFast } }
            }

            // Wider than the dot, and as tall as half the gap on each side: 32 px across, and
            // nothing left between one and the next.
            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: -8
                anchors.rightMargin: -8
                anchors.topMargin: -root.spacing / 2
                anchors.bottomMargin: -root.spacing / 2
                cursorShape: Qt.PointingHandCursor
                Accessible.role: Accessible.Button
                Accessible.name: Lang.workspace.arg(slot.wsId)
                Accessible.onPressAction: slot.ws ? slot.ws.activate() : root.go(String(slot.wsId))
                onClicked: slot.ws ? slot.ws.activate() : root.go(String(slot.wsId))
            }
        }
    }

    WheelHandler {
        onWheel: event => root.go(event.angleDelta.y > 0 ? "e-1" : "e+1")
    }
}
