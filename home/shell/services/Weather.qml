pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.theme
import "OpenMeteo.js" as OpenMeteo

// The weather where the desktop widget was told, from Open-Meteo (no key): while the widget is
// on, every half hour by the wall clock, so within a minute of the computer waking too; and when
// the network comes back after a try that didn't read, or with what was read that old.
Singleton {
    id: root

    // { place: as typed, name, label, lat, lon }, from the widget's options.
    readonly property var where: Machine.widgetOptions.weather ?? ({})
    readonly property bool placed: Number.isFinite(root.where.lat) && Number.isFinite(root.where.lon)
    readonly property string spot: root.placed ? root.where.lat + "," + root.where.lon : ""
    readonly property bool wanted: Machine.widgets.indexOf("weather") >= 0 && root.placed
    // What was last read and where: { now: { temp, feels, code, day }, days: [{ date, code, max, min }] }.
    property var forecast: null
    property string of: ""
    // When it was read, in ms since 1970.
    property real readAt: 0
    property bool failed: false
    readonly property bool current: root.forecast !== null && root.of === root.spot
    // A search for a place: the name it's for, and how the last one went.
    property string searching: ""
    property string notFound: ""
    property bool searchFailed: false
    readonly property real minute: 60 * 1000

    function sky(code: int): string {
        return OpenMeteo.sky(code);
    }

    function skyName(code: int): string {
        const sky = OpenMeteo.sky(code);
        return sky !== "" ? Lang["weather" + sky.charAt(0).toUpperCase() + sky.slice(1)] ?? "" : "";
    }

    function icon(code: int, day: bool): string {
        const sky = OpenMeteo.sky(code);
        return ({
            clear: day ? Icons.weatherClear : Icons.weatherNight,
            fewClouds: day ? Icons.weatherPartly : Icons.weatherNightPartly,
            partly: day ? Icons.weatherPartly : Icons.weatherNightPartly,
            cloudy: Icons.weatherCloudy,
            fog: Icons.weatherFog,
            drizzle: Icons.weatherDrizzle,
            rain: Icons.weatherRain,
            showers: Icons.weatherShowers,
            snow: Icons.weatherSnow,
            storm: Icons.weatherStorm,
        })[sky] ?? Icons.weatherCloudy;
    }

    // Today at the place and the three days after it, at `now` (ms), of what was read for where
    // it's told.
    function days(now: real): var {
        return OpenMeteo.days(root.current ? root.forecast : null, now);
    }

    // Read half an hour ago or more, or, by a clock put back, later than now.
    function stale(): bool {
        const age = Date.now() - root.readAt;
        return age < 0 || age >= 30 * root.minute;
    }

    // 14°, -3°: whole degrees, and no minus for what rounds to nothing.
    function degrees(value: real): string {
        return (Math.round(value) || 0) + "°";
    }

    function read(): void {
        if (!root.wanted || page.running)
            return;
        page.asked = root.spot;
        page.command = [Config.cmd.curl, "-sS", "--max-time", "20", "--proto", "=https", "-w", "\n%{http_code}",
                        OpenMeteo.forecastUrl(root.where.lat, root.where.lon)];
        page.running = true;
    }

    // From Preferences: a name to look for, kept with where it is once found; none forgets it.
    function search(name: string): void {
        const wanted = name.trim();
        root.notFound = "";
        root.searchFailed = false;
        if (wanted === "") {
            Machine.setWidgetOptions("weather", { place: "", name: "", label: "", lat: null, lon: null });
            return;
        }
        if (finder.running) {
            finder.next = wanted;
            return;
        }
        root.searching = wanted;
        finder.command = [Config.cmd.curl, "-sS", "--max-time", "20", "--proto", "=https", "-w", "\n%{http_code}",
                          OpenMeteo.searchUrl(wanted, Lang.locale.split("_")[0])];
        finder.running = true;
    }

    onSpotChanged: root.read()
    onWantedChanged: root.read()

    // A timer stands still while the computer sleeps; the wall clock doesn't.
    Timer {
        interval: root.minute
        running: root.wanted
        repeat: true
        onTriggered: {
            if (!root.failed && root.stale())
                root.read();
        }
    }

    Timer {
        id: retry
        interval: 10 * root.minute
        onTriggered: root.read()
    }

    // Once the one before has gone: a place changed while it read is read next.
    Timer {
        id: again
        interval: 50
        onTriggered: page.running ? again.restart() : root.read()
    }

    // And a name typed while another was looked for, after it.
    Timer {
        id: searchNext
        interval: 50
        onTriggered: {
            if (finder.running) {
                searchNext.restart();
                return;
            }
            const next = finder.next;
            finder.next = "";
            if (next !== "")
                root.search(next);
        }
    }

    Connections {
        target: Network
        function onConnectedChanged(): void {
            if (Network.connected && (root.failed || root.stale()))
                root.read();
        }
    }

    Process {
        id: page

        property string asked: ""

        stdout: StdioCollector {
            onStreamFinished: {
                const got = OpenMeteo.answer(text);
                const read = got.status === "200" ? OpenMeteo.forecast(got.body) : null;
                if (read === null) {
                    root.failed = true;
                    retry.restart();
                } else {
                    root.forecast = read;
                    root.of = page.asked;
                    root.readAt = Date.now();
                    root.failed = false;
                }
                if (page.asked !== root.spot)
                    again.restart();
            }
        }
    }

    Process {
        id: finder

        property string next: ""

        stdout: StdioCollector {
            onStreamFinished: {
                const got = OpenMeteo.answer(text);
                const found = got.status === "200" ? OpenMeteo.place(got.body) : null;
                if (found !== null)
                    Machine.setWidgetOptions("weather", { place: root.searching, name: found.name, label: found.label, lat: found.lat, lon: found.lon });
                else if (got.status === "200")
                    root.notFound = root.searching;
                else
                    root.searchFailed = true;
                root.searching = "";
                if (finder.next !== "")
                    searchNext.restart();
            }
        }
    }
}
