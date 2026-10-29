import QtQuick
import QtQuick.Shapes
import qs.theme
import qs.services
import "Geometry.js" as Geometry

// Light on the inner edge of the frame, like the Glyph LEDs on the back of
// a Nothing phone:
//   sweep  a segment runs around it (a notification; twice and red when critical)
//   rise   plugging in the charger: two lights start at the middle of the
//          bottom edge, climb both sides leaving a fading trail and meet at
//          the top, then it all goes out (the CHARGE pulse of the launcher on
//          the phone: same curve, 70 % travel and 30 % fade, but 1.8 s instead
//          of 1.5: the way round a laptop screen is about twice as long)
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

    // Rise: how far each light has climbed, 0..1 of half the ring.
    property color riseTint: Tokens.ink
    property real climb: 0
    readonly property real reach: climb * perimeter / 2
    readonly property string leftRoute: Geometry.rise(width, height, inset, edge, edge, edge, Tokens.frameRadius, -1)
    readonly property string rightRoute: Geometry.rise(width, height, inset, edge, edge, edge, Tokens.frameRadius, 1)

    // Dash pattern units are multiples of the stroke width.
    function pattern(w: real): var { return [segment / w, (perimeter + segment) / w]; }
    function offset(w: real): real { return (segment - progress * (perimeter + segment)) / w; }

    visible: sweepShape.opacity > 0 || riseShape.opacity > 0

    Shape {
        id: sweepShape
        anchors.fill: parent
        opacity: 0
        visible: opacity > 0
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

    // One stroke of a rising light: the stretch of its route that ends at
    // the head and reaches `length` behind it (0: all the way to the start).
    // Layered, from faint and long to bright and short, they make the trail
    // fade behind the head.
    component Beam: ShapePath {
        property string route
        property real reach
        property real total
        property color tint
        property real length: 0
        property real thick: 2.5
        property real alpha: 1

        readonly property real tail: length > 0 ? Math.max(0, reach - length) : 0

        fillColor: "transparent"
        strokeColor: Qt.rgba(tint.r, tint.g, tint.b, alpha)
        strokeWidth: thick
        strokeStyle: ShapePath.DashLine
        capStyle: length > 0 ? ShapePath.RoundCap : ShapePath.FlatCap
        dashPattern: [Math.max(0.01, reach - tail) / thick, (total + 100) / thick]
        dashOffset: -tail / thick

        PathSvg { path: route }
    }

    Shape {
        id: riseShape
        anchors.fill: parent
        opacity: 0
        visible: opacity > 0 && root.reach > 1
        preferredRendererType: Shape.GeometryRenderer
        layer.enabled: true
        layer.samples: 4

        Beam { route: root.leftRoute; reach: root.reach; total: root.perimeter; tint: root.riseTint; alpha: 0.14 }
        Beam { route: root.leftRoute; reach: root.reach; total: root.perimeter; tint: root.riseTint; length: 420; alpha: 0.26 }
        Beam { route: root.leftRoute; reach: root.reach; total: root.perimeter; tint: root.riseTint; length: 180; thick: 8; alpha: 0.22 }
        Beam { route: root.leftRoute; reach: root.reach; total: root.perimeter; tint: root.riseTint; length: 180 }

        Beam { route: root.rightRoute; reach: root.reach; total: root.perimeter; tint: root.riseTint; alpha: 0.14 }
        Beam { route: root.rightRoute; reach: root.reach; total: root.perimeter; tint: root.riseTint; length: 420; alpha: 0.26 }
        Beam { route: root.rightRoute; reach: root.reach; total: root.perimeter; tint: root.riseTint; length: 180; thick: 8; alpha: 0.22 }
        Beam { route: root.rightRoute; reach: root.reach; total: root.perimeter; tint: root.riseTint; length: 180 }
    }

    SequentialAnimation {
        id: sweep

        property int laps: 1

        PropertyAction { target: sweepShape; property: "opacity"; value: 1 }
        NumberAnimation {
            target: root
            property: "progress"
            from: 0
            to: 1
            duration: 1100
            easing.type: Easing.InOutCubic
            loops: sweep.laps
        }
        PropertyAction { target: sweepShape; property: "opacity"; value: 0 }
    }

    // Eased like the phone (PathInterpolator 0.2, 0, 0, 1).
    SequentialAnimation {
        id: rise

        PropertyAction { target: root; property: "climb"; value: 0 }
        PropertyAction { target: riseShape; property: "opacity"; value: 1 }
        NumberAnimation {
            target: root
            property: "climb"
            from: 0
            to: 1
            duration: 1260
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
        }
        NumberAnimation { target: riseShape; property: "opacity"; to: 0; duration: 540; easing.type: Easing.OutCubic }
        PropertyAction { target: root; property: "climb"; value: 0 }
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

        function onRise(tint: color): void {
            root.riseTint = tint;
            rise.stop();
            rise.start();
        }
    }
}
