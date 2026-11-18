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

    // A reading as a row of dots: its name, how full, and the figure.
    component Gauge: RowLayout {
        id: gauge

        property string name: ""
        property real value: 0
        property string reading: ""
        property bool alert: false

        Layout.fillWidth: true
        spacing: 10

        Label {
            Layout.preferredWidth: 36
            text: gauge.name
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
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
            text: gauge.reading
            color: Tokens.dim
            font.pixelSize: 12
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
            Region { item: calendarCard.visible ? calendarCard : null }
            Region { item: networkCard.visible ? networkCard : null }
            Region { item: systemCard.visible ? systemCard : null }
            Region { item: mediaCard.visible ? mediaCard : null }
            Region { item: weatherCard.visible ? weatherCard : null }
            Region { item: photoCard.visible ? photoCard : null }
            Region { item: githubCard.visible ? githubCard : null }
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

            // The month, a dot under each day with something on it, and what comes next.
            Card {
                id: calendarCard
                widget: "calendar"

                readonly property date now: clock.date
                readonly property int year: calendarCard.now.getFullYear()
                readonly property int month: calendarCard.now.getMonth()
                readonly property int today: calendarCard.now.getDate()
                readonly property int first: Qt.locale(Lang.locale).firstDayOfWeek
                readonly property var days: Calendar.month(calendarCard.year, calendarCard.month, calendarCard.first)
                readonly property var busy: Calendar.busy(calendarCard.year, calendarCard.month)
                readonly property var next: Calendar.upcoming(calendarCard.now.getTime() / 1000, 3)
                readonly property real cell: (calendarCard.width - 44) / 7

                Label {
                    text: Case.sentence(Qt.locale(Lang.locale).standaloneMonthName(calendarCard.month, Locale.LongFormat))
                        + " " + calendarCard.year
                }

                Grid {
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
                                color: date.isToday ? Tokens.black : date.day.inMonth ? Tokens.ink : Tokens.off
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

                // What comes next, or where the calendars go.
                ColumnLayout {
                    Layout.fillWidth: true
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
                        visible: calendarCard.next.length === 0
                        text: Calendar.any ? Lang.calNothing : Lang.widgetCalendarNone
                        color: Tokens.muted
                        font.pixelSize: 12
                    }
                }
            }

            // How the computer is: the processor, the memory, its temperature and the system's disk.
            Card {
                id: systemCard
                widget: "system"

                Gauge {
                    name: "CPU"
                    value: SysStats.cpu
                    reading: Lang.percent.arg(Math.round(SysStats.cpu * 100))
                }

                Gauge {
                    name: "RAM"
                    value: SysStats.mem
                    reading: Lang.percent.arg(Math.round(SysStats.mem * 100))
                }

                Gauge {
                    name: "°C"
                    value: Math.min(1, SysStats.temp / 100)
                    reading: Math.round(SysStats.temp) + "°"
                    alert: SysStats.temp >= 90
                }

                Gauge {
                    name: Lang.widgetSystemDisk
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

            // The weather where it was told: now, today's highest and lowest, and the days after.
            Card {
                id: weatherCard
                widget: "weather"

                readonly property var forecast: Weather.current ? Weather.forecast : null
                readonly property var today: weatherCard.forecast?.days[0] ?? null

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Label {
                        text: Weather.placed && Weather.where.name ? Weather.where.name : Lang.cfgWidgetWeather
                    }

                    Item { Layout.fillWidth: true }

                    Txt {
                        text: weatherCard.forecast !== null ? Weather.skyName(weatherCard.forecast.now.code)
                            : !Weather.placed ? Lang.widgetWeatherNoPlace : Weather.failed ? Lang.widgetWeatherFailed : ""
                        color: Tokens.dim
                        font.pixelSize: 12
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: weatherCard.forecast !== null
                    spacing: 14

                    Ico {
                        glyph: Weather.icon(weatherCard.forecast?.now.code ?? -1, weatherCard.forecast?.now.day ?? true)
                        color: Tokens.ink
                        font.pixelSize: 40
                    }

                    DotText {
                        text: Weather.degrees(weatherCard.forecast?.now.temp ?? 0)
                        font.pixelSize: 64
                    }

                    Item { Layout.fillWidth: true }

                    ColumnLayout {
                        visible: weatherCard.today !== null
                        spacing: 2

                        Txt {
                            Layout.alignment: Qt.AlignRight
                            text: Weather.degrees(weatherCard.today?.max ?? 0)
                        }

                        Txt {
                            Layout.alignment: Qt.AlignRight
                            text: Weather.degrees(weatherCard.today?.min ?? 0)
                            color: Tokens.dim
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    visible: weatherCard.forecast !== null
                    spacing: 0

                    Repeater {
                        model: (weatherCard.forecast?.days ?? []).slice(1, 4)

                        ColumnLayout {
                            id: ahead

                            required property var modelData

                            Layout.fillWidth: true
                            spacing: 4

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: Case.sentence(new Date(ahead.modelData.date + "T12:00:00").toLocaleString(Qt.locale(Lang.locale), "ddd"))
                            }

                            Ico {
                                Layout.alignment: Qt.AlignHCenter
                                glyph: Weather.icon(ahead.modelData.code, true)
                                font.pixelSize: 18
                            }

                            Row {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 6

                                Txt {
                                    text: Weather.degrees(ahead.modelData.max)
                                    font.pixelSize: 12
                                }

                                Txt {
                                    text: Weather.degrees(ahead.modelData.min)
                                    color: Tokens.dim
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }

            // A picture of one's own, in dots.
            Card {
                id: photoCard
                widget: "photo"

                DotScreen {
                    id: photo
                    Layout.fillWidth: true
                    Layout.preferredHeight: 208
                    source: Machine.photoUrl
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

                    // A picture from Files: one, of a kind it can show.
                    DropArea {
                        id: dropping
                        anchors.fill: parent
                        onEntered: drag => {
                            drag.accepted = drag.hasUrls && drag.urls.length === 1
                                && /^file:\/\/\/.+\.(png|jpe?g|gif|bmp|webp)$/i.test(drag.urls[0].toString());
                        }
                        onDropped: drop => {
                            Machine.setPhoto(decodeURIComponent(drop.urls[0].toString().slice(7)), false);
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

                // A year of weeks side by side, as GitHub has it.
                width: 44 + githubCard.weeks * githubCard.pitch - (githubCard.pitch - githubCard.dot)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Label {
                        text: Contributions.user !== "" ? Contributions.user : Lang.cfgWidgetGithub
                    }

                    Item { Layout.fillWidth: true }

                    Txt {
                        text: !Contributions.valid(Contributions.user) ? Lang.widgetGithubNoUser
                            : Contributions.current && Contributions.total === 1 ? Lang.widgetGithubTotalOne
                            : Contributions.current && Contributions.total >= 0
                                ? Lang.widgetGithubTotal.arg(Contributions.total.toLocaleString(Qt.locale(Lang.locale), "f", 0))
                            : Contributions.failed ? Lang.widgetGithubFailed : ""
                        color: Tokens.dim
                        font.pixelSize: 12
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
