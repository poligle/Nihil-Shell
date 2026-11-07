import QtQuick
import qs.theme

// A QR in dots, as NIHIL draws: black dots on an ink tile, four modules of
// quiet zone around. What a camera looks for to find it and square it up
// stays whole: the three corner squares, and the small ones inside a
// bigger QR (alignment patterns, where the QR standard puts them).
// rows: strings of 0 and 1 (nihil-deck pair --json).
Rectangle {
    id: root

    property var rows: []
    // Big enough for a camera at arm's length: about 5 px a module for the
    // deck's QR (version 8, 49 modules, and the quiet zone).
    property real size: 288
    readonly property int count: rows.length
    readonly property int quiet: 4

    // Where the alignment patterns' centres go, by version (ISO/IEC 18004,
    // annex E), up to 14; a bigger one keeps them as dots.
    readonly property var centres: [[], [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42],
        [6, 26, 46], [6, 28, 50], [6, 30, 54], [6, 32, 58], [6, 34, 62], [6, 26, 46, 66]]

    implicitWidth: size
    implicitHeight: size
    radius: 14
    color: Tokens.ink

    onRowsChanged: dots.requestPaint()

    Canvas {
        id: dots
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const n = root.count;
            if (n === 0)
                return;
            const module = width / (n + 2 * root.quiet);
            const origin = root.quiet * module;
            const version = (n - 17) / 4;

            // The squares drawn whole: [x, y, side] of each corner and
            // each alignment pattern (not those on the corners).
            const whole = [[0, 0, 7], [n - 7, 0, 7], [0, n - 7, 7]];
            const places = version < root.centres.length ? root.centres[version] : [];
            for (const cx of places) {
                for (const cy of places) {
                    const onCorner = (cx < 9 && cy < 9) || (cx > n - 9 && cy < 9) || (cx < 9 && cy > n - 9);
                    if (!onCorner)
                        whole.push([cx - 2, cy - 2, 5]);
                }
            }
            const inWhole = (x, y) => whole.some(([wx, wy, side]) => x >= wx && x < wx + side && y >= wy && y < wy + side);

            ctx.fillStyle = Tokens.black;
            for (let y = 0; y < n; y++) {
                const row = root.rows[y];
                for (let x = 0; x < n; x++) {
                    if (row.charAt(x) !== "1" || inWhole(x, y))
                        continue;
                    ctx.beginPath();
                    ctx.arc(origin + (x + 0.5) * module, origin + (y + 0.5) * module, module * 0.43, 0, 2 * Math.PI);
                    ctx.fill();
                }
            }

            // Each, as a ring and its middle: 7, 5 and 3 modules for a
            // corner, 5, 3 and 1 for an alignment pattern.
            const square = (x, y, side, colour) => {
                ctx.fillStyle = colour;
                ctx.beginPath();
                const corner = Math.min(side / 2, 1.2) * module;
                ctx.roundedRect(origin + x * module, origin + y * module, side * module, side * module, corner, corner);
                ctx.fill();
            };
            for (const [x, y, side] of whole) {
                square(x, y, side, Tokens.black);
                square(x + 1, y + 1, side - 2, Tokens.ink);
                square(x + 2, y + 2, side - 4, Tokens.black);
            }
        }
    }
}
