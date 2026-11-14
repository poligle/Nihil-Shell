import QtQuick
import qs.theme
import qs.config
import qs.services
import qs.components

Column {
    id: root

    property int current: -1
    property string asking: ""

    readonly property string repo: Nilo.settings.repo ?? "~/nixos-config"
    readonly property var items: [
        { key: "web", title: Lang.accessWeb, sub: Lang.accessWebSub, guard: "" },
        { key: "system", title: Lang.accessSystem, sub: Lang.accessSystemSub, guard: "" },
        { key: "apps", title: Lang.accessApps, sub: Lang.accessAppsSub, guard: "" },
        { key: "write", title: Lang.accessWrite, sub: Lang.accessWriteSub.arg(repo), guard: Lang.accessWriteGuard.arg(repo) },
        { key: "git", title: Lang.accessGit, sub: Lang.accessGitSub.arg(repo), guard: Lang.accessGitGuard.arg(repo) },
        { key: "shell", title: Lang.accessShell, sub: Lang.accessShellSub, guard: Lang.accessShellGuard }
    ]
    readonly property int count: items.length

    signal grew(Item row)

    spacing: 2

    onVisibleChanged: if (!visible) asking = ""

    function toggle(index: int): void {
        const item = items[index];
        if (!item) return;
        const on = Nilo.settings[item.key] === true;
        if (on || item.guard === "" || asking === item.key) {
            Nilo.set(item.key, !on);
            asking = "";
        } else {
            asking = item.key;
        }
    }

    function authorize(): void {
        const index = items.findIndex(item => item.key === asking);
        if (index >= 0) toggle(index);
    }

    function moveBy(step: int): void {
        current = current < 0 ? 0 : Math.max(0, Math.min(count - 1, current + step));
        if (asking !== "" && items[current].key !== asking) asking = "";
    }

    function rowAt(index: int): Item {
        return rows.itemAt(index);
    }

    Repeater {
        id: rows
        model: root.items

        SwitchRow {
            id: row

            required property var modelData
            required property int index

            width: root.width
            title: modelData.title
            sub: modelData.sub
            guard: root.asking === modelData.key ? modelData.guard : ""
            on: Nilo.settings[modelData.key] === true
            current: root.current === index

            onHeightChanged: if (asking) root.grew(row)
            onToggled: {
                root.current = row.index;
                root.toggle(row.index);
            }
            onCancelled: root.asking = ""
        }
    }
}
