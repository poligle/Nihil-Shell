pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.config

Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? true
    readonly property real micVolume: source?.audio?.volume ?? 0
    readonly property bool micMuted: source?.audio?.muted ?? true

    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)

    // A capture stream (Stream/Input/Audio) means the microphone is live.
    // Quickshell types it as Audio | Source | Stream, so it is the stream that
    // is *not* a sink: playback streams (Spotify...) are the sinks. Our own
    // visualiser and pavucontrol's meters don't count.
    readonly property bool micInUse: Pipewire.nodes.values.some(n =>
        n.audio && n.isStream && !n.isSink && !/cava|pavucontrol|quickshell/i.test(`${n.name} ${n.description}`))

    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    function setVolume(v: real): void {
        if (!sink?.audio) return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, v));
    }

    function toggleMute(): void {
        if (sink?.audio) sink.audio.muted = !sink.audio.muted;
    }

    function setMicVolume(v: real): void {
        if (!source?.audio) return;
        source.audio.muted = false;
        source.audio.volume = Math.max(0, Math.min(1, v));
        led.restart();
    }

    function toggleMic(): void {
        if (!source?.audio) return;
        source.audio.muted = !source.audio.muted;
        led.restart();
    }

    function setDefaultSink(node): void {
        Pipewire.preferredDefaultAudioSink = node;
    }

    // Keep the ThinkPad mic-mute LED in sync once PipeWire has applied the change.
    Timer {
        id: led
        interval: 200
        onTriggered: Quickshell.execDetached([Config.cmd.micLedSync])
    }
}
