import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.theme

// Application icon, desaturated like Nothing's monochrome icon pack.
// It regains its colour when `colored` is true (selection, hover).
Item {
    id: root

    property string icon: ""
    property bool colored: false
    property int size: 32

    implicitWidth: size
    implicitHeight: size

    function resolve(name: string): string {
        if (!name) return Quickshell.iconPath("application-x-executable", true);
        if (name.startsWith("/")) return "file://" + name;
        if (name.indexOf("://") > 0) return name;
        return Quickshell.iconPath(name, true) || Quickshell.iconPath("application-x-executable", true);
    }

    IconImage {
        anchors.fill: parent
        source: root.resolve(root.icon)
        asynchronous: true

        layer.enabled: true
        layer.effect: MultiEffect {
            saturation: root.colored ? 0 : -1
            brightness: root.colored ? 0 : -0.05

            Behavior on saturation { NumberAnimation { duration: Tokens.animNormal } }
        }
    }
}
