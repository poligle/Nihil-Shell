import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.config
import qs.services
import qs.components

Scope {
    id: root

    readonly property var target: {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (screens[i].name === Config.primaryOutput) return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }
    // Where the widgets go, worked out as the frame works out its edges: placed by hand, not
    // within what other surfaces reserve, so the glass bends exactly what's behind them.
    readonly property int gap: 24
    readonly property bool anyBar: Quickshell.screens.some(s => Config.barOutputs.indexOf(s.name) >= 0)
    readonly property int inset: root.target !== null && (Config.barOutputs.indexOf(root.target.name) >= 0
        || (!root.anyBar && Quickshell.screens.indexOf(root.target) === 0)) ? Tokens.barWidth : Tokens.frameThickness
    readonly property int deskLeft: root.inset + root.gap
    readonly property int deskTop: Tokens.frameThickness + root.gap
    readonly property int deskEdge: Tokens.frameThickness + root.gap
    readonly property int spacing: 14
    // A widget lands on a grid, so those side by side line up.
    readonly property int cell: 8

    function enabled(name: string): bool {
        return Machine.widgets.indexOf(name) >= 0;
    }

    function cards(): var {
        const out = [];
        for (let i = 0; i < desk.children.length; i++) {
            if (desk.children[i].widget !== undefined)
                out.push(desk.children[i]);
        }
        return out;
    }

    // Those that were never put anywhere, one under the other, in the order they're written.
    function flow(card: var): real {
        let y = 0;
        for (const other of root.cards()) {
            if (other === card)
                return y;
            if (other.visible && other.place === null)
                y += other.height + root.spacing;
        }
        return y;
    }

    // The place on the grid nearest (x, y) where the card fits, a gap clear of the others.
    function room(card: var, x: real, y: real): point {
        const others = root.cards().filter(other => other !== card && other.visible);
        const clear = (px, py) => others.every(o => px + card.width + root.spacing <= o.x || px >= o.x + o.width + root.spacing
            || py + card.height + root.spacing <= o.y || py >= o.y + o.height + root.spacing);
        const fit = (v, size, limit) => Math.max(0, Math.min(Math.floor((limit - size) / root.cell) * root.cell, Math.round(v / root.cell) * root.cell));
        const sx = fit(x, card.width, desk.width), sy = fit(y, card.height, desk.height);
        if (clear(sx, sy))
            return Qt.point(sx, sy);
        for (let ring = 1; ring < 120; ring++) {
            let best = null, far = Infinity;
            for (let i = -ring; i <= ring; i++) {
                for (const [dx, dy] of [[i, -ring], [i, ring], [-ring, i], [ring, i]]) {
                    const px = sx + dx * root.cell, py = sy + dy * root.cell;
                    if (px < 0 || py < 0 || px + card.width > desk.width || py + card.height > desk.height)
                        continue;
                    const d = dx * dx + dy * dy;
                    if (d < far && clear(px, py)) {
                        best = Qt.point(px, py);
                        far = d;
                    }
                }
            }
            if (best !== null)
                return best;
        }
        return Qt.point(sx, sy);
    }

    // The first one moved keeps the rest where they show: from then on each one has its place.
    function drop(card: var, x: real, y: real): void {
        const places = {};
        for (const other of root.cards()) {
            if (other !== card && other.visible && other.place === null)
                places[other.widget] = [other.x, other.y];
        }
        Machine.placeWidgets(places);
        const at = root.room(card, x, y);
        Machine.placeWidgets({ [card.widget]: [at.x, at.y] });
    }

    // Turned on once the others have places: it goes where there's room, near the top left.
    function settle(card: var): void {
        if (!card.visible || card.place !== null || !root.cards().some(other => other.place !== null))
            return;
        const at = root.room(card, 0, 0);
        Machine.placeWidgets({ [card.widget]: [at.x, at.y] });
    }

    // Once what's shown has settled: a few turned on at once, or read from the file, one by one.
    Timer {
        id: settling
        interval: 0
        onTriggered: {
            for (const card of root.cards())
                root.settle(card);
        }
    }

    component Card: Surface {
        id: card

        property string widget: ""
        default property alias content: inner.data

        readonly property var place: Machine.widgetPlaces[card.widget] ?? null
        // While it's dragged: where the pointer took it, and how far it has gone since, in the desk.
        property point grab: Qt.point(0, 0)
        property point moved: Qt.point(0, 0)
        property bool dragging: false

        function take(area: Item, mx: real, my: real): void {
            card.grab = area.mapToItem(desk, mx, my);
            card.moved = Qt.point(0, 0);
            card.dragging = true;
        }

        function follow(area: Item, mx: real, my: real): void {
            if (!card.dragging)
                return;
            const now = area.mapToItem(desk, mx, my);
            card.moved = Qt.point(now.x - card.grab.x, now.y - card.grab.y);
        }

        function leave(): void {
            if (!card.dragging)
                return;
            const x = card.x, y = card.y;
            card.dragging = false;
            card.moved = Qt.point(0, 0);
            root.drop(card, x, y);
        }

        visible: root.enabled(card.widget)
        onVisibleChanged: settling.restart()
        width: 320
        implicitHeight: inner.implicitHeight + 40
        height: implicitHeight
        x: Math.max(0, Math.min(desk.width - card.width, (card.place !== null ? card.place[0] : 0) + card.moved.x))
        y: Math.max(0, Math.min(desk.height - card.height, (card.place !== null ? card.place[1] : root.flow(card)) + card.moved.y))
        z: card.dragging ? 1 : 0
        pane: true
        radius: Tokens.drawerRadius
        color: Tokens.black
        border.width: 1
        border.color: Machine.arranging ? Tokens.ink : Tokens.line

        // A long press on a card starts arranging, and goes on moving it from there.
        MouseArea {
            id: hold
            z: -1
            anchors.fill: parent
            pressAndHoldInterval: 450
            preventStealing: true
            cursorShape: Machine.arranging ? Qt.SizeAllCursor : Qt.ArrowCursor
            onPressAndHold: mouse => {
                Machine.arranging = true;
                card.take(hold, mouse.x, mouse.y);
            }
            onPressed: mouse => {
                if (Machine.arranging)
                    card.take(hold, mouse.x, mouse.y);
            }
            onPositionChanged: mouse => card.follow(hold, mouse.x, mouse.y)
            onReleased: card.leave()
            onCanceled: card.leave()
        }

        ColumnLayout {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            spacing: 6
        }

        // While arranging, all of the card moves it, its buttons too.
        MouseArea {
            id: handle
            z: 10
            anchors.fill: parent
            visible: Machine.arranging
            preventStealing: true
            cursorShape: Qt.SizeAllCursor
            onPressed: mouse => card.take(handle, mouse.x, mouse.y)
            onPositionChanged: mouse => card.follow(handle, mouse.x, mouse.y)
            onReleased: card.leave()
            onCanceled: card.leave()
        }
    }

    PanelWindow {
        screen: root.target
        visible: root.target !== null && Machine.widgets.length > 0
        color: "transparent"

        // Under the windows, and over them while arranging: the desktop may be covered.
        WlrLayershell.layer: Machine.arranging ? WlrLayer.Top : WlrLayer.Bottom
        WlrLayershell.namespace: "nihil-widgets"
        WlrLayershell.keyboardFocus: Machine.arranging ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors { top: true; left: true; right: true; bottom: true }
        margins { top: root.deskTop; left: root.deskLeft; right: root.deskEdge; bottom: root.deskEdge }

        // Only the widgets take the pointer, but all of it while arranging.
        mask: Machine.arranging ? null : held
        Region {
            id: held
            Region { item: clockCard.visible ? clockCard : null }
            Region { item: networkCard.visible ? networkCard : null }
            Region { item: mediaCard.visible ? mediaCard : null }
        }

        SystemClock {
            id: clock
            precision: SystemClock.Minutes
        }

        Loader {
            id: backdrop
            active: Machine.glass && root.target !== null
            sourceComponent: Backdrop {
                output: root.target.name
                origin: Qt.vector2d(root.deskLeft, root.deskTop)
                screenSize: Qt.vector2d(root.target.width, root.target.height)
            }
        }

        Item {
            id: desk
            anchors.fill: parent

            property Item glassBackdrop: Machine.glass ? backdrop.item : null

            Keys.onEscapePressed: Machine.arranging = false
            Keys.onReturnPressed: Machine.arranging = false

            Connections {
                target: Machine
                function onArrangingChanged(): void {
                    if (Machine.arranging)
                        desk.forceActiveFocus();
                }
            }

            // Arranging, the windows step back; a click away from the widgets is done.
            Rectangle {
                anchors.fill: parent
                z: -2
                visible: Machine.arranging
                color: Qt.rgba(0, 0, 0, 0.55)
                radius: Tokens.drawerRadius

                MouseArea {
                    anchors.fill: parent
                    onClicked: Machine.arranging = false
                }
            }

            Card {
                id: clockCard
                widget: "clock"

                DotText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    font.pixelSize: 84
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: Case.sentence(clock.date.toLocaleString(Qt.locale(Lang.locale), Lang.dayName))
                    color: Tokens.dim
                    font.pixelSize: 12
                }

                Txt {
                    Layout.alignment: Qt.AlignHCenter
                    text: clock.date.toLocaleString(Qt.locale(Lang.locale), Lang.dateShort)
                    color: Tokens.muted
                    font.pixelSize: 13
                }
            }

            Card {
                id: networkCard
                widget: "network"

                NetRates {}

                DotScope {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    series: SysStats.rxHistory
                    secondary: SysStats.txHistory
                }
            }

            Card {
                id: mediaCard
                widget: "media"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    DotScreen {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 64
                        source: Media.art
                        pitch: 4
                        radius: 12
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label { text: Case.sentence(Media.player) || Lang.media }

                        Txt {
                            Layout.fillWidth: true
                            text: Media.title
                            font.weight: Font.Medium
                        }

                        Txt {
                            Layout.fillWidth: true
                            text: Media.artist
                            color: Tokens.dim
                            font.pixelSize: 12
                            visible: text !== ""
                        }
                    }
                }

                DotMeter {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 100
                    count: Math.max(8, Math.floor((width + 3) / 7))
                    dot: 4
                    gap: 3
                    value: Media.progress
                }

                RowLayout {
                    Layout.fillWidth: true

                    Label { text: Media.shown(Media.position) + " / " + Media.shown(Media.length) }
                    Item { Layout.fillWidth: true }

                    MediaKeys { size: 28 }
                }
            }

            Surface {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                z: 2
                visible: Machine.arranging
                width: hints.implicitWidth + 28
                height: 36
                radius: 18
                color: Tokens.black
                border.width: 1
                border.color: Tokens.line

                KeyHints {
                    id: hints
                    anchors.centerIn: parent
                    text: Lang.widgetsHint
                }
            }
        }
    }
}
