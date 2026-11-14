pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    property string folder: ""
    readonly property bool active: root.folder !== "" && partial.count > 0

    onActiveChanged: {
        if (root.active)
            Glyph.track("downloads", -1);
        else
            Glyph.finish("downloads", "quiet");
    }

    FolderListModel {
        id: partial
        folder: root.folder !== "" ? "file://" + root.folder : ""
        nameFilters: ["*.part", "*.crdownload"]
        showDirs: false
        showHidden: true
    }

    Process {
        running: true
        command: [Config.cmd.xdgUserDir, "DOWNLOAD"]
        stdout: StdioCollector {
            onStreamFinished: {
                const dir = text.trim();
                const home = Quickshell.env("HOME");
                root.folder = dir !== "" && dir !== home ? dir : home + "/Downloads";
            }
        }
    }
}
