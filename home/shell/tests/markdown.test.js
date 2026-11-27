const fs = require("fs");
const path = require("path");
const assert = require("assert");
const source = fs.readFileSync(path.join(__dirname, "../nilo/Markdown.js"), "utf8").replace(".pragma library", "");
const M = new Function(source + "\nreturn { html, host, toggled };")();

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

test("an address keeps its parentheses, and stays out of what ends the sentence", () => {
    const wiki = "https://es.wikipedia.org/wiki/Nix_(gestor_de_paquetes)";
    assert.deepStrictEqual(hrefs(M.html(`Mira ${wiki}.`, voices)), [wiki]);
    assert.ok(M.html(`Mira ${wiki}.`, voices).includes(`${wiki}</a>.`));
    const out = M.html(`[Nix](${wiki}) y (https://nixos.org)`, voices);
    assert.deepStrictEqual(hrefs(out), [wiki, "https://nixos.org"]);
    assert.ok(out.includes(">Nix</a> y (<a") && out.includes("nixos.org</a>)"));
});

test("emphasis doesn't reach into an address", () => {
    const out = M.html("See https://example.com/_priv_/a and *this*", voices);
    assert.deepStrictEqual(hrefs(out), ["https://example.com/_priv_/a"]);
    assert.ok(out.includes(">https://example.com/_priv_/a</a>") && out.includes("<i>this</i>"));
    assert.ok(M.html("[**the** manual](https://nixos.org/a_b_c)", voices).includes('href="https://nixos.org/a_b_c"'));
});

const note = Object.assign({ dim: "#888", icons: "Icons", breaks: true, tasks: true }, voices);

test("strikethrough, and a quote set off and dimmed", () => {
    assert.ok(M.html("~~done~~ and not", voices).includes("<s>done</s> and not"));
    const out = M.html("Before\n> said once\n> and twice\nAfter", note);
    assert.ok(out.includes("Before</p>"), out);
    assert.ok(out.includes('margin-left:12px; color:#888;">said once<br>and twice</p>'), out);
    assert.ok(out.includes(">After</p>"), out);
});

test("a note's lines are lines; Nilo's run on", () => {
    assert.ok(M.html("milk\neggs", note).includes("milk<br>eggs"));
    assert.ok(M.html("milk\neggs", voices).includes("milk eggs"));
});

test("tasks: a mark to tick, by the line it's on", () => {
    const out = M.html("# Shopping\n- [ ] milk\n- [x] **eggs**\n- bread", note);
    assert.deepStrictEqual(hrefs(out), ["task:1", "task:2"]);
    assert.ok(out.includes("&#xF0130;</span></a>&nbsp; milk") && out.includes("&#xF0133;</span></a>&nbsp; <b>eggs</b>"), out);
    assert.ok(out.includes("<li style=\"margin-bottom:4px;\">bread</li>"), out);
    // Nilo shows them, but they're not links there.
    assert.deepStrictEqual(hrefs(M.html("- [ ] milk", voices)), []);
    assert.strictEqual(M.toggled("# Shopping\n- [ ] milk\n- [x] eggs", 1), "# Shopping\n- [x] milk\n- [x] eggs");
    assert.strictEqual(M.toggled("# Shopping\n- [ ] milk\n- [X] eggs", 2), "# Shopping\n- [ ] milk\n- [ ] eggs");
    assert.strictEqual(M.toggled("# Shopping\n- milk", 1), "# Shopping\n- milk");
    assert.strictEqual(M.toggled("a", 7), "a");
});

test("in a note, no tag gets through either", () => {
    const out = M.html('<img src="https://example.com/x.png"> ![x](https://example.com/y.png) <b onclick="x">', note);
    assert.ok(!/<img|<b /.test(out), out);
    assert.ok(out.includes("&lt;img"), out);
});

test("titles and code go with the text's size, Nilo's as they were", () => {
    const text = "# Title\n#### Small\nSome `code`\n\n```\nblock\n```";
    const sizes = out => (out.match(/font-size:\d+px/g) || []).join(" ");
    assert.strictEqual(sizes(M.html(text, voices)), "font-size:20px font-size:15px font-size:13px font-size:12px");
    // A note's, at 13: smaller titles, and code no smaller than 11.
    assert.strictEqual(sizes(M.html(text, Object.assign({ size: 13 }, voices))), "font-size:17px font-size:13px font-size:11px font-size:11px");
});

test("a line's height goes in each block of text, and only when asked for", () => {
    const text = "Para\n\n- one\n- [ ] task\n# Title";
    assert.ok(!M.html(text, voices).includes("line-height"));
    const out = M.html(text, Object.assign({ line: 1.25 }, voices));
    assert.strictEqual((out.match(/line-height:125%/g) || []).length, 4, out);
});

console.log(`${passed} passed`);
