pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The kanban in the dashboard (drawers/TaskBoard.qml): short tasks in three
// columns, to do, doing and done. They live in ~/.local/state/nihil/tasks.json,
// which can also be edited by hand: the board follows the file.
//   qs -c nihil ipc call tasks add "Entregar la práctica"     tasks list
Singleton {
    id: root

    readonly property int columns: 3
    readonly property int maxLength: 160

    // In display order: [{ id, text, column }], column 0 to do, 1 doing, 2 done.
    property var cards: []

    readonly property string path: {
        const home = Quickshell.env("HOME") ?? "";
        const state = Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state");
        return state + "/nihil/tasks.json";
    }

    function inColumn(column: int): var {
        return cards.filter(card => card.column === column);
    }

    function add(text: string): void {
        const clean = String(text ?? "").replace(/\s+/g, " ").trim().slice(0, maxLength);
        if (clean === "") return;
        cards = cards.concat([{ id: newId(), text: clean, column: 0 }]);
        save();
    }

    // To the end of another column.
    function move(id: string, column: int): void {
        const to = Math.max(0, Math.min(columns - 1, column));
        const card = cards.find(c => c.id === id);
        if (!card || card.column === to) return;
        cards = cards.filter(c => c.id !== id).concat([{ id: card.id, text: card.text, column: to }]);
        save();
    }

    function remove(id: string): void {
        cards = cards.filter(c => c.id !== id);
        save();
    }

    function clearDone(): void {
        cards = cards.filter(c => c.column !== columns - 1);
        save();
    }

    function newId(): string {
        return Date.now().toString(36) + Math.floor(Math.random() * 46656).toString(36);
    }

    // --- The file -----------------------------------------------------------------

    property string written: ""

    function parse(text: string): void {
        if (text === written) return;
        let data;
        try { data = JSON.parse(text); } catch (e) { console.log("tasks: " + root.path + " is not valid JSON"); return; }
        const list = Array.isArray(data) ? data : data?.cards;
        if (!Array.isArray(list)) return;
        cards = list
            .filter(c => c && String(c.text ?? "").trim() !== "")
            .map(c => ({
                id: String(c.id ?? newId()),
                text: String(c.text).trim().slice(0, maxLength),
                column: Math.max(0, Math.min(columns - 1, Number(c.column) || 0))
            }));
    }

    function save(): void { saver.restart(); }

    FileView {
        id: file
        path: root.path
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parse(text())
    }

    Timer {
        id: saver
        interval: 250
        onTriggered: {
            root.written = JSON.stringify({ version: 1, cards: root.cards }, null, 2) + "\n";
            file.setText(root.written);
        }
    }

    IpcHandler {
        target: "tasks"

        function add(text: string): void { root.add(text); }
        function list(): string {
            return root.cards.map(c => ["[ ]", "[~]", "[x]"][c.column] + " " + c.text).join("\n");
        }
    }
}
