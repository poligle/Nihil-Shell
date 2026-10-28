import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.theme
import qs.config

// Workspaces as LEDs: off = empty, lit = has windows, long pill = focused,
// red = urgent. Scroll to move between workspaces.
Column {
    id: root

    spacing: 8

    readonly property var list: Hyprland.workspaces.values.filter(w => w.id > 0)
    readonly property int count: Math.max(Config.persistentWorkspaces, ...list.map(w => w.id))
    readonly property int focused: Hyprland.focusedWorkspace?.id ?? 1

    // Hyprland's Lua config (0.55+) takes Lua dispatchers; hyprlang takes the classic syntax.
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

            MouseArea {
                anchors.fill: parent
                anchors.margins: -3
                cursorShape: Qt.PointingHandCursor
                onClicked: slot.ws ? slot.ws.activate() : root.go(String(slot.wsId))
            }
        }
    }

    WheelHandler {
        onWheel: event => root.go(event.angleDelta.y > 0 ? "e-1" : "e+1")
    }
}
