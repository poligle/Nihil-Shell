// node home/shell/tests/task-merge.test.js: the kanban's merge (services/TaskMerge.js),
// with the scenarios NIHIL Launcher's TaskBoardTest checks, so both sides agree.
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const source = fs.readFileSync(path.join(__dirname, "../services/TaskMerge.js"), "utf8").replace(".pragma library", "");
const M = new Function(source + "\nreturn { merge, ordered, latest, KEEP_REMOVED };")();

const now = 1800000000000;
const card = (id, text, column, t, p = t) => ({ id, text, column, textStamp: now + t, placeStamp: now + p });
const ids = board => board.cards.map(c => c.id);
let passed = 0;
function test(name, body) { body(); passed++; console.log("ok", name); }

test("both sides changed while apart", () => {
    const phone = { cards: [card("a", "Entregar la práctica", 1, 1, 10), card("b", "Keycaps", 0, 2), card("c", "Nilo v3", 0, 11)], removed: {} };
    const desktop = { cards: [card("a", "Entregar la práctica 2", 0, 12, 1)], removed: { b: now + 13 } };
    const merged = M.merge(phone, desktop, now + 20);
    const a = merged.cards.find(c => c.id === "a");
    assert.strictEqual(a.text, "Entregar la práctica 2");
    assert.strictEqual(a.column, 1);
    assert.deepStrictEqual(ids(merged).sort(), ["a", "c"]);
    assert.deepStrictEqual(merged.removed, { b: now + 13 });
});

test("the same whichever way round and however often", () => {
    const x = { cards: [card("a", "One", 0, 5), card("b", "Two", 2, 3)], removed: { z: now + 1 } };
    const y = { cards: [card("a", "Uno", 1, 4, 6), card("c", "Three", 0, 7)], removed: { b: now + 9 } };
    const xy = M.merge(x, y, now + 10);
    assert.deepStrictEqual(xy, M.merge(y, x, now + 10));
    assert.deepStrictEqual(xy, M.merge(xy, x, now + 10));
    assert.deepStrictEqual(xy, M.merge(M.merge(xy, y, now + 10), x, now + 10));
});

test("a later edit brings back a removed card", () => {
    const removed = { cards: [], removed: { a: now + 5 } };
    assert.deepStrictEqual(ids(M.merge(removed, { cards: [card("a", "Still to do", 0, 8, 1)], removed: {} }, now + 10)), ["a"]);
    assert.deepStrictEqual(ids(M.merge(removed, { cards: [card("a", "Old", 0, 3)], removed: {} }, now + 10)), []);
});

test("removals are forgotten after sixty days", () => {
    const removed = { cards: [], removed: { a: now } };
    assert.deepStrictEqual(M.merge(removed, { cards: [], removed: {} }, now + 1000).removed, { a: now });
    assert.deepStrictEqual(M.merge(removed, { cards: [], removed: {} }, now + M.KEEP_REMOVED + 1).removed, {});
});

test("in the order the board shows", () => {
    const board = { cards: [card("x", "Later", 0, 9), card("y", "Done", 2, 1), card("z", "Sooner", 0, 2)], removed: {} };
    assert.deepStrictEqual(ids(M.merge(board, { cards: [], removed: {} }, now + 10)), ["z", "x", "y"]);
    assert.strictEqual(M.latest(board), now + 9);
});

console.log(passed + " passed");
