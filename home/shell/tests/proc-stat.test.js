const fs = require("fs");
const path = require("path");
const assert = require("assert");
const source = fs.readFileSync(path.join(__dirname, "../services/ProcStat.js"), "utf8").replace(".pragma library", "");
const P = new Function(source + "\nreturn { cpu, busy };")();

let passed = 0;
function test(name, body) { body(); passed++; console.log("ok", name); }

test("a virtual machine's time is busy once", () => {
    // Eight threads for a second, two of them a virtual machine's: 200 of user, all of it guest
    // too; 50 of user and 50 of system besides, and 500 idle. 300 of 800 busy.
    //            user nice system idle iowait irq softirq steal guest guest_nice
    const before = "cpu  1000 0 500 10000 0 0 0 0 600 0\ncpu0 125 0 62 1250 0 0 0 0 75 0\n";
    const after = "cpu  1250 0 550 10500 0 0 0 0 800 0\ncpu0 156 0 69 1312 0 0 0 0 100 0\n";
    assert.deepStrictEqual(P.cpu(before), { idle: 10000, total: 11500 });
    assert.strictEqual(P.busy(P.cpu(before), P.cpu(after)), 0.375);
});

test("guest_nice is in nice already", () => {
    const before = P.cpu("cpu  0 1000 0 1000 0 0 0 0 0 1000");
    const after = P.cpu("cpu  0 1500 0 1500 0 0 0 0 0 1500");
    assert.strictEqual(P.busy(before, after), 0.5);
});

test("waiting on the disk is idle", () => {
    const before = P.cpu("cpu  100 0 0 100 100 0 0 0 0 0");
    const after = P.cpu("cpu  200 0 0 150 150 0 0 0 0 0");
    assert.strictEqual(P.busy(before, after), 0.5);
});

test("no time between two readings is no reading", () => {
    const same = P.cpu("cpu  10 0 10 100 0 0 0 0 0 0");
    assert.strictEqual(P.busy(same, same), null);
});

console.log(passed, "passed");
