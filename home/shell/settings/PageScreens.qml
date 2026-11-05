import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.theme
import qs.config
import qs.services
import qs.components

// The screens: each one connected (Hyprland says which, and its modes) with
// its mode, scale, rotation and place, whether the bar is on it, and which
// is the main one (the desktop widgets, the lock screen, the login). They
// go in settings.json's "outputs" (modules/nihil.nix), with the size of the
// screen in pixels, turned, for its wallpapers; applying rebuilds, and only
// the wallpapers for a size that changed are drawn again. One saved but not
// connected now can be forgotten.
Flickable {
    id: page

    property var monitors: []       // hyprctl monitors all -j
    property bool loaded: false

    readonly property var saved: Machine.get("outputs", ({}))
    readonly property string main: Machine.get("primaryOutput", Config.primaryOutput)
    readonly property var away: Object.keys(saved).filter(name => !monitors.some(monitor => monitor.name === name))

    readonly property var rotations: [{ value: 0, label: "0°" }, { value: 1, label: "90°" }, { value: 2, label: "180°" }, { value: 3, label: "270°" }]
    readonly property var places: [
        { value: "auto", label: Lang.cfgScreenAuto }, { value: "auto-left", label: Lang.cfgScreenLeft },
        { value: "auto-right", label: Lang.cfgScreenRight }, { value: "auto-up", label: Lang.cfgScreenAbove },
        { value: "auto-down", label: Lang.cfgScreenBelow }
    ]

    contentHeight: column.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // "2880x1800@120.00Hz" → { width, height, rate, mode: "2880x1800@120" }
    function parseMode(text: string): var {
        const m = /^(\d+)x(\d+)@([\d.]+)/.exec(String(text));
        if (!m)
            return null;
        const rate = Math.round(Number(m[3]) * 100) / 100;
        return { width: Number(m[1]), height: Number(m[2]), rate: rate, mode: m[1] + "x" + m[2] + "@" + rate };
    }

    // Its modes, largest and fastest first, each once; "preferred" before them.
    function modesOf(monitor: var): var {
        const seen = {};
        const found = (monitor.availableModes ?? []).map(text => parseMode(text)).filter(mode => {
            if (mode === null || seen[mode.mode])
                return false;
            seen[mode.mode] = true;
            return true;
        });
        found.sort((a, b) => b.width * b.height - a.width * a.height || b.rate - a.rate);
        return ["preferred"].concat(found.map(mode => mode.mode));
    }

    function modeLabel(mode: string): string {
        const m = parseMode(mode);
        return m === null ? Lang.cfgScreenPreferred : m.width + " × " + m.height + " · " + Math.round(m.rate) + " Hz";
    }

    // Scales that leave whole pixels, as Hyprland wants.
    function scalesFor(width: int, height: int): var {
        return [1, 1.25, 1.5, 1.6, 1.75, 2, 2.5, 3].filter(scale => {
            const w = width / scale, h = height / scale;
            return Math.abs(w - Math.round(w)) < 0.001 && Math.abs(h - Math.round(h)) < 0.001;
        });
    }

    function entry(name: string): var {
        return saved[name] ?? ({});
    }

    // A change to one screen: its size for the wallpapers follows its mode
    // (or the one it has now, for "preferred") and its rotation.
    function write(monitor: var, change: var): void {
        const next = Object.assign({}, entry(monitor.name), change);
        const mode = next.mode && next.mode !== "preferred" ? parseMode(next.mode) : null;
        const width = mode ? mode.width : (monitor.width ?? next.width ?? 1920);
        const height = mode ? mode.height : (monitor.height ?? next.height ?? 1080);
        const turned = [1, 3, 5, 7].indexOf(next.transform ?? 0) >= 0;
        next.width = turned ? height : width;
        next.height = turned ? width : height;
        Machine.set("outputs." + monitor.name, next);
    }

    function step(monitor: var, by: int): void {
        const modes = modesOf(monitor);
        const now = Math.max(0, modes.indexOf(entry(monitor.name).mode ?? "preferred"));
        write(monitor, { mode: modes[(now + by + modes.length) % modes.length] });
    }

    Process {
        id: reader
        command: [Config.cmd.hyprctl, "monitors", "all", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.monitors = JSON.parse(text).sort((a, b) => a.x - b.x || a.y - b.y);
                } catch (error) {
                    page.monitors = [];
                }
                page.loaded = true;
            }
        }
    }

    ColumnLayout {
        id: column
        width: page.width
        spacing: 14

        Heading {
            title: Lang.cfgScreens
            sub: Lang.cfgScreensSub
        }

        Txt {
            visible: page.loaded && page.monitors.length === 0
            text: Lang.cfgScreenNone
            color: Tokens.muted
            font.pixelSize: 13
        }

        Repeater {
            model: page.monitors

            ColumnLayout {
                id: monitor

                required property var modelData

                readonly property var saved: page.entry(modelData.name)
                readonly property var mode: page.parseMode(saved.mode ?? "") ?? ({ width: modelData.width, height: modelData.height })

                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 6

                // Its name, what it is, and whether it is the main one or off.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Ico {
                        glyph: Icons.monitor
                        color: Tokens.dim
                    }

                    Txt {
                        text: monitor.modelData.name
                        font.pixelSize: 16
                    }

                    Label {
                        Layout.fillWidth: true
                        text: [monitor.modelData.make, monitor.modelData.model].filter(part => part).join(" ")
                    }

                    Label {
                        visible: monitor.modelData.disabled === true
                        text: Lang.cfgScreenOff
                        color: Tokens.dim
                    }
                }

                Setting {
                    title: Lang.cfgScreenMode

                    Row {
                        spacing: 10

                        CircleButton {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 26
                            glyph: Icons.chevronLeft
                            onClicked: page.step(monitor.modelData, -1)
                        }

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 170
                            horizontalAlignment: Text.AlignHCenter
                            text: page.modeLabel(monitor.saved.mode ?? "preferred")
                            font.family: Tokens.fontMono
                            font.pixelSize: 12
                        }

                        CircleButton {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 26
                            glyph: Icons.chevron
                            onClicked: page.step(monitor.modelData, 1)
                        }
                    }
                }

                Setting {
                    title: Lang.cfgScreenScale

                    Choice {
                        options: page.scalesFor(monitor.mode.width, monitor.mode.height).map(scale => ({ value: scale, label: String(scale) }))
                        value: monitor.saved.scale ?? 1
                        onPicked: value => page.write(monitor.modelData, { scale: value })
                    }
                }

                Setting {
                    title: Lang.cfgScreenRotation

                    Choice {
                        options: page.rotations
                        value: monitor.saved.transform ?? 0
                        onPicked: value => page.write(monitor.modelData, { transform: value })
                    }
                }

                Setting {
                    visible: page.monitors.length > 1
                    title: Lang.cfgScreenPlace

                    Choice {
                        options: page.places
                        value: monitor.saved.position ?? "auto"
                        onPicked: value => page.write(monitor.modelData, { position: value })
                    }
                }

                Setting {
                    title: Lang.cfgScreenBar
                    sub: Lang.cfgScreenBarSub

                    Toggle {
                        on: monitor.saved.bar ?? true
                        onToggled: page.write(monitor.modelData, { bar: !on })
                    }
                }

                Setting {
                    visible: page.monitors.length > 1
                    title: Lang.cfgScreenMain
                    sub: Lang.cfgScreenMainSub

                    Toggle {
                        on: page.main === monitor.modelData.name
                        onToggled: {
                            if (on)
                                return;
                            // The main one has to be among the outputs.
                            if (!(monitor.modelData.name in page.saved))
                                page.write(monitor.modelData, {});
                            Machine.set("primaryOutput", monitor.modelData.name);
                        }
                    }
                }
            }
        }

        // Saved, but not connected now.
        Repeater {
            model: page.loaded ? page.away : []

            Setting {
                id: gone

                required property string modelData

                Layout.topMargin: 10
                title: gone.modelData
                sub: Lang.cfgScreenAway

                PillButton {
                    visible: gone.modelData !== page.main
                    text: Lang.cfgScreenForget
                    onClicked: Machine.set("outputs." + gone.modelData, undefined)
                }
            }
        }
    }
}
