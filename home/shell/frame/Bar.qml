import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.services
import qs.components
import qs.nilo

// The left side of the frame: NixOS mark, workspaces, active app, tray,
// status, battery, clock and the privacy LED.
Item {
    id: root

    required property string output

    Column {
        anchors.top: parent.top
        anchors.topMargin: 16
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 22

        Ico {
            anchors.horizontalCenter: parent.horizontalCenter
            glyph: Icons.nix
            font.pixelSize: 20
            color: logo.containsMouse || Drawers.isOpen("launcher", root.output) ? Tokens.ink : Tokens.dim

            MouseArea {
                id: logo
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Drawers.toggle("launcher", root.output)
            }
        }

        Workspaces {
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    AppIcon {
        anchors.centerIn: parent
        size: 22
        icon: Apps.iconFor(ToplevelManager.activeToplevel?.appId ?? "")
        visible: (ToplevelManager.activeToplevel?.appId ?? "") !== ""
    }

    Column {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 18

        // Nilo is awake (its model takes memory) or downloading one.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 24
            height: 14
            visible: Nilo.enabled && (Nilo.loaded || Nilo.loading || Nilo.busy || (Nilo.pull !== null && Nilo.pull.status !== "error"))

            Eyes {
                anchors.centerIn: parent
                eyeWidth: 4
                eyeHeight: 11
                gap: 5
                mood: Nilo.busy ? (Nilo.phase === "writing" ? "writing" : "thinking") : Nilo.loading ? "waking"
                    : Nilo.loaded ? "idle" : "asleep"
                pulse: Nilo.pulse
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: Nilo.toggle()
            }
        }

        Tray {
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Status {
            anchors.horizontalCenter: parent.horizontalCenter
            output: root.output
        }

        BatteryGauge {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Battery.present
        }

        BarClock {
            anchors.horizontalCenter: parent.horizontalCenter
            output: root.output
        }

        // Privacy LED: something is recording the microphone.
        Rectangle {
            id: privacy
            anchors.horizontalCenter: parent.horizontalCenter
            width: 6
            height: 6
            radius: 3
            color: Tokens.interrupt
            visible: Audio.micInUse

            SequentialAnimation on opacity {
                running: privacy.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
            }
        }
    }
}
