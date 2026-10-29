.pragma library

// The little Markdown a model writes, as Qt rich text in NIHIL's voices:
// paragraphs, lists, headings, **bold**, *italics*, `code`, fenced code and
// links. Anything else stays as typed. It runs on every word while Nilo
// writes, so it never fails on half a construct: an open ** just shows.
//   html(text, { ink, dim, code, surface, mono })

function escape(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function inline(text, s) {
    const codes = [];
    let out = text.replace(/`([^`\n]+)`/g, (m, code) => {
        codes.push(code);
        return "\u0001" + (codes.length - 1) + "\u0001";
    });
    out = out.replace(/\[([^\]\n]+)\]\((https?:\/\/[^\s)]+)\)/g,
        (m, label, url) => `<a href="${url}" style="color:${s.ink};">${label}</a>`);
    out = out.replace(/(^|[\s(])(https?:\/\/[^\s<)]+[^\s<).,;:!?»”])/g,
        (m, before, url) => `${before}<a href="${url}" style="color:${s.ink};">${url}</a>`);
    out = out.replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>");
    out = out.replace(/(^|[^*\w])\*([^*\s][^*\n]*?)\*(?![*\w])/g, "$1<i>$2</i>");
    out = out.replace(/(^|[^\w])_([^_\s][^_\n]*?)_(?!\w)/g, "$1<i>$2</i>");
    return out.replace(/\u0001(\d+)\u0001/g,
        (m, i) => `<span style="font-family:'${s.mono}'; font-size:13px; color:${s.code};">${codes[+i]}</span>`);
}

function html(text, s) {
    const lines = escape(String(text ?? "")).split("\n");
    const out = [];
    let para = [];
    let list = null;
    let code = null;
    const p = "margin-top:0px; margin-bottom:10px;";

    function flushPara() {
        if (para.length) out.push(`<p style="${p}">${inline(para.join(" "), s)}</p>`);
        para = [];
    }
    function flushList() {
        if (list) {
            out.push(`<${list.tag} style="margin-top:0px; margin-bottom:10px; margin-left:-18px;">`
                + list.items.map(item => `<li style="margin-bottom:4px;">${inline(item, s)}</li>`).join("")
                + `</${list.tag}>`);
        }
        list = null;
    }
    function flushCode() {
        out.push(`<table width="100%" cellpadding="12" cellspacing="0" style="margin-bottom:10px;" bgcolor="${s.surface}">`
            + `<tr><td><pre style="font-family:'${s.mono}'; font-size:12px; color:${s.code};">${code.join("\n")}</pre></td></tr></table>`);
        code = null;
    }

    for (const line of lines) {
        if (code !== null) {
            if (/^\s*```/.test(line)) flushCode();
            else code.push(line);
            continue;
        }
        if (/^\s*```/.test(line)) {
            flushPara();
            flushList();
            code = [];
            continue;
        }
        const heading = line.match(/^(#{1,4})\s+(.+)$/);
        if (heading) {
            flushPara();
            flushList();
            const size = [20, 18, 16, 15][heading[1].length - 1];
            out.push(`<p style="${p} font-size:${size}px;"><b>${inline(heading[2], s)}</b></p>`);
            continue;
        }
        const bullet = line.match(/^\s*[-*•]\s+(.*)$/);
        const number = line.match(/^\s*\d+[.)]\s+(.*)$/);
        if (bullet || number) {
            flushPara();
            const tag = bullet ? "ul" : "ol";
            if (!list || list.tag !== tag) {
                flushList();
                list = { tag: tag, items: [] };
            }
            list.items.push((bullet ?? number)[1]);
            continue;
        }
        if (!line.trim()) {
            flushPara();
            flushList();
            continue;
        }
        if (list && /^\s{2,}\S/.test(line)) {
            list.items[list.items.length - 1] += " " + line.trim();
            continue;
        }
        flushList();
        para.push(line.trim());
    }
    if (code !== null) flushCode();
    flushPara();
    flushList();
    return out.join("");
}
