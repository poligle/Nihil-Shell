import QtQuick
import qs.theme

// Dot-plot "oscilloscope" for a time series (e.g. network throughput).
// Values are drawn on a log scale so idle traffic is still visible.
Canvas {
    id: root

    property var series: []         // newest last
    property var secondary: []      // optional second trace (dimmer)
    property int samples: 60
    property real floor: 512        // bytes/s mapped to the baseline

    implicitHeight: 48

    onSeriesChanged: requestPaint()
    onSecondaryChanged: requestPaint()
    onWidthChanged: requestPaint()

    function level(v: real, peak: real): real {
        if (v <= root.floor) return 0;
        return Math.min(1, Math.log(v / root.floor) / Math.log(Math.max(peak, root.floor * 4) / root.floor));
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const step = width / samples;
        const rows = Math.max(3, Math.floor(height / step));
        const r = Math.max(1, step * 0.28);
        const peak = Math.max(root.floor * 4, ...root.series, ...root.secondary);

        // LEDs off
        ctx.fillStyle = Tokens.off;
        for (let i = 0; i < samples; i++)
            for (let j = 0; j < rows; j++) {
                ctx.beginPath();
                ctx.arc(i * step + step / 2, height - j * step - step / 2, r * 0.6, 0, 2 * Math.PI);
                ctx.fill();
            }

        const draw = (data, colour) => {
            ctx.fillStyle = colour;
            const offset = samples - data.length;
            for (let k = 0; k < data.length; k++) {
                const h = Math.round(root.level(data[k], peak) * (rows - 1));
                if (h <= 0 && data[k] <= root.floor) continue;
                ctx.beginPath();
                ctx.arc((offset + k) * step + step / 2, height - h * step - step / 2, r, 0, 2 * Math.PI);
                ctx.fill();
            }
        };

        draw(root.secondary, Tokens.muted);
        draw(root.series, Tokens.ink);
    }
}
