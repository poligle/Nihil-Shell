import QtQuick
import QtQuick.Effects
import qs.theme

Item {
    id: root

    property string source: ""
    property int pitch: 5
    property int radius: 14
    readonly property alias status: art.status

    // The dots, as paths: each on a pixel's centre and an odd number of pixels across, with a pixel
    // at least clear of the next, so they come out round and apart; none past the rounded corners.
    function dots(ctx: var, width: real, height: real): void {
        const p = root.pitch, r = (p - 1 - p % 2) / 2, first = Math.floor(p / 2) + 0.5;
        const corner = root.radius, inside = Math.max(0, corner - r);
        for (let y = first; y < height; y += p) {
            for (let x = first; x < width; x += p) {
                const dx = Math.max(0, corner - x, x - (width - corner)), dy = Math.max(0, corner - y, y - (height - corner));
                if (dx * dx + dy * dy > inside * inside)
                    continue;
                ctx.beginPath();
                ctx.arc(x, y, r, 0, 2 * Math.PI);
                ctx.fill();
            }
        }
    }

    onPitchChanged: {
        mask.requestPaint();
        idle.requestPaint();
    }
    onRadiusChanged: {
        mask.requestPaint();
        idle.requestPaint();
    }

    clip: true

    Surface {
        anchors.fill: parent
        radius: root.radius
        color: Tokens.surface
    }

    // With no picture, the dots unlit.
    Canvas {
        id: idle
        anchors.fill: parent
        visible: art.status !== Image.Ready

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: {
            if (visible)
                requestPaint();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = String(Tokens.off);
            root.dots(ctx, width, height);
        }
    }

    Image {
        id: art
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        autoTransform: true
        asynchronous: true
        visible: false
        sourceSize.width: root.width * 2
        sourceSize.height: root.height * 2
    }

    // The mask's edge sits at half a dot's cover, softened over a quarter of the range either side:
    // a dot's rim stays whole and its corners part lit, so it reads round, and nothing shows
    // between dots. With the defaults, 0 and 0, the mask let the whole picture through.
    MultiEffect {
        anchors.fill: parent
        source: art
        visible: art.status === Image.Ready
        saturation: -1
        contrast: 0.25
        brightness: 0.05
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.5
    }

    Canvas {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        // Bigger with its card, smoothed rather than in blocks.
        layer.smooth: true

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = "white";
            root.dots(ctx, width, height);
        }
    }
}
