import QtQuick
import Quickshell.Widgets
import qs.theme
import qs.config
import qs.services
import qs.components

Item {
    id: root

    readonly property var item: Vector.received
    readonly property real radius: 14
    readonly property real pitch: 7
    readonly property bool over: pointer.containsMouse || dropArea.containsDrag
    property real head: -1
    property real flash: 0
    property color flashColor: Tokens.ink

    readonly property var leds: {
        const inset = 1.5;
        const w = root.width - 2 * inset;
        const h = root.height - 2 * inset;
        const r = Math.min(root.radius, w / 2, h / 2);
        if (w <= 2 * r || h <= 2 * r)
            return [];
        const across = w - 2 * r;
        const down = h - 2 * r;
        const arc = Math.PI * r / 2;
        const length = 2 * (across + down) + 4 * arc;
        const count = Math.max(8, Math.floor(length / root.pitch));
        const corner = (cx, cy, from, t) => {
            const a = from + t / arc * Math.PI / 2;
            return { x: inset + cx + r * Math.cos(a), y: inset + cy + r * Math.sin(a) };
        };
        const points = [];
        for (let i = 0; i < count; i++) {
            let s = i * length / count;
            let p;
            if (s < across) p = { x: inset + r + s, y: inset };
            else if ((s -= across) < arc) p = corner(w - r, r, -Math.PI / 2, s);
            else if ((s -= arc) < down) p = { x: inset + w, y: inset + r + s };
            else if ((s -= down) < arc) p = corner(w - r, h - r, 0, s);
            else if ((s -= arc) < across) p = { x: inset + w - r - s, y: inset + h };
            else if ((s -= across) < arc) p = corner(r, h - r, Math.PI / 2, s);
            else if ((s -= arc) < down) p = { x: inset, y: inset + h - r - s };
            else p = corner(r, r, Math.PI, s - down);
            points.push(p);
        }
        return points;
    }

    function shade(index: int): color {
        const base = root.over || Vector.busy ? Tokens.muted : Tokens.off;
        let light = 0;
        if (root.head >= 0) {
            const behind = (root.head - index / root.leds.length + 1) % 1;
            light = behind < 0.3 ? 1 - behind / 0.3 : 0;
        }
        const lit = Qt.tint(base, Qt.rgba(Tokens.ink.r, Tokens.ink.g, Tokens.ink.b, light));
        return root.flash > 0 ? Qt.tint(lit, Qt.rgba(root.flashColor.r, root.flashColor.g, root.flashColor.b, root.flash)) : lit;
    }

    NumberAnimation {
        id: lap
        target: root
        property: "head"
        from: 0
        to: 1
        duration: 900
        easing.type: Easing.InOutSine
        onFinished: root.head = -1
    }

    SequentialAnimation {
        id: blink
        NumberAnimation { target: root; property: "flash"; to: 1; duration: 90 }
        NumberAnimation { target: root; property: "flash"; to: 0; duration: 420; easing.type: Easing.OutCubic }
    }

    Connections {
        target: Vector
        function onLit(what: string): void {
            if (what === "sent" || what === "received") {
                lap.restart();
            } else {
                root.flashColor = what === "failed" ? Tokens.interrupt : Tokens.ink;
                blink.restart();
            }
        }
    }

    Timer {
        running: Vector.busy
        interval: 950
        repeat: true
        triggeredOnStart: true
        onTriggered: lap.restart()
    }

    Repeater {
        model: root.leds

        Rectangle {
            required property var modelData
            required property int index

            x: modelData.x - 1.5
            y: modelData.y - 1.5
            width: 3
            height: 3
            radius: 1.5
            color: root.shade(index)
        }
    }

    Label {
        x: 14
        y: 11
        text: Lang.vector
        color: root.over ? Tokens.dim : Tokens.muted
    }

    Ico {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 8
        visible: !Vector.has
        glyph: Icons.swap
        color: root.over ? Tokens.dim : Tokens.off
        font.pixelSize: 22
    }

    ClippingRectangle {
        anchors.fill: parent
        anchors.margins: 12
        anchors.topMargin: 30
        radius: 6
        color: "transparent"
        visible: Vector.has && root.item.kind === "image"

        Image {
            anchors.fill: parent
            source: Vector.has && root.item.kind === "image" ? "file://" + root.item.path.split("/").map(encodeURIComponent).join("/") : ""
            sourceSize.width: 440
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: root.over ? 1 : 0.8
        }
    }

    Txt {
        anchors.fill: parent
        anchors.margins: 14
        anchors.topMargin: 30
        visible: Vector.has && root.item.kind === "text"
        text: Vector.text
        color: root.over ? Tokens.ink : Tokens.dim
        font.pixelSize: 12
        verticalAlignment: Text.AlignTop
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 8
        spacing: 10
        visible: Vector.has && (root.item.kind === "video" || root.item.kind === "file")

        Ico {
            anchors.verticalCenter: parent.verticalCenter
            glyph: root.item.kind === "video" ? Icons.video : Icons.file
            color: root.over ? Tokens.ink : Tokens.dim
            font.pixelSize: 20
        }

        Column {
            width: parent.width - 30
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Txt {
                width: parent.width
                text: root.item.name ?? ""
                color: root.over ? Tokens.ink : Tokens.dim
                font.pixelSize: 13
            }

            Label {
                text: Dates.bytes(root.item.size ?? 0)
            }
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Vector.has ? Vector.copy() : Vector.send("")
    }

    Ico {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 12
        anchors.topMargin: 9
        glyph: Icons.paste
        color: sendArea.containsMouse ? Tokens.ink : Tokens.dim
        font.pixelSize: 15
        opacity: Vector.has && (root.over || sendArea.containsMouse) ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: Tokens.animFast } }

        MouseArea {
            id: sendArea
            anchors.fill: parent
            anchors.margins: -6
            enabled: Vector.has
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Vector.send("")
        }
    }

    DropArea {
        id: dropArea
        anchors.fill: parent
        onDropped: event => {
            if (event.hasUrls && event.urls.length > 0) {
                Vector.send(event.urls[0].toString());
                event.accept();
            }
        }
    }
}
