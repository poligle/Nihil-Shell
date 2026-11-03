import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.theme
import qs.config
import qs.services
import qs.components

// The wallpaper, quickly (SUPER + W): the arrows show each at once, Enter
// or a click keeps it, Escape goes back to the one there was. The lock
// screen and the login follow it (nihil-wallpaper).
Scope {
    PanelWindow {
        id: win

        property string before: ""
        property int index: 0
        readonly property var names: Config.wallpapers
        readonly property var target: {
            const screens = Quickshell.screens;
            for (let i = 0; i < screens.length; i++) {
                if (screens[i].name === Machine.screen)
                    return screens[i];
            }
            return screens.length > 0 ? screens[0] : null;
        }

        function show(i: int): void {
            win.index = (i + win.names.length) % win.names.length;
            Machine.liveWallpaper(win.names[win.index]);
        }

        visible: Machine.picking && target !== null
        screen: target
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "nihil-wallpapers"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        onVisibleChanged: {
            if (visible) {
                before = Machine.wallpaper;
                index = Math.max(0, names.indexOf(before));
                keys.forceActiveFocus();
            }
        }

        HyprlandFocusGrab {
            windows: [win]
            active: win.visible
            onCleared: Machine.picking = false
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Machine.picking = false
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onLeftPressed: win.show(win.index - 1)
            Keys.onRightPressed: win.show(win.index + 1)
            Keys.onReturnPressed: Machine.picking = false
            Keys.onEscapePressed: {
                Machine.liveWallpaper(win.before);
                Machine.picking = false;
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 72
            width: Math.min(parent.width - 120, win.names.length * 222 + 26)
            height: 196
            radius: Tokens.drawerRadius
            color: Tokens.black
            border.width: 1
            border.color: Tokens.line

            MouseArea {
                anchors.fill: parent
            }

            Label {
                x: 20
                y: 14
                text: Lang.wpHint
            }

            ListView {
                anchors.fill: parent
                anchors.margins: 20
                anchors.topMargin: 40
                orientation: ListView.Horizontal
                spacing: 14
                clip: true
                model: win.names
                currentIndex: win.index
                highlightMoveDuration: Tokens.animFast

                delegate: Rectangle {
                    id: card

                    required property string modelData
                    required property int index

                    width: 208
                    height: 132
                    radius: 14
                    color: Tokens.surface
                    border.width: card.index === win.index ? 2 : 1
                    border.color: card.index === win.index ? Tokens.ink : Tokens.line

                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        source: "file://" + Config.wallpaperDir + "/" + card.modelData + "/" + Config.primaryOutput + ".png"
                        sourceSize.width: 416
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    Label {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 10
                        text: card.modelData
                        color: card.index === win.index ? Tokens.ink : Tokens.dim
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            win.show(card.index);
                            Machine.picking = false;
                        }
                    }
                }
            }
        }
    }
}
