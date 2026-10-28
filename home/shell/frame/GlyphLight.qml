import QtQuick
import QtQuick.Shapes
import qs.theme
import qs.services
import "Geometry.js" as Geometry

// A segment of light that runs once around the inner edge of the frame,
// like the Glyph LEDs on the back of a Nothing phone.
Item {
    id: root

    property int inset: Tokens.frameThickness
    property int edge: Tokens.frameThickness
    property color tint: Tokens.ink
    property int start: 1
    property real progress: 0

    readonly property real segment: 260
    readonly property real perimeter: Geometry.ringLength(width, height, inset, edge, edge, edge, Tokens.frameRadius)
    readonly property string ring: Geometry.outline(width, height, inset, edge, edge, edge,
        Tokens.frameRadius, 0, 0, [], start)

    // Dash pattern units are multiples of the stroke width.
    function pattern(w: real): var { return [segment / w, (perimeter + segment) / w]; }
    function offset(w: real): real { return (segment - progress * (perimeter + segment)) / w; }

    opacity: 0
    visible: opacity > 0

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.22)
            strokeWidth: 8
            strokeStyle: ShapePath.DashLine
            capStyle: ShapePath.RoundCap
            dashPattern: root.pattern(8)
            dashOffset: root.offset(8)

            PathSvg { path: root.ring }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.tint
            strokeWidth: 2.5
            strokeStyle: ShapePath.DashLine
            capStyle: ShapePath.RoundCap
            dashPattern: root.pattern(2.5)
            dashOffset: root.offset(2.5)

            PathSvg { path: root.ring }
        }
    }

    SequentialAnimation {
        id: sweep

        property int laps: 1

        PropertyAction { target: root; property: "opacity"; value: 1 }
        NumberAnimation {
            target: root
            property: "progress"
            from: 0
            to: 1
            duration: 1100
            easing.type: Easing.InOutCubic
            loops: sweep.laps
        }
        PropertyAction { target: root; property: "opacity"; value: 0 }
    }

    Connections {
        target: Glyph

        function onSweep(tint: color, laps: int, startEdge: int): void {
            root.tint = tint;
            root.start = startEdge;
            sweep.stop();
            sweep.laps = laps;
            sweep.start();
        }
    }
}
