import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.config
import qs.services
import qs.components
import "Desk.js" as Desk
import "../nilo/Markdown.js" as Markdown

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
    // How small and how big one can be made, against its own size.
    readonly property real smallest: 0.75
    readonly property real largest: 2.5
    // A new photo's size, as it comes.
    readonly property int photoWidth: 320
    readonly property int photoHeight: 248

    // The note being written, by name, in its sheet over the windows; "" while none is.
    property string writing: ""
    readonly property var noteVoices: ({ ink: String(Tokens.ink), dim: String(Tokens.dim), code: "#E6E6E6", surface: String(Tokens.surface),
                                         mono: Tokens.fontMono, icons: Tokens.fontIcons, breaks: true, tasks: true, size: 13, line: 1.25 })

    function write(name: string): void {
        if (Machine.arranging || root.target === null)
            return;
        root.written();
        root.writing = name;
        words.text = Machine.widgetOptions[name]?.text ?? "";
        words.cursorPosition = words.length;
        Qt.callLater(() => words.forceActiveFocus());
    }

    // Kept as it's written, and once more as it's left.
    function written(): void {
        if (root.writing === "")
            return;
        saving.stop();
        if (words.text !== (Machine.widgetOptions[root.writing]?.text ?? ""))
            Machine.setWidgetOption(root.writing, "text", words.text);
        root.writing = "";
    }

    // Another note, as big as this one and beside it if there's room, written at once; none where
    // the desk has no room for it.
    function noteBeside(card: var): void {
        const at = Desk.beside({ x: card.x, y: card.y, w: card.width, h: card.height }, card.width, card.height, root.boxes(card),
                               { w: desk.width, h: desk.height }, root.spacing, root.cell);
        if (at === null) {
            Machine.notify(Lang.widgetNoRoom, "");
            return;
        }
        root.write(Machine.addWidget("note", [at.x, at.y], [Math.round(card.width), Math.round(card.height)]));
    }

    // A task's mark ticks it; any other link, of the web only, opens.
    function followNote(name: string, link: string): void {
        if (link.startsWith("task:"))
            Machine.setWidgetOption(name, "text", Markdown.toggled(Machine.widgetOptions[name]?.text ?? "", Number(link.slice(5))));
        else if (/^https?:\/\//i.test(link))
            Apps.open(link);
    }

    Connections {
        target: Machine
        function onArrangingChanged(): void {
            if (Machine.arranging)
                root.written();
        }
    }

    // One file from Files, of a kind a photo can show.
    function picture(drag: var): bool {
        return drag.hasUrls && drag.urls.length === 1 && /^file:\/\/\/.+\.(png|jpe?g|gif|bmp|webp)$/i.test(drag.urls[0].toString());
    }

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

    // The others, as boxes in the desk.
    function boxes(card: var): var {
        return root.cards().filter(other => other !== card && other.visible).map(other => ({ x: other.x, y: other.y, w: other.width, h: other.height }));
    }

    // The place on the grid nearest (x, y) where the card fits, a gap clear of the others: { x, y },
    // or null if the desk has none.
    function room(card: var, x: real, y: real): var {
        return Desk.room(card.width, card.height, x, y, root.boxes(card), { w: desk.width, h: desk.height }, root.spacing, root.cell);
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
        if (at !== null)
            Machine.placeWidgets({ [card.widget]: [at.x, at.y] });
    }

    // The size a card takes as its corner goes (dx, dy) from where it was at size `from`: its width
    // on the grid, all of it within the desk, and short of the others it would run into.
    function resized(card: var, from: real, dx: real, dy: real): real {
        return Desk.scaled({ x: card.x, y: card.y, base: card.base, tall: card.tall }, from, dx, dy, root.boxes(card),
                           { w: desk.width, h: desk.height }, { gap: root.spacing, cell: root.cell, smallest: root.smallest, largest: root.largest });
    }

    // The width and height one made to any shape takes as its corner goes (dx, dy) from `from`.
    function stretched(card: var, from: var, dx: real, dy: real): var {
        const out = Desk.stretched({ x: card.x, y: card.y, least: { w: card.least.width, h: card.least.height } }, from, dx, dy,
                                   root.boxes(card), { w: desk.width, h: desk.height }, { gap: root.spacing, cell: root.cell });
        return [out.w, out.h];
    }

    // Whether a point in the desk is on the cross, where a card dropped is taken away.
    function onBin(point: point): bool {
        return Machine.arranging && Math.hypot(point.x - (bin.x + bin.width / 2), point.y - (bin.y + bin.height / 2)) <= bin.width / 2;
    }

    // Turned on once the others have places: it goes where there's room, near the top left, and
    // stays without a place while there's none.
    function settle(card: var): void {
        if (!card.visible || card.place !== null || !root.cards().some(other => other.place !== null))
            return;
        const at = root.room(card, 0, 0);
        if (at !== null)
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

    // A reading as a row of dots: its name, how full, and the figure.
    component Gauge: RowLayout {
        id: gauge

        property string name: ""
        property real value: 0
        property string reading: ""
        property bool alert: false
        // Its name's size, bigger in a card made small; its figure's, and their columns, with it.
        property real fine: 11
        readonly property real figure: Math.max(12, gauge.fine)

        Layout.fillWidth: true
        spacing: 10

        Label {
            Layout.preferredWidth: Math.ceil(36 * gauge.fine / 11)
            text: gauge.name
            font.pixelSize: gauge.fine
        }

        DotMeter {
            Layout.fillWidth: true
            Layout.preferredWidth: 100
            count: Math.max(8, Math.floor((width + 3) / 7))
            dot: 4
            gap: 3
            value: gauge.value
            litColor: gauge.alert ? Tokens.interrupt : Tokens.ink
        }

        Txt {
            Layout.preferredWidth: Math.ceil(40 * gauge.figure / 12)
            horizontalAlignment: Text.AlignRight
            text: gauge.reading
            color: Tokens.dim
            font.pixelSize: gauge.figure
        }
    }

    component Card: Surface {
        id: card

        property string widget: ""
        // Its width as it comes: all of it grows and shrinks from there, from its corner.
        property real base: 320
        // Or, made to any shape, its width and height apart, and what's in it laid out again; at
        // the least this big.
        property bool free: false
        property size least: Qt.size(200, 120)
        default property alias content: inner.data

        readonly property var place: Machine.widgetPlaces[card.widget] ?? null
        readonly property real tall: inner.implicitHeight + 40
        // How big it is: being resized, as kept, or as it comes. A number is how many times its
        // size; [width, height], for one made to any shape.
        readonly property var shape: card.sizing !== null ? card.sizing : (Machine.widgetSizes[card.widget] ?? null)
        readonly property real times: typeof card.shape === "number" ? card.shape : 1
        readonly property bool shaped: card.free && Array.isArray(card.shape)
        readonly property real size: card.free ? 1 : card.times
        // Its smallest text, as it's drawn before the card's own scale: 11 pixels on the screen at
        // the least, however small the card is made.
        readonly property real fine: 11 / Math.min(1, card.size)
        // While it's dragged: where the pointer took it, in the desk and on the card, and how far it
        // has gone since. Over the cross it shrinks towards the pointer.
        property point grab: Qt.point(0, 0)
        property point hold: Qt.point(0, 0)
        property point moved: Qt.point(0, 0)
        property bool dragging: false
        readonly property bool binned: card.dragging && root.onBin(Qt.point(card.grab.x + card.moved.x, card.grab.y + card.moved.y))
        // Over the cross, a photo or a note goes for good, with its picture or its text.
        readonly property bool doomed: card.binned && Machine.several(card.widget)
        // While its corner is dragged: the size it's taking.
        property var sizing: null

        function take(area: Item, mx: real, my: real): void {
            card.grab = area.mapToItem(desk, mx, my);
            card.hold = area.mapToItem(card, mx, my);
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
            const x = card.x, y = card.y, binned = card.binned;
            card.dragging = false;
            card.moved = Qt.point(0, 0);
            if (binned)
                Machine.removeWidget(card.widget);
            else
                root.drop(card, x, y);
        }

        function sized(): void {
            if (card.sizing === null)
                return;
            Machine.sizeWidget(card.widget, card.sizing);
            card.sizing = null;
            root.drop(card, card.x, card.y);
        }

        visible: root.enabled(card.widget)
        onVisibleChanged: settling.restart()
        width: card.shaped ? card.shape[0] : card.base * card.times
        implicitHeight: card.shaped ? card.shape[1] : card.tall * card.times
        height: implicitHeight
        // Within the desk; while dragged, where the pointer takes it, the cross included.
        readonly property real leftAt: (card.place !== null ? card.place[0] : 0) + card.moved.x
        readonly property real topAt: (card.place !== null ? card.place[1] : root.flow(card)) + card.moved.y
        // Where it rests, while it's dragged too.
        readonly property real restX: Math.max(0, Math.min(desk.width - card.width, card.place !== null ? card.place[0] : 0))
        readonly property real restY: Math.max(0, Math.min(desk.height - card.height, card.place !== null ? card.place[1] : root.flow(card)))
        x: card.dragging ? card.leftAt : card.restX
        y: card.dragging ? card.topAt : card.restY
        z: card.dragging ? 1 : 0
        transform: Scale {
            origin.x: card.hold.x
            origin.y: card.hold.y
            xScale: card.binned ? 0.35 : 1
            yScale: xScale

            Behavior on xScale { NumberAnimation { duration: Tokens.animFast; easing.type: Easing.OutCubic } }
        }
        opacity: card.binned ? 0.75 : 1
        pane: true
        radius: Tokens.drawerRadius
        color: Tokens.black
        // Shrunk to a third over the cross, its red as thick as a line.
        border.width: card.doomed ? 3 : 1
        border.color: card.doomed ? Tokens.interrupt : Machine.arranging ? Tokens.ink : Tokens.line

        // A long press on a card starts arranging, and goes on moving it from there.
        MouseArea {
            id: hold
            z: -1
            anchors.fill: parent
            pressAndHoldInterval: 450
            preventStealing: true
            cursorShape: Machine.arranging ? Qt.SizeAllCursor : Qt.ArrowCursor
            onPressAndHold: mouse => {
                Machine.arrangeWidgets();
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

        Item {
            width: card.free ? card.width : card.base
            height: card.free ? card.height : card.tall
            scale: card.size
            transformOrigin: Item.TopLeft

            ColumnLayout {
                id: inner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: card.free ? parent.bottom : undefined
                anchors.margins: 20
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                spacing: 6
            }
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

        // While arranging, its corner makes it bigger or smaller.
        MouseArea {
            id: corner

            property point from: Qt.point(0, 0)
            property var start: null

            z: 11
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 30
            height: 30
            visible: Machine.arranging
            preventStealing: true
            cursorShape: Qt.SizeFDiagCursor
            onPressed: mouse => {
                corner.from = corner.mapToItem(desk, mouse.x, mouse.y);
                corner.start = card.free ? { w: card.width, h: card.height } : card.size;
                card.sizing = card.free ? [card.width, card.height] : card.size;
            }
            onPositionChanged: mouse => {
                if (card.sizing === null)
                    return;
                const now = corner.mapToItem(desk, mouse.x, mouse.y), dx = now.x - corner.from.x, dy = now.y - corner.from.y;
                card.sizing = card.free ? root.stretched(card, corner.start, dx, dy) : root.resized(card, corner.start, dx, dy);
            }
            onReleased: card.sized()
            onCanceled: card.sized()

            Repeater {
                model: [[0, 0], [6, 0], [0, 6]]

                Rectangle {
                    id: dot

                    required property var modelData

                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 8 + dot.modelData[0]
                    anchors.bottomMargin: 8 + dot.modelData[1]
                    width: 3
                    height: 3
                    radius: 1.5
                    color: Tokens.ink
                }
            }
        }
    }

    PanelWindow {
        screen: root.target
        visible: root.target !== null
        color: "transparent"

        // Under the windows, and over them while arranging: the desktop may be covered.
        WlrLayershell.layer: Machine.arranging ? WlrLayer.Top : WlrLayer.Bottom
        WlrLayershell.namespace: "nihil-widgets"
        WlrLayershell.keyboardFocus: Machine.arranging ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors { top: true; left: true; right: true; bottom: true }
        margins { top: root.deskTop; left: root.deskLeft; right: root.deskEdge; bottom: root.deskEdge }

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

            // Esc puts back what was there when arranging began; Enter, or a click away from them,
            // keeps what's there now.
            Keys.onEscapePressed: Machine.stopArranging(false)
            Keys.onReturnPressed: Machine.stopArranging(true)
            Keys.onEnterPressed: Machine.stopArranging(true)

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
                    onClicked: Machine.stopArranging(true)
                }
            }

            // A picture dropped from Files where there's no photo is a new one, where it fell; with no
            // room for one on the desk, it isn't taken.
            DropArea {
                id: deskDrop

                readonly property var spot: Desk.room(root.photoWidth, root.photoHeight, deskDrop.drag.x - root.photoWidth / 2,
                                                      deskDrop.drag.y - root.photoHeight / 2, root.boxes(null),
                                                      { w: desk.width, h: desk.height }, root.spacing, root.cell)

                anchors.fill: parent
                z: -1
                onEntered: drag => drag.accepted = root.picture(drag) && deskDrop.spot !== null
                onDropped: drop => {
                    if (deskDrop.spot === null)
                        return;
                    Machine.setPhoto(decodeURIComponent(drop.urls[0].toString().slice(7)), false, "", [deskDrop.spot.x, deskDrop.spot.y]);
                    drop.accept();
                }
            }

            Rectangle {
                visible: deskDrop.containsDrag && deskDrop.spot !== null
                x: deskDrop.spot?.x ?? 0
                y: deskDrop.spot?.y ?? 0
                width: root.photoWidth
                height: root.photoHeight
                radius: Tokens.drawerRadius
                color: "transparent"
                border.width: 1
                border.color: Tokens.ink
            }

            Card {
                id: clockCard
                widget: "clock"

                DotText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    font.pixelSize: 84
                }

                Txt {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Case.sentence(clock.date.toLocaleString(Qt.locale(Lang.locale), Lang.dateLong))
                    color: Tokens.dim
                    font.pixelSize: 15
                }
            }

            Card {
                id: networkCard
                widget: "network"
                free: true
                least: Qt.size(240, 112)

                NetRates {}

                DotScope {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 40
                    series: SysStats.rxHistory
                    secondary: SysStats.txHistory
                }
            }

            // The month, a dot under each day with something on it, and what comes next.
            Card {
                id: calendarCard
                widget: "calendar"
                free: true
                least: Qt.size(280, calendarCard.listTop + 36)

                readonly property date now: clock.date
                readonly property int year: calendarCard.now.getFullYear()
                readonly property int month: calendarCard.now.getMonth()
                readonly property int today: calendarCard.now.getDate()
                readonly property int first: Qt.locale(Lang.locale).firstDayOfWeek
                readonly property var days: Calendar.month(calendarCard.year, calendarCard.month, calendarCard.first)
                readonly property var busy: Calendar.busy(calendarCard.year, calendarCard.month)
                // As it comes, three of what comes next; made taller, as many as fit.
                readonly property real listTop: 20 + monthGrid.y + monthGrid.height + 12
                readonly property int rows: calendarCard.shaped
                    ? Math.max(1, Math.floor((calendarCard.height - 20 - calendarCard.listTop + 6) / 22) - (Calendar.failed ? 1 : 0)) : 3
                readonly property var next: Calendar.upcoming(calendarCard.now.getTime() / 1000, calendarCard.rows)
                readonly property real cell: ((calendarCard.free ? calendarCard.width : calendarCard.base) - 44) / 7

                Label {
                    text: Case.sentence(Qt.locale(Lang.locale).standaloneMonthName(calendarCard.month, Locale.LongFormat))
                        + " " + calendarCard.year
                }

                Grid {
                    id: monthGrid
                    Layout.topMargin: 4
                    columns: 7

                    Repeater {
                        model: 7

                        Item {
                            id: weekday

                            required property int index

                            width: calendarCard.cell
                            height: 18

                            Txt {
                                anchors.centerIn: parent
                                text: Case.sentence(Qt.locale(Lang.locale).dayName((calendarCard.first + weekday.index) % 7, Locale.NarrowFormat))
                                color: Tokens.muted
                                font.pixelSize: 11
                            }
                        }
                    }

                    Repeater {
                        model: 42

                        Item {
                            id: date

                            required property int index
                            readonly property var day: calendarCard.days[date.index]
                            readonly property bool isToday: date.day.inMonth && date.day.d === calendarCard.today

                            width: calendarCard.cell
                            height: 30
                            // A sixth week of nothing but the next month's days isn't drawn.
                            visible: date.index < 35 || calendarCard.days[35].inMonth

                            Rectangle {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -2
                                width: 24
                                height: 24
                                radius: 12
                                visible: date.isToday
                                color: Tokens.ink
                            }

                            Txt {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -2
                                text: date.day.d
                                color: date.isToday ? Tokens.black : date.day.inMonth ? Tokens.ink : Tokens.muted
                                font.pixelSize: 12
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 1
                                width: 4
                                height: 4
                                radius: 2
                                visible: date.day.inMonth && calendarCard.busy[date.day.d] === true
                                color: Tokens.dim
                            }
                        }
                    }
                }

                // What comes next, or where the calendars go; below, what room is left.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: 6
                    spacing: 6

                    Repeater {
                        model: calendarCard.next

                        RowLayout {
                            id: coming

                            required property var modelData

                            Layout.fillWidth: true
                            spacing: 12

                            Txt {
                                Layout.preferredWidth: 96
                                text: Calendar.when(coming.modelData, calendarCard.now.getTime() / 1000)
                                color: Tokens.dim
                                font.pixelSize: 12
                            }

                            Txt {
                                Layout.fillWidth: true
                                text: Calendar.title(coming.modelData)
                                font.pixelSize: 12
                            }
                        }
                    }

                    Txt {
                        Layout.fillWidth: true
                        visible: calendarCard.next.length === 0
                        text: Calendar.any ? Lang.calNothing : Lang.widgetCalendarNone
                        color: Tokens.muted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Alert {
                        Layout.fillWidth: true
                        visible: Calendar.failed
                        text: Lang.cfgCalendarUnread
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            // How the computer is: the processor, the memory, its temperature and the system's disk.
            Card {
                id: systemCard
                widget: "system"

                Gauge {
                    name: "CPU"
                    fine: systemCard.fine
                    value: SysStats.cpu
                    reading: Lang.percent.arg(Math.round(SysStats.cpu * 100))
                }

                Gauge {
                    name: "RAM"
                    fine: systemCard.fine
                    value: SysStats.mem
                    reading: Lang.percent.arg(Math.round(SysStats.mem * 100))
                }

                Gauge {
                    name: Lang.widgetSystemTemp
                    fine: systemCard.fine
                    value: SysStats.tempKnown ? Math.min(1, SysStats.temp / 100) : 0
                    reading: SysStats.tempKnown ? Math.round(SysStats.temp) + "°" : "--"
                    alert: SysStats.tempKnown && SysStats.temp >= 90
                }

                Gauge {
                    name: Lang.widgetSystemDisk
                    fine: systemCard.fine
                    value: SysStats.disk
                    reading: Lang.percent.arg(Math.round(SysStats.disk * 100))
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

                        Label {
                            Layout.fillWidth: true
                            text: Case.sentence(Media.player) || Lang.media
                            font.pixelSize: mediaCard.fine
                        }

                        Txt {
                            Layout.fillWidth: true
                            text: Media.title
                            font.weight: Font.Medium
                            font.pixelSize: Math.max(14, mediaCard.fine)
                        }

                        Txt {
                            Layout.fillWidth: true
                            text: Media.artist
                            color: Tokens.dim
                            font.pixelSize: Math.max(12, mediaCard.fine)
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

                    Label {
                        text: Media.shown(Media.position) + " / " + Media.shown(Media.length)
                        font.pixelSize: mediaCard.fine
                    }
                    Item { Layout.fillWidth: true }

                    MediaKeys { size: 28 }
                }
            }

            // The weather where it was told: now, today's highest and lowest, and the days after;
            // dashes for what hasn't been read, as the music has them.
            Card {
                id: weatherCard
                widget: "weather"

                readonly property var forecast: Weather.current ? Weather.forecast : null
                // Today at the place and the three days after it, by their dates: one read before
                // midnight starts with yesterday. A day it hasn't has no sky and no figures.
                readonly property var days: Weather.days(clock.date.getTime())
                readonly property var today: weatherCard.days[0]
                // The last read failed: with nothing read before it says so, and over what was, it
                // says when that was read.
                readonly property bool failed: Weather.placed && Weather.failed
                readonly property string readAt: {
                    const at = new Date(Weather.readAt);
                    return at.toDateString() === clock.date.toDateString() ? Qt.formatTime(at, "HH:mm")
                        : Case.sentence(at.toLocaleString(Qt.locale(Lang.locale), "ddd HH:mm"));
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Label {
                        id: weatherPlace
                        Layout.fillWidth: true
                        Layout.maximumWidth: Math.ceil(weatherPlace.implicitWidth)
                        text: Weather.placed && Weather.where.name ? Weather.where.name : Lang.cfgWidgetWeather
                        font.pixelSize: weatherCard.fine
                    }

                    Txt {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        visible: !weatherCard.failed
                        horizontalAlignment: Text.AlignRight
                        text: !Weather.placed ? Lang.widgetWeatherNoPlace
                            : weatherCard.forecast !== null ? Weather.skyName(weatherCard.forecast.now.code) : ""
                        color: Tokens.dim
                        font.pixelSize: Math.max(12, weatherCard.fine)
                    }

                    // At the right, by the edge; the hour of what's shown is never cut short.
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        Layout.minimumWidth: weatherCard.forecast !== null ? Math.ceil(weatherFailed.implicitWidth) : 0
                        implicitHeight: weatherFailed.implicitHeight
                        visible: weatherCard.failed

                        Alert {
                            id: weatherFailed
                            anchors.right: parent.right
                            width: Math.min(weatherFailed.implicitWidth, parent.width)
                            text: weatherCard.forecast !== null ? weatherCard.readAt : Lang.widgetWeatherFailed
                            font.pixelSize: weatherCard.fine
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Ico {
                        glyph: Weather.icon(weatherCard.forecast?.now.code ?? -1, weatherCard.forecast?.now.day ?? true)
                        color: weatherCard.forecast !== null ? Tokens.ink : Tokens.off
                        font.pixelSize: 40
                    }

                    DotText {
                        text: Weather.degrees(weatherCard.forecast?.now.temp ?? NaN)
                        font.pixelSize: 64
                    }

                    Item { Layout.fillWidth: true }

                    ColumnLayout {
                        spacing: 2

                        Txt {
                            Layout.alignment: Qt.AlignRight
                            text: Weather.degrees(weatherCard.today.max)
                            font.pixelSize: Math.max(14, weatherCard.fine)
                        }

                        Txt {
                            Layout.alignment: Qt.AlignRight
                            text: Weather.degrees(weatherCard.today.min)
                            color: Tokens.dim
                            font.pixelSize: Math.max(14, weatherCard.fine)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 0

                    Repeater {
                        model: weatherCard.days.slice(1)

                        ColumnLayout {
                            id: ahead

                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.maximumWidth: Number.POSITIVE_INFINITY
                            spacing: 4

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: Case.sentence(new Date(ahead.modelData.date + "T12:00:00").toLocaleString(Qt.locale(Lang.locale), "ddd"))
                                font.pixelSize: weatherCard.fine
                            }

                            Ico {
                                Layout.alignment: Qt.AlignHCenter
                                glyph: Weather.icon(ahead.modelData.code, true)
                                color: ahead.modelData.code >= 0 ? Tokens.dim : Tokens.off
                                font.pixelSize: 18
                            }

                            Row {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 6

                                Txt {
                                    text: Weather.degrees(ahead.modelData.max)
                                    font.pixelSize: Math.max(12, weatherCard.fine)
                                }

                                Txt {
                                    text: Weather.degrees(ahead.modelData.min)
                                    color: Tokens.dim
                                    font.pixelSize: Math.max(12, weatherCard.fine)
                                }
                            }
                        }
                    }
                }
            }

            // Pictures of one's own, in dots, as many as wanted.
            Repeater {
                id: photos
                model: Machine.photos

                Card {
                    id: photoCard

                    required property string modelData

                    widget: photoCard.modelData
                    free: true
                    least: Qt.size(160, 120)

                    DotScreen {
                        id: photo
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 208
                        source: Machine.photoUrl(photoCard.modelData)
                        pitch: 4
                        radius: 12

                        Txt {
                            anchors.centerIn: parent
                            width: parent.width - 48
                            visible: photo.status === Image.Null || photo.status === Image.Error
                            text: Lang.widgetPhotoHow
                            color: Tokens.dim
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                        }

                        // A picture from Files, in place of the one it has.
                        DropArea {
                            id: dropping
                            anchors.fill: parent
                            onEntered: drag => drag.accepted = root.picture(drag)
                            onDropped: drop => {
                                Machine.setPhoto(decodeURIComponent(drop.urls[0].toString().slice(7)), false, photoCard.modelData, null);
                                drop.accept();
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: dropping.containsDrag
                            color: "transparent"
                            radius: photo.radius
                            border.width: 1
                            border.color: Tokens.ink
                        }
                    }
                }
            }

            // Notes of one's own, as many as wanted: Markdown, written with the pencil.
            Repeater {
                id: notes
                model: Machine.notes

                Card {
                    id: noteCard

                    required property string modelData
                    readonly property string text: Machine.widgetOptions[noteCard.modelData]?.text ?? ""

                    widget: noteCard.modelData
                    base: 280
                    free: true
                    least: Qt.size(200, 120)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Item {
                            Layout.fillWidth: true
                        }

                        CircleButton {
                            size: 26
                            glyph: Icons.plus
                            label: Lang.noteAnother
                            onClicked: root.noteBeside(noteCard)
                        }

                        CircleButton {
                            size: 26
                            glyph: Icons.pencil
                            label: Lang.noteWrite
                            onClicked: root.write(noteCard.modelData)
                        }
                    }

                    // What doesn't fit stays below the last line that shows whole, under a fade; the
                    // wheel brings it up a line at a time.
                    Item {
                        id: notePage

                        readonly property string html: Markdown.html(noteCard.text, root.noteVoices)
                        // How far down it's been brought, at the top of a line.
                        property real scrolled: 0
                        property real wheeled: 0
                        // From there, down to the last line that shows whole.
                        readonly property real shown: {
                            const page = notePage.height, from = notePage.scrolled, limit = from + page;
                            if (lines.width <= 0 || noteCard.text === "" || lines.contentHeight <= limit)
                                return page;
                            const line = lines.positionToRectangle(lines.positionAt(0, limit));
                            return line.y > from && line.y < limit && line.y + line.height > limit ? line.y - from : page;
                        }
                        readonly property bool more: lines.contentHeight > notePage.scrolled + notePage.shown

                        // The top of the line at y, of the one after it, and of the one before it.
                        function lineAt(y: real): real {
                            return lines.positionToRectangle(lines.positionAt(0, y)).y;
                        }
                        function below(y: real): real {
                            const at = notePage.lineAt(y);
                            for (let probe = at + 2; probe < lines.contentHeight; probe += 2) {
                                if (notePage.lineAt(probe) > at)
                                    return notePage.lineAt(probe);
                            }
                            return at;
                        }
                        function above(y: real): real {
                            const at = notePage.lineAt(y);
                            for (let probe = at - 2; probe > 0; probe -= 2) {
                                if (notePage.lineAt(probe) < at)
                                    return notePage.lineAt(probe);
                            }
                            return 0;
                        }

                        function scroll(down: bool): void {
                            if (down && notePage.more)
                                notePage.scrolled = notePage.below(notePage.scrolled);
                            else if (!down && notePage.scrolled > 0)
                                notePage.scrolled = notePage.above(notePage.scrolled);
                        }

                        // Shorter than it was, it comes back down as far as all of the rest fits.
                        function fit(): void {
                            while (notePage.scrolled > 0 && lines.contentHeight - notePage.above(notePage.scrolled) <= notePage.height)
                                notePage.scrolled = notePage.above(notePage.scrolled);
                        }

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 96
                        onHeightChanged: notePage.fit()

                        Flickable {
                            width: notePage.width
                            height: notePage.shown
                            contentWidth: notePage.width
                            contentHeight: noteText.contentHeight
                            contentY: notePage.scrolled
                            interactive: false
                            clip: true

                            Text {
                                id: noteText
                                width: notePage.width
                                text: notePage.html
                                textFormat: Text.RichText
                                wrapMode: Text.Wrap
                                color: Tokens.ink
                                font.family: Tokens.fontSans
                                font.pixelSize: root.noteVoices.size
                                onLinkActivated: link => root.followNote(noteCard.modelData, link)

                                HoverHandler {
                                    cursorShape: noteText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                }
                            }
                        }

                        // The same, laid out alike and never shown: only a TextEdit tells where its
                        // lines are, and one shown would keep the press that starts arranging.
                        TextEdit {
                            id: lines
                            visible: false
                            width: notePage.width
                            text: notePage.html
                            textFormat: TextEdit.RichText
                            wrapMode: TextEdit.Wrap
                            readOnly: true
                            font: noteText.font
                            onContentHeightChanged: notePage.fit()
                        }

                        Txt {
                            width: notePage.width
                            visible: noteCard.text.trim() === ""
                            text: Lang.notePlaceholder
                            color: Tokens.muted
                            font.pixelSize: root.noteVoices.size
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            y: notePage.shown - height
                            height: Math.min(40, notePage.shown)
                            visible: notePage.more
                            gradient: Gradient {
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 1; color: Tokens.black }
                            }
                        }

                        // A notch at a time, a touchpad's small steps adding up to one.
                        WheelHandler {
                            onWheel: event => {
                                notePage.wheeled += event.angleDelta.y;
                                const notches = Math.trunc(notePage.wheeled / 120);
                                notePage.wheeled -= notches * 120;
                                for (let i = 0; i < Math.abs(notches); i++)
                                    notePage.scroll(notches < 0);
                            }
                        }
                    }
                }
            }

            // A year of GitHub contributions, a dot a day: the more, the brighter.
            Card {
                id: githubCard
                widget: "github"

                readonly property int weeks: 53
                readonly property int pitch: 8
                readonly property int dot: 5
                readonly property string today: Qt.formatDate(clock.date, "yyyy-MM-dd")
                readonly property var cells: Contributions.cells(githubCard.weeks, Qt.locale(Lang.locale).firstDayOfWeek, githubCard.today)
                // Off, then lit a step at a time to full.
                readonly property var shades: [0, 0.3, 0.52, 0.75, 1].map(f => Qt.tint(Tokens.off, Qt.rgba(Tokens.ink.r, Tokens.ink.g, Tokens.ink.b, f)))
                // The last read failed, with nothing read before to show.
                readonly property bool failed: Contributions.valid(Contributions.user) && Contributions.failed
                    && !(Contributions.current && Contributions.total >= 0)

                // A year of weeks side by side, as GitHub has it.
                base: 44 + githubCard.weeks * githubCard.pitch - (githubCard.pitch - githubCard.dot)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Label {
                        id: githubUser
                        Layout.fillWidth: true
                        Layout.maximumWidth: Math.ceil(githubUser.implicitWidth)
                        text: Contributions.user !== "" ? Contributions.user : Lang.cfgWidgetGithub
                        font.pixelSize: githubCard.fine
                    }

                    Txt {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        visible: !githubCard.failed
                        horizontalAlignment: Text.AlignRight
                        text: !Contributions.valid(Contributions.user) ? Lang.widgetGithubNoUser
                            : Contributions.current && Contributions.total === 1 ? Lang.widgetGithubTotalOne
                            : Contributions.current && Contributions.total >= 0
                                ? Lang.widgetGithubTotal.arg(Contributions.total.toLocaleString(Qt.locale(Lang.locale), "f", 0)) : ""
                        color: Tokens.dim
                        font.pixelSize: Math.max(12, githubCard.fine)
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        implicitHeight: githubFailed.implicitHeight
                        visible: githubCard.failed

                        Alert {
                            id: githubFailed
                            anchors.right: parent.right
                            width: Math.min(githubFailed.implicitWidth, parent.width)
                            text: Lang.widgetGithubFailed
                            font.pixelSize: githubCard.fine
                        }
                    }
                }

                Item {
                    Layout.topMargin: 6
                    Layout.preferredWidth: githubCard.weeks * githubCard.pitch - (githubCard.pitch - githubCard.dot)
                    Layout.preferredHeight: 7 * githubCard.pitch - (githubCard.pitch - githubCard.dot)

                    Repeater {
                        model: githubCard.weeks * 7

                        Rectangle {
                            required property int index
                            readonly property int level: githubCard.cells[index] ?? 0

                            x: Math.floor(index / 7) * githubCard.pitch
                            y: index % 7 * githubCard.pitch
                            width: githubCard.dot
                            height: githubCard.dot
                            radius: githubCard.dot / 2
                            visible: level >= 0
                            color: githubCard.shades[Math.max(0, level)]
                        }
                    }
                }
            }

            // Where a card dropped is taken away: turned off, or, a photo or a note, gone. At the foot
            // of the desk in the middle, or, with a card there, in the free place nearest to it, over
            // none while the desk has room; and still while one is dragged, as it keeps clear of
            // where each one rests.
            Surface {
                id: bin

                readonly property bool hot: root.cards().some(card => card.binned)
                readonly property bool doom: root.cards().some(card => card.doomed)
                readonly property point foot: Qt.point((desk.width - bin.width) / 2, desk.height - bin.height - 20)
                readonly property var spot: !Machine.arranging ? null
                    : Desk.room(bin.width, bin.height, bin.foot.x, bin.foot.y,
                                root.cards().filter(card => card.visible).map(card => ({ x: card.restX, y: card.restY, w: card.width, h: card.height })),
                                { w: desk.width, h: desk.height }, root.spacing, root.cell)

                x: bin.spot !== null ? bin.spot.x : bin.foot.x
                y: bin.spot !== null ? bin.spot.y : bin.foot.y
                z: 0.5
                visible: Machine.arranging
                width: 56
                height: 56
                radius: 28
                scale: bin.hot ? 1.2 : 1
                color: Tokens.black
                border.width: 1
                border.color: bin.doom ? Tokens.interrupt : bin.hot ? Tokens.ink : Tokens.line
                Accessible.name: Lang.widgetsRemove

                Behavior on scale { NumberAnimation { duration: Tokens.animFast; easing.type: Easing.OutCubic } }

                Ico {
                    anchors.centerIn: parent
                    glyph: bin.doom ? Icons.trash : Icons.close
                    font.pixelSize: 24
                    color: bin.doom ? Tokens.interrupt : bin.hot ? Tokens.ink : Tokens.dim
                }
            }
        }
    }

    // Writing a note: its sheet over the windows, where it is, with the keyboard until Esc, its
    // tick or a click away from it.
    PanelWindow {
        screen: root.target
        visible: root.target !== null && root.writing !== ""
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "nihil-note"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore

        anchors { top: true; left: true; right: true; bottom: true }
        margins { top: root.deskTop; left: root.deskLeft; right: root.deskEdge; bottom: root.deskEdge }

        MouseArea {
            anchors.fill: parent
            onClicked: root.written()
        }

        Timer {
            id: saving
            interval: 800
            onTriggered: {
                if (root.writing !== "")
                    Machine.setWidgetOption(root.writing, "text", words.text);
            }
        }

        Surface {
            id: sheet

            readonly property Item note: root.cards().find(card => card.widget === root.writing) ?? null

            x: sheet.note?.x ?? 0
            y: sheet.note?.y ?? 0
            width: sheet.note?.width ?? 280
            height: sheet.note?.height ?? 168
            radius: Tokens.drawerRadius
            color: Tokens.black
            border.width: 1
            border.color: Tokens.ink

            // A click on it stays in it.
            MouseArea {
                anchors.fill: parent
                onClicked: words.forceActiveFocus()
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true

                    Item {
                        Layout.fillWidth: true
                    }

                    CircleButton {
                        size: 26
                        glyph: Icons.check
                        label: Lang.noteDone
                        onClicked: root.written()
                    }
                }

                Flickable {
                    id: page
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: page.width
                    contentHeight: words.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    // What's being written stays in sight.
                    function follow(r: rect): void {
                        if (r.y < page.contentY)
                            page.contentY = r.y;
                        else if (r.y + r.height > page.contentY + page.height)
                            page.contentY = r.y + r.height - page.height;
                    }

                    Txt {
                        width: page.width
                        visible: words.length === 0
                        text: Lang.notePlaceholder
                        color: Tokens.muted
                        font.family: Tokens.fontMono
                        font.pixelSize: 13
                    }

                    TextEdit {
                        id: words
                        width: page.width
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        color: Tokens.ink
                        selectionColor: Tokens.ink
                        selectedTextColor: Tokens.black
                        font.family: Tokens.fontMono
                        font.pixelSize: 13
                        selectByMouse: true
                        Keys.onEscapePressed: root.written()
                        onTextChanged: {
                            if (root.writing !== "")
                                saving.restart();
                        }
                        onCursorRectangleChanged: page.follow(words.cursorRectangle)
                    }
                }
            }
        }
    }
}
