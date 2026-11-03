import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.config
import qs.services
import qs.components

// How many fingers on the touchpad for each gesture (modules/binds.nix).
Flickable {
    id: page

    readonly property var gestures: ["workspaces", "close", "launcher", "special"]

    contentHeight: column.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function fingers(name: string): var {
        const chosen = Machine.get("gestures", {});
        return name in chosen ? chosen[name] : Config.gestureDefaults[name];
    }

    function capital(name: string): string {
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    ColumnLayout {
        id: column
        width: page.width
        spacing: 14

        Heading {
            title: Lang.cfgGestures
            sub: Lang.cfgGesturesSub
        }

        Repeater {
            model: page.gestures

            Setting {
                required property string modelData

                title: Lang["cfgGesture" + page.capital(modelData)] ?? modelData
                sub: Lang["cfgGesture" + page.capital(modelData) + "Sub"] ?? ""

                Choice {
                    options: [{ value: null, label: Lang.cfgOff }, { value: 3, label: "3" }, { value: 4, label: "4" }, { value: 5, label: "5" }]
                    value: page.fingers(modelData)
                    onPicked: value => Machine.set("gestures." + modelData, value === Config.gestureDefaults[modelData] ? undefined : value)
                }
            }
        }
    }
}
