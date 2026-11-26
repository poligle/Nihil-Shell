import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.config
import qs.services

// The interface in use, and what comes in and goes out: the Dashboard's and the desktop's. The
// rates keep their width; the interface's name gives way.
RowLayout {
    Layout.fillWidth: true

    Label {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        text: SysStats.iface || Lang.offline
    }

    Label { text: "↓ " + SysStats.human(SysStats.rx); color: Tokens.dim }
    Label { text: "↑ " + SysStats.human(SysStats.tx) }
}
