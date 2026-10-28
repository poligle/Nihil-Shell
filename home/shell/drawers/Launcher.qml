import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.theme
import qs.config
import qs.services
import qs.components

// Bottom drawer. Plain text searches apps (monochrome grid, colour on the
// selected one); ">" lists actions; "=" is a calculator (qalc).
//   arrows / tab  move     enter  open     esc  close
Item {
    id: root

    property bool active: false
    property string query: ""
    property string armed: ""
    property string result: ""

    readonly property string mode: query.startsWith(">") ? "actions" : query.startsWith("=") ? "calc" : "apps"
    readonly property string term: mode === "apps" ? query : query.slice(1).trim()

    readonly property var apps: mode === "apps" ? Apps.search(term) : []

    // `keys` keeps English words searchable whatever the language.
    readonly property var allActions: [
        { id: "lock", name: Lang.actLock, hint: Lang.hintSession, keys: "lock", glyph: Icons.lock, command: [Config.cmd.lock] },
        { id: "suspend", name: Lang.actSuspend, hint: Lang.hintSystem, keys: "sleep suspend", glyph: Icons.sleep, command: [Config.cmd.systemctl, "suspend"] },
        { id: "reboot", name: Lang.actReboot, hint: Lang.hintSystem, keys: "reboot restart", glyph: Icons.restart, command: [Config.cmd.systemctl, "reboot"], confirm: true },
        { id: "power", name: Lang.actPowerOff, hint: Lang.hintSystem, keys: "power off shutdown", glyph: Icons.power, command: [Config.cmd.powerOff], confirm: true, danger: true },
        { id: "logout", name: Lang.actLogout, hint: Lang.hintSession, keys: "logout exit", glyph: Icons.logout, command: [Config.cmd.uwsm, "stop"], confirm: true },
        { id: "next", name: Lang.actNextWallpaper, hint: Lang.hintWallpaper, keys: "wallpaper next", glyph: Icons.image, command: [Config.cmd.wallpaper, "next"] },
        { id: "prev", name: Lang.actPrevWallpaper, hint: Lang.hintWallpaper, keys: "wallpaper previous", glyph: Icons.image, command: [Config.cmd.wallpaper, "prev"] },
        { id: "dnd", name: Lang.actDnd, hint: Notifs.dnd ? Lang.hintOn : Lang.hintOff, keys: "dnd silent", glyph: Notifs.dnd ? Icons.bellOff : Icons.bell },
        { id: "night", name: Lang.actNight, hint: Toggles.night ? Lang.hintOn : Lang.hintOff, keys: "night light", glyph: Icons.night },
        { id: "terminal", name: Lang.actTerminal, hint: "kitty", glyph: Icons.terminal, command: [Config.cmd.terminal] }
    ].concat(Config.wallpapers.map(name => ({
        id: "wp-" + name, name: Lang.actWallpaper.arg(name), hint: Lang.hintWallpaper, keys: "wallpaper",
        glyph: Icons.image, command: [Config.cmd.wallpaper, "set", name]
    })))

    readonly property var actions: mode !== "actions" ? [] : allActions.filter(a =>
        !term || `${a.name} ${a.hint} ${a.keys ?? ""}`.toLowerCase().indexOf(term.toLowerCase()) >= 0)

    onActiveChanged: {
        if (active) {
            input.text = "";
            armed = "";
            result = "";
            grid.currentIndex = 0;
            list.currentIndex = 0;
            input.forceActiveFocus();
        }
    }

    // Read `query` itself here: derived bindings (mode, term) may not be
    // re-evaluated yet when this handler runs.
    onQueryChanged: {
        armed = "";
        grid.currentIndex = 0;
        list.currentIndex = 0;
        if (query.startsWith("=")) calcDelay.restart();
        else result = "";
    }

    function launch(entry): void {
        Drawers.close();
        Apps.launch(entry);
    }

    function runAction(action): void {
        if (!action) return;
        if (action.confirm && armed !== action.id) {
            armed = action.id;
            return;
        }
        Drawers.close();
        if (action.id === "dnd") Notifs.dnd = !Notifs.dnd;
        else if (action.id === "night") Toggles.night = !Toggles.night;
        else Quickshell.execDetached(action.command);
    }

    function accept(): void {
        if (mode === "apps" && apps.length > 0) launch(apps[Math.max(0, grid.currentIndex)]);
        else if (mode === "actions") runAction(actions[list.currentIndex]);
        else if (mode === "calc" && result) {
            Quickshell.execDetached([Config.cmd.wlCopy, result]);
            Drawers.close();
        }
    }

    function move(key): bool {
        if (mode === "apps") {
            if (key === Qt.Key_Right || key === Qt.Key_Tab) grid.moveCurrentIndexRight();
            else if (key === Qt.Key_Left || key === Qt.Key_Backtab) grid.moveCurrentIndexLeft();
            else if (key === Qt.Key_Down) grid.moveCurrentIndexDown();
            else if (key === Qt.Key_Up) grid.moveCurrentIndexUp();
            else return false;
            return true;
        }
        if (mode === "actions") {
            if (key === Qt.Key_Down || key === Qt.Key_Tab) list.incrementCurrentIndex();
            else if (key === Qt.Key_Up || key === Qt.Key_Backtab) list.decrementCurrentIndex();
            else return false;
            armed = "";
            return true;
        }
        return false;
    }

    // Calculator: qalc, debounced.
    Timer {
        id: calcDelay
        interval: 140
        onTriggered: {
            if (root.term === "") { root.result = ""; return; }
            calc.command = [Config.cmd.qalc, "-t", "--", root.term];
            calc.running = true;
        }
    }

    Process {
        id: calc
        stdout: StdioCollector {
            onStreamFinished: root.result = text.trim().split("\n").pop()
        }
    }

    // Search field
    Rectangle {
        id: search
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 24
        height: 48
        radius: 24
        color: Tokens.surface
        border.width: 1
        border.color: input.activeFocus ? Tokens.muted : Tokens.line

        Ico {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            glyph: root.mode === "calc" ? Icons.calculator : root.mode === "actions" ? Icons.chevron : Icons.search
            color: Tokens.muted
        }

        QQC.TextField {
            id: input
            anchors.left: searchIcon.right
            anchors.right: modeLabel.left
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            background: null
            color: Tokens.ink
            selectionColor: Tokens.ink
            selectedTextColor: Tokens.black
            objectName: "launcherSearch"
            placeholderText: Lang.search
            placeholderTextColor: Tokens.muted
            font.family: Tokens.fontMono
            font.pixelSize: 14
            onTextChanged: root.query = text
            onAccepted: root.accept()
            Keys.onEscapePressed: Drawers.close()
            Keys.onPressed: event => {
                if (root.move(event.key)) event.accepted = true;
            }
        }

        Label {
            id: modeLabel
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            text: root.mode === "apps" ? Lang.appsCount.arg(root.apps.length) : root.mode === "actions" ? Lang.actions : Lang.calculator
        }
    }

    // Apps
    GridView {
        id: grid
        anchors.top: search.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 24
        anchors.topMargin: 14
        anchors.bottomMargin: 10
        visible: root.mode === "apps"
        clip: true
        cellWidth: width / 7
        cellHeight: 112
        model: root.apps
        keyNavigationWraps: true
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0

        delegate: Item {
            id: cell

            required property var modelData
            required property int index

            readonly property bool selected: GridView.isCurrentItem

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: 18
                color: cell.selected ? Tokens.raised : "transparent"
                border.width: cell.selected ? 1 : 0
                border.color: Tokens.line
            }

            AppIcon {
                id: icon
                anchors.horizontalCenter: parent.horizontalCenter
                y: 18
                size: 46
                icon: cell.modelData.icon
                colored: cell.selected || area.containsMouse
            }

            Label {
                anchors.top: icon.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 16
                horizontalAlignment: Text.AlignHCenter
                text: cell.modelData.name
                color: cell.selected ? Tokens.ink : Tokens.muted
                font.letterSpacing: 0.8
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: grid.currentIndex = cell.index
                onClicked: root.launch(cell.modelData)
            }
        }
    }

    // Actions
    ListView {
        id: list
        anchors.top: search.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 24
        anchors.topMargin: 14
        anchors.bottomMargin: 10
        visible: root.mode === "actions"
        clip: true
        spacing: 2
        model: root.actions
        keyNavigationWraps: true
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0

        delegate: Rectangle {
            id: row

            required property var modelData
            required property int index

            readonly property bool selected: ListView.isCurrentItem
            readonly property bool isArmed: root.armed === modelData.id

            width: list.width
            height: 44
            radius: 14
            color: isArmed ? Tokens.interrupt : (selected ? Tokens.raised : "transparent")

            Ico {
                id: glyph
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                glyph: row.modelData.glyph
                color: row.isArmed ? Tokens.ink : (row.modelData.danger ? Tokens.interrupt : (row.selected ? Tokens.ink : Tokens.dim))
            }

            Txt {
                anchors.left: glyph.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.name
                color: row.selected || row.isArmed ? Tokens.ink : Tokens.dim
            }

            Label {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: row.isArmed ? Lang.enterAgain : row.modelData.hint
                color: row.isArmed ? Tokens.ink : Tokens.muted
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: list.currentIndex = row.index
                onClicked: root.runAction(row.modelData)
            }
        }
    }

    // Calculator
    Column {
        anchors.centerIn: grid
        visible: root.mode === "calc"
        spacing: 12

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.term || Lang.typeExpression
        }

        DotText {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, root.width - 80)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.result || "0"
            font.pixelSize: 56
            color: root.result ? Tokens.ink : Tokens.off
        }
    }

    Label {
        id: footer
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 18
        text: root.mode === "calc" ? Lang.hintCalc : Lang.hintApps
    }
}
