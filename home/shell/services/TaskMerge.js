.pragma library
// How two kanbans become one: the desktop's (Tasks.qml) and a phone's, the same
// rules as NIHIL Launcher's core/TaskBoard.kt. Each card keeps when its text and
// its place were last set (textStamp, placeStamp, milliseconds); its place is its
// column and its rank there, set where it is put. A removal leaves its stamp in
// "removed". For each card the text set last and the place set last win, and a
// removal wins over everything set before it. Whichever way round and however
// often: two sides apart for a week each keep what the other did.

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

// Equal stamps (rare): the greater text; for the place, one with a rank over one
// without (a side from before ranks), then the further column, then the greater
// rank. On both sides alike.
function combine(x, y) {
    const text = x.textStamp !== y.textStamp ? (x.textStamp > y.textStamp ? x : y) : (x.text >= y.text ? x : y);
    const place = x.placeStamp !== y.placeStamp ? (x.placeStamp > y.placeStamp ? x : y) : tie(x, y);
    const card = { id: x.id, text: text.text, column: place.column, textStamp: text.textStamp, placeStamp: place.placeStamp };
    if (ranked(place))
        card.rank = place.rank;
    return card;
}

function tie(x, y) {
    if (ranked(x) !== ranked(y))
        return ranked(x) ? x : y;
    if (x.column !== y.column)
        return x.column > y.column ? x : y;
    return ranked(x) && y.rank > x.rank ? y : x;
}

function ranked(card) {
    return typeof card.rank === "number" && isFinite(card.rank);
}

// Where a card sits in its column: its rank, or, from before ranks, when it got there.
function position(card) {
    return ranked(card) ? card.rank : card.placeStamp;
}

// By column, then by position: how the board shows them.
function ordered(cards) {
    return cards.slice().sort((p, q) => p.column - q.column || position(p) - position(q) || (p.id < q.id ? -1 : p.id > q.id ? 1 : 0));
}

// The rank of a card put at [index] among [others] (its column in order, without
// it): one less than the first, one more than the last, or halfway between two;
// null when those two are too close for one between (the column is ranked again).
function rankAt(others, index, now) {
    const i = Math.max(0, Math.min(others.length, index));
    const before = i > 0 ? position(others[i - 1]) : null;
    const after = i < others.length ? position(others[i]) : null;
    if (before === null && after === null)
        return now;
    if (before === null)
        return after - 1;
    if (after === null)
        return before + 1;
    const middle = (before + after) / 2;
    return middle > before && middle < after ? middle : null;
}

// [cards] with [id] put at [index] of [column] (where it ends up there, counted
// without it), its place stamped [now]; the same list when it is there already.
function place(cards, id, column, index, now) {
    const card = cards.find(c => c.id === id);
    if (!card)
        return cards;
    const lane = ordered(cards.filter(c => c.column === column));
    const others = lane.filter(c => c.id !== id);
    const at = Math.max(0, Math.min(others.length, index));
    if (card.column === column && lane.indexOf(card) === at)
        return cards;
    const ranks = {};
    const rank = rankAt(others, at, now);
    if (rank !== null)
        ranks[id] = rank;
    else
        others.slice(0, at).concat([card], others.slice(at)).forEach((c, i) => { ranks[c.id] = now + i; });
    return ordered(cards.map(c => c.id in ranks
        ? { id: c.id, text: c.text, column: column, textStamp: c.textStamp, placeStamp: now, rank: ranks[c.id] }
        : c));
}

// The latest stamp a board holds: the clock goes on from there.
function latest(board) {
    let last = 0;
    (board.cards || []).forEach(c => { last = Math.max(last, c.textStamp, c.placeStamp); });
    Object.keys(board.removed || {}).forEach(id => { last = Math.max(last, board.removed[id]); });
    return last;
}
