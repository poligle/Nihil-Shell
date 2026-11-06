import QtQuick
import Quickshell.Wayland

// Loaded by Frame.qml while the clipboard history is out: Hyprland's own
// keys wait while it has the keyboard (the frame window, set on load).
// Apart from Frame.qml because ShortcutInhibitor came with Quickshell 0.3.
ShortcutInhibitor {
    enabled: window !== null
}
