.pragma library

// The processor's time, from the first line of /proc/stat: idle, and all of it. Its ninth and
// tenth columns, guest and guest_nice, are already in user and nice: counted again, a virtual
// machine's time would be in the total twice, and busy twice.
function cpu(text) {
    const f = String(text).split("\n")[0].trim().split(/\s+/).slice(1, 9).map(Number);
    return { idle: f[3] + (f[4] || 0), total: f.reduce((a, b) => a + b, 0) };
}

// The share of the time between two readings that was busy; null with no time between them.
function busy(before, after) {
    return after.total > before.total ? 1 - (after.idle - before.idle) / (after.total - before.total) : null;
}
