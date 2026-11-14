const fs = require("fs");
const path = require("path");
const assert = require("assert");
const source = fs.readFileSync(path.join(__dirname, "../services/TaskMerge.js"), "utf8").replace(".pragma library", "");
const M = new Function(source + "\nreturn { merge, ordered, latest, KEEP_REMOVED, place, rankAt };")();

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

test("put where it is dropped, in its column or another", () => {
    let cards = [card("a", "A", 0, 1), card("b", "B", 0, 2), card("c", "C", 0, 3), card("d", "D", 1, 4)];
    cards = M.place(cards, "c", 0, 0, now + 10);
    assert.deepStrictEqual(ids({ cards }), ["c", "a", "b", "d"]);
    cards = M.place(cards, "a", 0, 2, now + 11);
    assert.deepStrictEqual(ids({ cards }), ["c", "b", "a", "d"]);
    cards = M.place(cards, "d", 0, 1, now + 12);
    assert.deepStrictEqual(ids({ cards }), ["c", "d", "b", "a"]);
    assert.strictEqual(M.place(cards, "d", 0, 1, now + 13), cards);
    assert.strictEqual(cards.find(c => c.id === "d").placeStamp, now + 12);
});

test("an order kept by the other side, and by one from before ranks", () => {
    const desktop = { cards: M.place([card("a", "A", 0, 1), card("b", "B", 0, 2)], "b", 0, 0, now + 5), removed: {} };
    const older = { cards: desktop.cards.map(c => ({ id: c.id, text: c.text, column: c.column, textStamp: c.textStamp, placeStamp: c.placeStamp })), removed: {} };
    assert.deepStrictEqual(ids(M.merge(desktop, older, now + 9)), ["b", "a"]);
    assert.deepStrictEqual(M.merge(desktop, older, now + 9), M.merge(older, desktop, now + 9));
    const moved = { cards: [card("a", "A", 1, 1, 7), card("b", "B", 0, 2, 5)], removed: {} };
    assert.deepStrictEqual(M.merge(desktop, moved, now + 9).cards.map(c => [c.id, c.column]), [["b", 0], ["a", 1]]);
});

test("no room between two: the column is ranked again", () => {
    const tight = [Object.assign(card("a", "A", 0, 1), { rank: 1 }), Object.assign(card("b", "B", 0, 2), { rank: 1 + Number.EPSILON }), card("c", "C", 0, 3)];
    const cards = M.place(tight, "c", 0, 1, now + 10);
    assert.deepStrictEqual(ids({ cards }), ["a", "c", "b"]);
    assert.deepStrictEqual(cards.map(c => c.rank), [now + 10, now + 11, now + 12]);
    assert.ok(cards.every(c => c.placeStamp === now + 10));
    assert.strictEqual(M.rankAt([], 0, now), now);
});

console.log(passed + " passed");
