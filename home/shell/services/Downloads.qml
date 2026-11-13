pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.config

// Downloads on the frame's light (services/Glyph.qml): while a browser has a
// file half written in the downloads folder, the light goes round. Zen and
// Firefox write it as name.part, Chromium as name.crdownload; neither says
// how big it will be, so how far is not known. When the last one goes the
// light just goes out: a download cancelled looks the same as one finished.
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

    // The downloads folder, as the session names it (Descargas in Spanish).
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
