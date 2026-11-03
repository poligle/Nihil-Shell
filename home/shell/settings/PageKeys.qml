import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.config
import qs.services
import qs.components

// The keys of NIHIL's actions (modules/binds.nix). Hyprland catches a bound
// key before any window sees it, so a combination is put together here
// rather than pressed: modifiers and a key name. Workspaces (SUPER + a
// digit, with SHIFT to move a window there) and the media keys stay.
Flickable {
    id: page

    readonly property var order: ["terminal", "launcher", "dashboard", "panel", "settings", "wallpapers", "files", "browser", "notes",
        "code", "music", "pixels", "colourPicker", "lock", "nilo", "close", "float", "maximize", "fullscreen", "special",
        "toSpecial", "nextWorkspace", "screenshot"]
    readonly property var actions: order.filter(name => name in Config.bindDefaults && (name !== "nilo" || Config.nilo.enabled))
    readonly property var modifiers: ["SUPER", "SHIFT", "CTRL", "ALT"]
    readonly property var keyName: /^([A-Za-z0-9]|F([1-9]|1[0-9]|2[0-4])|Return|Space|Tab|Escape|BackSpace|Delete|Insert|Home|End|Prior|Next|PRINT|Print|comma|period|slash|minus|equal|semicolon|apostrophe|grave|backslash|bracketleft|bracketright|Super_L|Super_R)$/

    property string editing: ""
    property var mods: []
    property string key: ""
    property string error: ""

    contentHeight: column.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function keyOf(name: string): var {
        const binds = Machine.get("binds", {});
        return name in binds ? binds[name] : Config.bindDefaults[name];
    }

    function label(name: string): string {
        return Lang["bind" + name.charAt(0).toUpperCase() + name.slice(1)] ?? name;
    }

    // The same combination however it is written: parts in any order, any case.
    function normal(combo: string): string {
        return combo.split("+").map(part => part.trim().toUpperCase()).filter(part => part !== "")
            .map(part => part === "CONTROL" ? "CTRL" : part).sort().join("+");
    }

    function reserved(combo: string): bool {
        const wanted = normal(combo);
        for (let digit = 0; digit <= 9; digit++) {
            if (wanted === normal("SUPER + " + digit) || wanted === normal("SUPER + SHIFT + " + digit))
                return true;
        }
        return false;
    }

    function owner(combo: string, except: string): string {
        const wanted = normal(combo);
        for (let i = 0; i < page.actions.length; i++) {
            const name = page.actions[i];
            const taken = keyOf(name);
            if (name !== except && taken !== null && taken !== undefined && normal(taken) === wanted)
                return name;
        }
        return "";
    }

    function edit(name: string): void {
        if (page.editing === name) {
            page.editing = "";
            return;
        }
        const combo = keyOf(name);
        const parts = combo ? combo.split("+").map(part => part.trim()) : [];
        page.mods = parts.map(part => part.toUpperCase() === "CONTROL" ? "CTRL" : part.toUpperCase())
            .filter(part => page.modifiers.indexOf(part) >= 0);
        page.key = parts.filter(part => page.modifiers.indexOf(part.toUpperCase() === "CONTROL" ? "CTRL" : part.toUpperCase()) < 0).join(" + ");
        page.error = "";
        page.editing = name;
    }

    function toggleMod(mod: string): void {
        page.mods = page.mods.indexOf(mod) >= 0 ? page.mods.filter(other => other !== mod) : page.mods.concat([mod]);
    }

    function save(name: string): void {
        const key = page.key.trim();
        if (!page.keyName.test(key)) {
            page.error = Lang.cfgKeyInvalid;
            return;
        }
        if (page.mods.length === 0 && !/^(PRINT|Print|F[0-9]+)$/.test(key)) {
            page.error = Lang.cfgKeyNeedsMod;
            return;
        }
        const combo = page.modifiers.filter(mod => page.mods.indexOf(mod) >= 0).concat([key]).join(" + ");
        if (reserved(combo)) {
            page.error = Lang.cfgKeyReserved;
            return;
        }
        const other = owner(combo, name);
        if (other !== "") {
            page.error = Lang.cfgKeyTaken.arg(label(other));
            return;
        }
        const fallback = Config.bindDefaults[name];
        Machine.set("binds." + name, fallback && normal(fallback) === normal(combo) ? undefined : combo);
        page.editing = "";
    }

    function reset(name: string): void {
        Machine.set("binds." + name, undefined);
        page.editing = "";
    }

    function remove(name: string): void {
        Machine.set("binds." + name, Config.bindDefaults[name] === null ? undefined : null);
        page.editing = "";
    }

    ColumnLayout {
        id: column
        width: page.width
        spacing: 0

        Heading {
            Layout.bottomMargin: 12
            title: Lang.cfgKeys
            sub: Lang.cfgKeysSub
        }

        Repeater {
            model: page.actions

            Item {
                id: row

                required property string modelData
                readonly property var combo: page.keyOf(modelData)
                readonly property bool open: page.editing === modelData

                Layout.fillWidth: true
                implicitHeight: 44 + (open ? editor.implicitHeight + 14 : 0)

                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: row.open ? Tokens.surface : (rowArea.containsMouse ? Tokens.surface : "transparent")
                }

                Item {
                    id: line
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 44

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 14
                        text: page.label(row.modelData)
                        color: row.open ? Tokens.ink : Tokens.dim
                    }

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        text: row.combo === null || row.combo === undefined ? Lang.cfgKeyNone : row.combo
                        color: row.combo === null || row.combo === undefined ? Tokens.muted : Tokens.ink
                        font.family: Tokens.fontMono
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.edit(row.modelData)
                    }
                }

                Column {
                    id: editor
                    visible: row.open
                    anchors.top: line.bottom
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    spacing: 10

                    Flow {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: page.modifiers

                            PillButton {
                                required property string modelData

                                text: modelData
                                accent: page.mods.indexOf(modelData) >= 0
                                onClicked: page.toggleMod(modelData)
                            }
                        }

                        Txt {
                            height: 32
                            text: "+"
                            color: Tokens.muted
                        }

                        Field {
                            id: keyField
                            width: 210
                            height: 32
                            placeholder: Lang.cfgKeyName
                            value: row.open ? page.key : ""
                            invalid: page.error !== ""
                            onEdited: text => {
                                page.key = text;
                                page.error = "";
                            }
                            onAccepted: page.save(row.modelData)
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: 6

                        PillButton {
                            text: Lang.cfgKeySave
                            accent: true
                            onClicked: page.save(row.modelData)
                        }

                        PillButton {
                            text: Lang.cfgKeyDefault
                            onClicked: page.reset(row.modelData)
                        }

                        PillButton {
                            text: Lang.cfgKeyRemove
                            onClicked: page.remove(row.modelData)
                        }

                        Label {
                            height: 26
                            visible: page.error !== ""
                            text: page.error
                            color: Tokens.interrupt
                        }
                    }
                }
            }
        }
    }
}
