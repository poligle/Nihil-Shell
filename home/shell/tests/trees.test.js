// The installer's window and the greeter are trees of their own, with a few of the shell's files:
// one that names a type its tree doesn't copy stops the whole window from loading, and that shows
// only on the machine.
const fs = require("fs");
const path = require("path");
const assert = require("assert");

const repo = path.join(__dirname, "../../..");
const read = file => fs.readFileSync(path.join(repo, file), "utf8");

let passed = 0;
function test(name, body) { body(); passed++; console.log("ok", name); }

// What a .nix copies with cp, by where it goes in the tree: the file it comes from, or null for one
// it makes itself.
function copies(file) {
    const files = {};
    const copy = /cp \$\{([^}\s]+)\} \$out\/([\w./-]+)/g;
    let found;
    const text = read(file);
    while ((found = copy.exec(text)) !== null)
        files[found[2]] = found[1].startsWith(".") ? path.join(path.dirname(file), found[1]) : null;
    return files;
}

// The shell's types: its own folders, and what home/shell.nix makes into them.
const made = copies("home/shell.nix");
const shellHas = (module, type) => fs.existsSync(path.join(repo, "home/shell", module, type + ".qml"))
    || (module + "/" + type + ".qml") in made;

// What a tree lacks: the imports, and the shell's types, its files name and it doesn't have.
function lacks(files) {
    const missing = [];
    for (const place of Object.keys(files)) {
        const source = files[place];
        if (source === null || !place.endsWith(".qml"))
            continue;
        const folder = path.posix.dirname(place);
        const raw = read(source);
        let found;
        const relative = /^import\s+"([^"]+)"/gm;
        while ((found = relative.exec(raw)) !== null)
            if (!(path.posix.join(folder, found[1]) in files))
                missing.push(place + " imports " + found[1]);
        // A file sees its own folder's types and those of the qs modules it imports.
        const modules = folder === "." ? [] : [folder];
        const module = /^import\s+qs\.(\w+)/gm;
        while ((found = module.exec(raw)) !== null) {
            modules.push(found[1]);
            if (!Object.keys(files).some(other => other.startsWith(found[1] + "/")))
                missing.push(place + " imports qs." + found[1]);
        }
        const code = raw.replace(/"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|`(?:[^`\\]|\\.)*`|\/\/[^\n]*|\/\*[\s\S]*?\*\//g, " ");
        const names = new Set();
        const name = /(^|[^.\w])([A-Z]\w*)/g;
        while ((found = name.exec(code)) !== null)
            names.add(found[2]);
        for (const type of names)
            for (const from of modules)
                if (shellHas(from, type) && !((from + "/" + type + ".qml") in files))
                    missing.push(place + " uses " + type + ", from qs." + from);
    }
    return missing;
}

const installer = copies("installer/iso.nix");
const greeter = copies("modules/greeter.nix");

test("what each tree copies, read from its .nix", () => {
    assert.ok(installer["shell.qml"].endsWith(path.join("installer", "gui", "shell.qml")));
    assert.ok(installer["components/Field.qml"].endsWith(path.join("components", "Field.qml")));
    assert.strictEqual(installer["config/Config.qml"], null);
    assert.ok(greeter["shell.qml"].endsWith(path.join("greeter", "shell.qml")));
    assert.ok(made["config/Lang.qml"] === null && shellHas("theme", "Tokens") && shellHas("components", "Txt"));
});

test("the installer's window has every type its files use", () => {
    assert.deepStrictEqual(lacks(installer), []);
});

test("the greeter has every type its files use", () => {
    assert.deepStrictEqual(lacks(greeter), []);
});

test("a type the tree doesn't copy shows, a component or a singleton", () => {
    const without = (files, place) => { const rest = Object.assign({}, files); delete rest[place]; return rest; };
    assert.deepStrictEqual(lacks(without(installer, "components/TextMenu.qml")), ["components/Field.qml uses TextMenu, from qs.components"]);
    assert.deepStrictEqual(lacks(without(installer, "config/Lang.qml")), ["components/TextMenu.qml uses Lang, from qs.config"]);
});

console.log(passed, "passed");
