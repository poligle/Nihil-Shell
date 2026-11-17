const fs = require("fs");
const path = require("path");
const assert = require("assert");
const source = fs.readFileSync(path.join(__dirname, "../nilo/Markdown.js"), "utf8").replace(".pragma library", "");
const M = new Function(source + "\nreturn { html, host };")();

const voices = { ink: "#fff", code: "#aaa", mono: "Mono", surface: "#000" };
const hrefs = out => [...out.matchAll(/href="([^"]*)"/g)].map(m => m[1]);
let passed = 0;
function test(name, body) { body(); passed++; console.log("ok", name); }

test("a link's address can't end its attribute", () => {
    const out = M.html('[the manual](https://nixos.org"href="file:///etc/passwd)', voices);
    assert.deepStrictEqual(hrefs(out), ["https://nixos.org&quot;href=&quot;file:///etc/passwd"]);
});

test("nor can a bare one", () => {
    const out = M.html('See https://nixos.org"onclick="x for more', voices);
    assert.strictEqual(hrefs(out).length, 1);
    assert.ok(!/onclick="/.test(out));
});

test("quotes in the text still read as quotes", () => {
    assert.ok(M.html(`He said "hi" and it's fine`, voices).includes("He said &quot;hi&quot; and it&#39;s fine"));
});

test("a link shows where it goes", () => {
    assert.strictEqual(M.host("https://nixos.org/manual/nixos"), "nixos.org");
    assert.strictEqual(M.host("http://example.com:8080?q=1"), "example.com:8080");
    assert.strictEqual(M.host("file:///etc/passwd"), "");
    assert.strictEqual(M.host(""), "");
});

console.log(`${passed} passed`);
