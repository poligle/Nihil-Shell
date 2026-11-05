import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.theme
import qs.config
import qs.services
import qs.drawers
import qs.nilo

// One per output: a fullscreen, click-through layer that draws the frame and
// grows the drawers out of it. Only the bar, the open drawers and the
// notifications take input (see `mask`).
Scope {
    id: root

    required property ShellScreen modelData

    readonly property string output: modelData.name
    readonly property bool hasBar: Config.barOutputs.indexOf(output) >= 0
    readonly property int inset: hasBar ? Tokens.barWidth : Tokens.frameThickness
    readonly property int edge: Tokens.frameThickness

    Exclusions {
        screen: root.modelData
        inset: root.inset
        edge: root.edge
    }

    PanelWindow {
        id: win

        screen: root.modelData
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "nihil-frame"
        // OnDemand, not Exclusive: Hyprland drops every focus grab when a layer
        // turns exclusive (desktop/view/LayerSurface.cpp), which closed the
        // launcher and the panel the moment they opened. The grab below hands
        // the keyboard to this window instead. The launcher and the wallpapers
        // take it however they opened, so you can type (or pick) as soon as
        // they appear from the edge; the panel and the dashboard once they are
        // kept (the Wi-Fi password, a new task in the kanban).
        WlrLayershell.keyboardFocus: launcherOpen || wallOpen || ((panelOpen || dashOpen) && !Drawers.byHover)
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // Caffeine (services/Caffeine.qml): while it is on, hypridle waits.
        IdleInhibitor {
            window: win
            enabled: Caffeine.on
        }

        readonly property bool dashOpen: Drawers.isOpen("dashboard", root.output)
        readonly property bool panelOpen: Drawers.isOpen("panel", root.output)
        readonly property bool launcherOpen: Drawers.isOpen("launcher", root.output)
        readonly property bool wallOpen: Drawers.isOpen("wallpapers", root.output)
        readonly property bool clipOpen: Drawers.isOpen("clipboard", root.output)
        readonly property bool osdOpen: Osd.shown && Osd.screen === root.output && !panelOpen

        // Opening progress of each drawer (0 closed, 1 open).
        property real dashP: dashOpen ? 1 : 0
        property real panelP: panelOpen ? 1 : 0
        property real launcherP: launcherOpen ? 1 : 0
        property real wallP: wallOpen ? 1 : 0
        property real clipP: clipOpen ? 1 : 0
        property real osdP: osdOpen ? 1 : 0

        Behavior on dashP { NumberAnimation { duration: Tokens.animDrawer; easing.type: Easing.OutCubic } }
        Behavior on panelP { NumberAnimation { duration: Tokens.animDrawer; easing.type: Easing.OutCubic } }
        Behavior on launcherP { NumberAnimation { duration: Tokens.animDrawer; easing.type: Easing.OutCubic } }
        Behavior on wallP { NumberAnimation { duration: Tokens.animDrawer; easing.type: Easing.OutCubic } }
        Behavior on clipP { NumberAnimation { duration: Tokens.animDrawer; easing.type: Easing.OutCubic } }
        Behavior on osdP { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }

        // Content fades in at the end of the opening, like LEDs switching on.
        function reveal(p: real): real { return Math.max(0, (p - 0.55) / 0.45); }

        readonly property real innerW: width - root.inset - root.edge
        readonly property real centerX: root.inset + innerW / 2

        readonly property real dashW: Math.min(980, innerW - 120)
        // As deep as the dashboard asks: its kanban grows with the tasks.
        property real dashD: Math.min(dashboard.implicitHeight, height - 2 * root.edge - 96)
        Behavior on dashD { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }
        readonly property real panelL: Math.min(height - 2 * root.edge - 96, 860)
        readonly property real panelD: 400
        readonly property real launcherW: Math.min(860, innerW - 120)
        // Taller for Nilo ("?"), so the conversation has room.
        property real launcherD: launcher.niloMode ? Math.min(680, height - 2 * root.edge - 140) : 470
        Behavior on launcherD { NumberAnimation { duration: Tokens.animDrawer; easing.type: Easing.OutCubic } }
        // The wallpapers, side by side: as wide as they are, up to the launcher's room.
        readonly property real wallW: Math.min(innerW - 120, Math.max(460, Config.wallpapers.length * 222 + 34))
        readonly property real wallD: 214
        // The clipboard history, from the top: as deep as its copies.
        readonly property real clipW: Math.min(680, innerW - 120)
        property real clipD: Math.min(clipboard.implicitHeight, height - 2 * root.edge - 96)
        Behavior on clipD { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }
        readonly property real osdL: 300
        readonly property real osdD: 64

        // Nilo's panel, out of the bar next to its eyes (nilo/Peek.qml): its
        // middle at the eyes, never into the frame's corners.
        readonly property bool peekOpen: root.hasBar && Nilo.peeking && Nilo.peekScreen === root.output
            && Drawers.current === ""
        property real peekP: peekOpen ? 1 : 0
        Behavior on peekP { NumberAnimation { duration: Tokens.animDrawer; easing.type: Easing.OutCubic } }
        readonly property real peekD: 400
        readonly property real peekL: Math.min(peek.implicitHeight, height - 2 * root.edge - 2 * (Tokens.frameRadius + Tokens.fillet))
        readonly property real peekA: Math.max(root.edge + Tokens.frameRadius + Tokens.fillet,
            Math.min(barHit.eyesY - peekL / 2, height - root.edge - Tokens.frameRadius - Tokens.fillet - peekL))

        readonly property var bumps: [
            { edge: 0, a: centerX - dashW / 2, b: centerX + dashW / 2, d: dashD * dashP },
            { edge: 0, a: centerX - clipW / 2, b: centerX + clipW / 2, d: clipD * clipP },
            { edge: 1, a: root.edge, b: root.edge + panelL, d: panelD * panelP },
            { edge: 1, a: height / 2 - osdL / 2, b: height / 2 + osdL / 2, d: panelP > 0 ? 0 : osdD * osdP },
            { edge: 2, a: centerX - launcherW / 2, b: centerX + launcherW / 2, d: launcherD * launcherP },
            { edge: 2, a: centerX - wallW / 2, b: centerX + wallW / 2, d: wallD * wallP },
            { edge: 3, a: peekA, b: peekA + peekL, d: peekD * peekP }
        ]

        mask: Region {
            regions: [
                Region { item: barHit },
                Region { item: hotZone },
                Region { item: cornerZone },
                Region { item: bottomZone },
                Region { item: dashHit },
                Region { item: panelHit },
                Region { item: launcherHit },
                Region { item: wallHit },
                Region { item: clipHit },
                Region { item: peekHit },
                Region { item: popups }
            ]
        }

        // Clicking outside an open drawer closes it. The dashboard and the
        // panel opened by hovering leave the keyboard where it was; all of
        // them close when the pointer leaves, unless a click or a key (the
        // launcher) kept them.
        HyprlandFocusGrab {
            windows: [win]
            active: win.launcherOpen || win.wallOpen || ((win.panelOpen || win.dashOpen) && !Drawers.byHover)
            onCleared: Drawers.close()
        }

        Item {
            id: scene
            anchors.fill: parent

            // Dim the desktop behind the launcher; clicking it closes.
            Rectangle {
                anchors.fill: parent
                color: Tokens.black
                opacity: 0.5 * win.launcherP
                visible: opacity > 0
            }

            MouseArea {
                id: launcherHit
                width: win.launcherOpen ? parent.width : 0
                height: win.launcherOpen ? parent.height : 0
                onClicked: Drawers.close()
            }

            FrameShape {
                anchors.fill: parent
                inset: root.inset
                edge: root.edge
                bumps: win.bumps
            }

            GlyphLight {
                anchors.fill: parent
                inset: root.inset
                edge: root.edge
            }

            Bar {
                id: barHit
                visible: root.hasBar
                x: 0
                y: 0
                width: root.hasBar ? root.inset : 0
                height: parent.height
                output: root.output
            }

            // Dashboard: from the top edge, opened by hovering it or SUPER+D.
            MouseArea {
                id: hotZone
                x: win.centerX - win.dashW / 2
                y: 0
                width: win.dashW
                height: Drawers.current === "" || (win.dashOpen && Drawers.byHover) ? root.edge + 3 : 0
                hoverEnabled: true
                onContainsMouseChanged: containsMouse ? hoverOpen.restart() : hoverClose.restart()
            }

            Item {
                id: dashHit
                x: win.centerX - win.dashW / 2
                y: 0
                width: win.dashP > 0 ? win.dashW : 0
                height: root.edge + win.dashD * win.dashP

                HoverHandler {
                    id: dashHover
                    onHoveredChanged: if (!hovered) hoverClose.restart()
                }

                Item {
                    y: root.edge
                    width: parent.width
                    height: win.dashD * win.dashP
                    clip: true

                    Dashboard {
                        id: dashboard
                        width: win.dashW
                        height: win.dashD
                        anchors.bottom: parent.bottom
                        active: win.dashOpen
                        opacity: win.reveal(win.dashP)
                    }
                }

                // A click inside keeps a dashboard opened by hovering, and lets
                // it take the keyboard. The press goes on to the dashboard.
                MouseArea {
                    anchors.fill: parent
                    enabled: win.dashOpen && Drawers.byHover
                    onPressed: mouse => {
                        Drawers.byHover = false;
                        mouse.accepted = false;
                    }
                }
            }

            // The clipboard history (services/Clipboard.qml): from the top
            // too, while its modifier is held. It never takes the keyboard,
            // so the paste lands in the window that had it.
            Item {
                id: clipHit
                x: win.centerX - win.clipW / 2
                y: 0
                width: win.clipP > 0 ? win.clipW : 0
                height: root.edge + win.clipD * win.clipP

                Item {
                    y: root.edge
                    width: parent.width
                    height: win.clipD * win.clipP
                    clip: true

                    ClipboardView {
                        id: clipboard
                        width: win.clipW
                        height: win.clipD
                        anchors.bottom: parent.bottom
                        active: win.clipOpen
                        opacity: win.reveal(win.clipP)
                    }
                }
            }

            Timer {
                id: hoverOpen
                interval: 160
                onTriggered: {
                    if (hotZone.containsMouse && Drawers.current === "")
                        Drawers.open("dashboard", root.output, true);
                }
            }

            Timer {
                id: hoverClose
                interval: 420
                onTriggered: {
                    if (!Drawers.byHover)
                        return;
                    if ((win.dashOpen && !hotZone.containsMouse && !dashHover.hovered)
                            || (win.panelOpen && !cornerZone.containsMouse && !panelHover.hovered)
                            || (win.launcherOpen && !bottomZone.containsMouse && !launcherHover.hovered))
                        Drawers.close();
                }
            }

            // The settings panel also opens by resting the pointer in the
            // top-right corner for a moment. The zone stays inside the frame.
            MouseArea {
                id: cornerZone
                x: win.width - width
                y: 0
                width: 14
                height: Drawers.current === "" ? 14 : 0
                hoverEnabled: true
                onContainsMouseChanged: containsMouse ? cornerOpen.restart() : hoverClose.restart()
            }

            Timer {
                id: cornerOpen
                interval: 400
                onTriggered: {
                    if (cornerZone.containsMouse && Drawers.current === "")
                        Drawers.open("panel", root.output, true);
                }
            }

            // Control panel: from the top-right corner, opened from the status
            // icons, SUPER+P or by resting the pointer in the corner.
            Item {
                id: panelHit
                x: win.width - root.edge - win.panelD * win.panelP
                y: 0
                width: win.panelP > 0 ? win.panelD * win.panelP + root.edge : 0
                height: root.edge + win.panelL
                clip: true

                HoverHandler {
                    id: panelHover
                    onHoveredChanged: if (!hovered) hoverClose.restart()
                }

                Panel {
                    y: root.edge
                    width: win.panelD
                    height: win.panelL
                    active: win.panelOpen
                    opacity: win.reveal(win.panelP)
                }

                // A click inside keeps a panel opened by hovering, as if it
                // had been opened on purpose. The press goes on to the panel.
                MouseArea {
                    anchors.fill: parent
                    enabled: win.panelOpen && Drawers.byHover
                    onPressed: mouse => {
                        Drawers.byHover = false;
                        mouse.accepted = false;
                    }
                }
            }

            // On-screen display: from the middle of the right edge.
            Item {
                x: win.width - root.edge - win.osdD * win.osdP
                y: win.height / 2 - win.osdL / 2
                width: win.osdD * win.osdP
                height: win.osdL
                clip: true
                visible: win.osdP > 0 && win.panelP === 0

                OsdView {
                    width: win.osdD
                    height: win.osdL
                    opacity: win.reveal(win.osdP)
                }
            }

            // Launcher: from the bottom edge, SUPER+Space, three fingers up or
            // resting the pointer on the middle of the bottom edge.
            Item {
                x: win.centerX - win.launcherW / 2
                y: win.height - root.edge - win.launcherD * win.launcherP
                width: win.launcherW
                height: win.launcherD * win.launcherP
                clip: true

                HoverHandler {
                    id: launcherHover
                    onHoveredChanged: if (!hovered) hoverClose.restart()
                }

                Launcher {
                    id: launcher
                    width: win.launcherW
                    height: win.launcherD
                    active: win.launcherOpen
                    opacity: win.reveal(win.launcherP)
                }

                // Opened by hovering, it takes the keyboard but closes when the
                // pointer leaves; a click inside (or a key, Launcher.qml) keeps
                // it open, as if it had come from SUPER+Space. The press goes on
                // to the launcher.
                MouseArea {
                    anchors.fill: parent
                    enabled: win.launcherOpen && Drawers.byHover
                    onPressed: mouse => {
                        Drawers.byHover = false;
                        mouse.accepted = false;
                    }
                }
            }

            // Wallpapers (SUPER + W): from the bottom edge too, where the
            // launcher comes out, while the desktop shows each one at once.
            Item {
                id: wallHit
                x: win.centerX - win.wallW / 2
                y: win.height - root.edge - win.wallD * win.wallP
                width: win.wallP > 0 ? win.wallW : 0
                height: win.wallD * win.wallP
                clip: true

                WallpaperPicker {
                    width: win.wallW
                    height: win.wallD
                    active: win.wallOpen
                    opacity: win.reveal(win.wallP)
                }
            }

            // The zone sits on the edge itself, under the launcher's footprint.
            // The pointer has to rest there a moment: it often lands on the
            // bottom edge on its way to a window's status bar.
            MouseArea {
                id: bottomZone
                x: win.centerX - win.launcherW / 2
                y: win.height - height
                width: win.launcherW
                height: Drawers.current === "" || (win.launcherOpen && Drawers.byHover) ? root.edge + 3 : 0
                hoverEnabled: true
                onContainsMouseChanged: containsMouse ? bottomOpen.restart() : hoverClose.restart()
            }

            Timer {
                id: bottomOpen
                interval: 350
                onTriggered: {
                    if (bottomZone.containsMouse && Drawers.current === "")
                        Drawers.open("launcher", root.output, true);
                }
            }

            // Nilo's panel grows from the bar to the right, its content
            // sliding out with it.
            Item {
                id: peekHit
                x: root.inset
                y: win.peekA
                width: win.peekP > 0 ? win.peekD * win.peekP : 0
                height: win.peekL
                clip: true

                Peek {
                    id: peek
                    shown: win.peekOpen
                    anchors.right: parent.right
                    width: win.peekD
                    height: win.peekL
                    opacity: win.reveal(win.peekP)
                }
            }

            Popups {
                id: popups
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: root.edge + 14
                anchors.rightMargin: root.edge + 14
                output: root.output
                suppressed: win.panelP > 0
            }
        }
    }
}
