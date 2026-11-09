.pragma library
// How two kanbans become one: the desktop's (Tasks.qml) and a phone's, the same
// rules as NIHIL Launcher's core/TaskBoard.kt. Each card keeps when its text and
// its column were last set (textStamp, placeStamp, milliseconds); a removal leaves
// its stamp in "removed". For each card the text set last and the column set last
// win, and a removal wins over everything set before it. Whichever way round and
// however often: two sides apart for a week each keep what the other did.

var KEEP_REMOVED = 60 * 24 * 60 * 60 * 1000;

function merge(a, b, now) {
    const mine = {};
    const theirs = {};
    (a.cards || []).forEach(c => { mine[c.id] = c; });
    (b.cards || []).forEach(c => { theirs[c.id] = c; });
    const removedA = a.removed || {};
    const removedB = b.removed || {};
    const ids = new Set([].concat(Object.keys(mine), Object.keys(theirs), Object.keys(removedA), Object.keys(removedB)));
    const cards = [];
    const removed = {};
    ids.forEach(id => {
        const x = mine[id];
        const y = theirs[id];
        const card = x && y ? combine(x, y) : (x || y);
        const gone = Math.max(id in removedA ? removedA[id] : -Infinity, id in removedB ? removedB[id] : -Infinity);
        if (card && gone < Math.max(card.textStamp, card.placeStamp))
            cards.push(card);
        else if (gone !== -Infinity && now - gone < KEEP_REMOVED)
            removed[id] = gone;
    });
    return { cards: ordered(cards), removed: removed };
}

// Equal stamps (rare): the greater text, the further column, on both sides alike.
function combine(x, y) {
    const text = x.textStamp !== y.textStamp ? (x.textStamp > y.textStamp ? x : y) : (x.text >= y.text ? x : y);
    const place = x.placeStamp !== y.placeStamp ? (x.placeStamp > y.placeStamp ? x : y) : (x.column >= y.column ? x : y);
    return { id: x.id, text: text.text, column: place.column, textStamp: text.textStamp, placeStamp: place.placeStamp };
}

// By column, then in the order they got there: how the board shows them.
function ordered(cards) {
    return cards.slice().sort((p, q) => p.column - q.column || p.placeStamp - q.placeStamp || (p.id < q.id ? -1 : p.id > q.id ? 1 : 0));
}

// The latest stamp a board holds: the clock goes on from there.
function latest(board) {
    let last = 0;
    (board.cards || []).forEach(c => { last = Math.max(last, c.textStamp, c.placeStamp); });
    Object.keys(board.removed || {}).forEach(id => { last = Math.max(last, board.removed[id]); });
    return last;
}
