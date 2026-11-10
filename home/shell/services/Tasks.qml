pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "TaskMerge.js" as TaskMerge

// The kanban in the dashboard (drawers/TaskBoard.qml): short tasks in three
// columns, to do, doing and done, each in the order they are put. They live in
// ~/.local/state/nihil/tasks.json, which can also be edited by hand: the board
// follows the file. A phone with NIHIL Launcher keeps the same board through the
// deck (tasks sync): each card carries when its text and its place (its column
// and its rank there) were last set, a removed card leaves the time of its
// removal, and TaskMerge.js puts two boards together.
//   qs -c nihil ipc call tasks add "Entregar la práctica"     tasks list
Singleton {
    id: root

    readonly property int columns: 3
    readonly property int maxLength: 160
    // In display order: [{ id, text, column, textStamp, placeStamp, rank }], column 0
    // to do, 1 doing, 2 done (a card from before ranks has none); removed: { id: when },
    // kept 60 days.
    property var cards: []
    property var removed: ({})
    // The last stamp given or seen: the next one is always later.
    property real clock: 0
    readonly property string path: {
        const home = Quickshell.env("HOME") ?? "";
        const state = Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state");
        return state + "/nihil/tasks.json";
    }

    function inColumn(column: int): var {
        return cards.filter(card => card.column === column);
    }

    function clean(text: string): string {
        return String(text ?? "").replace(/\s+/g, " ").trim().slice(0, maxLength);
    }

    // At the end of "to do".
    function add(text: string): void {
        const typed = clean(text);
        if (typed === "") return;
        const at = stamp();
        const todo = inColumn(0);
        cards = TaskMerge.ordered(cards.concat([{ id: newId(), text: typed, column: 0, textStamp: at, placeStamp: at,
            rank: TaskMerge.rankAt(todo, todo.length, at) }]));
        save();
    }

    // Its text written again; empty, it stays as it was.
    function edit(id: string, text: string): void {
        const typed = clean(text);
        const card = cards.find(c => c.id === id);
        if (!card || typed === "" || typed === card.text) return;
        const at = stamp();
        cards = cards.map(c => c.id === id ? Object.assign({}, c, { text: typed, textStamp: at }) : c);
        save();
    }

    // To the end of another column.
    function move(id: string, column: int): void {
        const to = Math.max(0, Math.min(columns - 1, column));
        const card = cards.find(c => c.id === id);
        if (!card || card.column === to) return;
        place(id, to, inColumn(to).length);
    }

    // Where it is dropped: at [index] of [column], counted without it.
    function place(id: string, column: int, index: int): void {
        const to = Math.max(0, Math.min(columns - 1, column));
        const next = TaskMerge.place(cards, id, to, index, stamp());
        if (next === cards) return;
        cards = next;
        save();
    }

    function remove(id: string): void {
        forget(cards.filter(c => c.id === id));
    }

    function clearDone(): void {
        forget(cards.filter(c => c.column === columns - 1));
    }

    function forget(gone: var): void {
        if (gone.length === 0) return;
        const next = Object.assign({}, removed);
        gone.forEach(c => { next[c.id] = stamp(); });
        removed = next;
        cards = cards.filter(c => !(c.id in next));
        save();
    }

    function stamp(): real {
        clock = Math.max(Date.now(), clock + 1);
        return clock;
    }

    function newId(): string {
        return Date.now().toString(36) + Math.floor(Math.random() * 46656).toString(36);
    }

    // A phone's board (or anything in its shape) into this one: the result, for it too.
    function sync(board: var): var {
        const merged = TaskMerge.merge({ cards: cards, removed: removed }, board ?? {}, Date.now());
        clock = Math.max(clock, TaskMerge.latest(merged));
        cards = merged.cards;
        removed = merged.removed;
        save();
        return { cards: cards, removed: removed, now: Date.now() };
    }

    // --- The file -----------------------------------------------------------------

    property string written: ""

    function parse(text: string): void {
        if (text === written) return;
        let data;
        try { data = JSON.parse(text); } catch (e) { console.log("tasks: " + root.path + " is not valid JSON"); return; }
        const list = Array.isArray(data) ? data : data?.cards;
        if (!Array.isArray(list)) return;
        // Version 1 (and a hand-written file) has no stamps: they start at 0, and the
        // file's order is kept as the order the cards got to their column. Version 2
        // has no ranks: a card without one is where it got to its column.
        const loaded = list
            .filter(c => c && String(c.text ?? "").trim() !== "")
            .map((c, i) => {
                const card = {
                    id: String(c.id ?? newId()),
                    text: String(c.text).trim().slice(0, maxLength),
                    column: Math.max(0, Math.min(columns - 1, Number(c.column) || 0)),
                    textStamp: Number(c.textStamp) || 0,
                    placeStamp: Number(c.placeStamp) || i
                };
                if (typeof c.rank === "number" && isFinite(c.rank)) card.rank = c.rank;
                return card;
            });
        const gone = data?.removed && typeof data.removed === "object" && !Array.isArray(data.removed) ? data.removed : {};
        const merged = TaskMerge.merge({ cards: loaded, removed: gone }, {}, Date.now());
        cards = merged.cards;
        removed = merged.removed;
        clock = Math.max(clock, TaskMerge.latest(merged));
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
            root.written = JSON.stringify({ version: 3, cards: root.cards, removed: root.removed }, null, 2) + "\n";
            file.setText(root.written);
        }
    }

    IpcHandler {
        target: "tasks"

        function add(text: string): void { root.add(text); }
        function list(): string {
            return root.cards.map(c => ["[ ]", "[~]", "[x]"][c.column] + " " + c.text).join("\n");
        }
        // For the deck (home/deck): the board as JSON, and a phone's board merged in.
        function state(): string {
            return JSON.stringify({ cards: root.cards, removed: root.removed, now: Date.now() });
        }
        function sync(json: string): string {
            let board;
            try { board = JSON.parse(json); } catch (e) { return ""; }
            return JSON.stringify(root.sync(board));
        }
    }
}
