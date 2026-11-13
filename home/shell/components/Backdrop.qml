import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.config
import qs.services

// What is behind a window, for its smoked glass (components/Surface.qml,
// frame/FrameGlass.qml): the output's own wallpaper render, which awww shows
// dot for dot, and, while `windows` is on, the windows of the screen's
// workspace where they are, captured live (Quickshell's screencopy) and laid
// in the order Hyprland draws them: tiled, floating (the last used on top),
// fullscreen, the special workspace's over them. Either is one texture with
// its mipmaps, which the frost reads blurred: the wallpaper alone, or all of
// it drawn into one (a ShaderEffectSource) while there are windows. A window
// that wants glass keeps one and points `glassBackdrop` at it on an item that
// holds everything else; Surfaces find it there. It is a pixel wide and
// clipped: it draws nothing of its own but keeps its texture.
//
// Hyprland's own layers can't be the source: the frame would see itself, and
// a layer kept out of screen sharing (no_screen_share) is captured black.
Item {
    id: root

    required property string output
    // Where the window starts on its screen, and the screen's size, in logical px.
    property vector2d origin: Qt.vector2d(0, 0)
    property vector2d screenSize: Qt.vector2d(1, 1)
    // How much of what is behind reaches the glass: less under a dim.
    property real dim: 1
    // The windows too, not only the wallpaper: while some glass can be over
    // one (services/Glass.qml asks Hyprland where they are more often then).
    property bool windows: false

    readonly property Item texture: wall.status !== Image.Ready ? null : root.windows ? shot : wall
    readonly property string name: Machine.wallpaper !== "" ? Machine.wallpaper : Machine.get("wallpaper", "night")
    readonly property var monitor: Hyprland.monitors.values.find(m => m.name === root.output) ?? null
    readonly property var special: Glass.specialOf(root.monitor)

    width: 1
    height: 1
    clip: true

    // services/Glass.qml counts the backdrops that show windows.
    property bool counted: false
    function count(showing: bool): void {
        if (showing === root.counted)
            return;
        root.counted = showing;
        Glass.live += showing ? 1 : -1;
    }
    onWindowsChanged: root.count(root.windows)
    Component.onCompleted: root.count(root.windows)
    Component.onDestruction: root.count(false)

    onNameChanged: wall.primary = false

    // A window where it is on the screen (its own ids only: the screen and
    // whether to capture come in).
    component Shown: ScreencopyView {
        id: shown

        required property var modelData
        property var monitor: null
        property bool capture: false
        // Over the workspace's windows, for the special workspace's. (Not
        // `layer`: every Item has that one already, layer.enabled and the rest.)
        property int above: 0

        readonly property var ipc: shown.modelData?.lastIpcObject ?? ({})
        readonly property rect place: Glass.place(shown.modelData, shown.monitor)

        x: shown.place.x
        y: shown.place.y
        width: shown.place.width
        height: shown.place.height
        visible: shown.place.width > 0 && shown.place.height > 0
        z: shown.above + ((shown.ipc.fullscreen ?? 0) > 0 ? 1500
            : shown.ipc.floating ? 1000 - Math.min(shown.ipc.focusHistoryID ?? 0, 999) : 0)
        captureSource: (shown.capture && shown.visible) ? (shown.modelData?.wayland ?? null) : null
        live: true
    }

    Item {
        id: scene

        width: root.screenSize.x
        height: root.screenSize.y

        Image {
            id: wall

            // An output without a render of its own shows the primary one's (nihil-wallpaper).
            property bool primary: false

            anchors.fill: parent
            asynchronous: true
            smooth: true
            mipmap: true
            source: "file://" + Config.wallpaperDir + "/" + root.name + "/" + (primary ? Config.primaryOutput : root.output) + ".png"
            onStatusChanged: {
                if (status === Image.Error && !primary)
                    primary = true;
            }
        }

        Repeater {
            model: root.windows && root.monitor?.activeWorkspace ? root.monitor.activeWorkspace.toplevels : null
            delegate: Shown {
                monitor: root.monitor
                capture: root.windows
            }
        }

        // The special workspace, when it is out on this screen: over the rest.
        Repeater {
            model: root.windows && root.special ? root.special.toplevels : null
            delegate: Shown {
                monitor: root.monitor
                capture: root.windows
                above: 2000
            }
        }
    }

    ShaderEffectSource {
        id: shot

        width: 1
        height: 1
        sourceItem: root.windows ? scene : null
        hideSource: true
        live: true
        mipmap: true
        smooth: true
    }
}
