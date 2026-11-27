const fs = require("fs");
const path = require("path");
const assert = require("assert");
const source = fs.readFileSync(path.join(__dirname, "../services/OpenMeteo.js"), "utf8").replace(".pragma library", "");
const O = new Function(source + "\nreturn { searchUrl, forecastUrl, answer, place, forecast, sky, days };")();

let passed = 0;
function test(name, body) { body(); passed++; console.log("ok", name); }

test("a name goes in the search whole, whatever it has in it", () => {
    assert.strictEqual(O.searchUrl("L'Hospitalet & co?", "es"),
        "https://geocoding-api.open-meteo.com/v1/search?count=1&format=json&language=es&name=L'Hospitalet%20%26%20co%3F");
});

test("the forecast asks for a place to four decimals", () => {
    const url = O.forecastUrl(41.387917, -2.169919);
    assert.ok(url.startsWith("https://api.open-meteo.com/v1/forecast?latitude=41.3879&longitude=-2.1699&"), url);
    assert.ok(url.includes("timezone=auto"));
});

test("what curl answered, and its status", () => {
    assert.deepStrictEqual(O.answer('{"a":1}\n200'), { status: "200", body: '{"a":1}' });
    assert.deepStrictEqual(O.answer("\n000"), { status: "000", body: "" });
    assert.deepStrictEqual(O.answer(""), { status: "", body: "" });
});

test("the first place found, with what says more of where it is", () => {
    const text = JSON.stringify({ results: [
        { name: "Barcelona", latitude: 41.38879, longitude: 2.15899, country: "España", admin1: "Cataluña" },
        { name: "Barcelona", latitude: 10.13, longitude: -64.68, country: "Venezuela" }] });
    assert.deepStrictEqual(O.place(text), { name: "Barcelona", label: "Barcelona, Cataluña, España", lat: 41.3888, lon: 2.159 });
    const city = JSON.stringify({ results: [{ name: "Madrid", latitude: 40.4, longitude: -3.7, admin1: "Madrid", country: "España" }] });
    assert.strictEqual(O.place(city).label, "Madrid, España");
});

test("none found, or not an answer, is no place", () => {
    assert.strictEqual(O.place(JSON.stringify({ generationtime_ms: 0.5 })), null);
    assert.strictEqual(O.place(JSON.stringify({ results: [{ name: "X", latitude: "41" , longitude: 2 }] })), null);
    assert.strictEqual(O.place("<html>"), null);
    assert.strictEqual(O.place(undefined), null);
});

test("now and the days, the ill-formed ones left out", () => {
    const text = JSON.stringify({
        current: { time: "2026-11-18T17:00", temperature_2m: 14.2, apparent_temperature: 12.9, weather_code: 3, is_day: 0 },
        daily: { time: ["2026-11-18", "2026-11-19", "x", "2026-11-21"], weather_code: [3, 61, 0, null],
                 temperature_2m_max: [18.1, 15, 20, 16], temperature_2m_min: [9.4, 8, 10, 7] },
    });
    assert.deepStrictEqual(O.forecast(text), {
        now: { temp: 14.2, feels: 12.9, code: 3, day: false },
        days: [{ date: "2026-11-18", code: 3, max: 18.1, min: 9.4 }, { date: "2026-11-19", code: 61, max: 15, min: 8 }],
        offset: null,
    });
});

test("a forecast with nothing for now is none", () => {
    assert.strictEqual(O.forecast(JSON.stringify({ error: true, reason: "Latitude must be in range" })), null);
    assert.strictEqual(O.forecast(""), null);
    const bare = O.forecast(JSON.stringify({ current: { temperature_2m: -0.4, weather_code: 71 } }));
    assert.deepStrictEqual(bare, { now: { temp: -0.4, feels: -0.4, code: 71, day: true }, days: [], offset: null });
});

// Read in Barcelona at 23:30 on the 25th, an hour ahead of UTC.
const late = O.forecast(JSON.stringify({
    utc_offset_seconds: 3600,
    current: { temperature_2m: 6.2, weather_code: 0, is_day: 0 },
    daily: { time: ["2026-11-25", "2026-11-26", "2026-11-27", "2026-11-28"], weather_code: [0, 3, 61, 2],
             temperature_2m_max: [9.1, 12, 11, 13], temperature_2m_min: [5, 6, 7, 4] },
}));

test("today by its date at the place, not by where it comes", () => {
    assert.strictEqual(late.offset, 3600);
    // Seen at 08:00 the morning after: today is the 26th, and the 29th wasn't read.
    const seen = O.days(late, Date.UTC(2026, 10, 26, 7, 0));
    assert.deepStrictEqual(seen.slice(0, 3).map(day => [day.date, day.code, day.max]),
                           [["2026-11-26", 3, 12], ["2026-11-27", 61, 11], ["2026-11-28", 2, 13]]);
    assert.strictEqual(seen[3].date, "2026-11-29");
    assert.ok(seen[3].code === -1 && Number.isNaN(seen[3].max) && Number.isNaN(seen[3].min));
    // Still the 25th there at 23:59, in UTC the 25th at 22:59.
    assert.strictEqual(O.days(late, Date.UTC(2026, 10, 25, 22, 59))[0].date, "2026-11-25");
});

test("a place in another time zone has a today of its own", () => {
    const tokyo = Object.assign({}, late, { offset: 9 * 3600 });
    // 20:00 UTC on the 26th is 05:00 on the 27th in Tokyo.
    assert.strictEqual(O.days(tokyo, Date.UTC(2026, 10, 26, 20, 0))[0].date, "2026-11-27");
});

test("nothing read: four days on the computer's clock, with no sky or figures", () => {
    // The last day of a year, which goes on into the next.
    const now = Date.UTC(2026, 11, 31, 12, 0);
    const local = new Date(now);
    const written = d => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    const none = O.days(null, now);
    assert.deepStrictEqual(none.map(day => day.date),
                           [0, 1, 2, 3].map(i => written(new Date(local.getFullYear(), local.getMonth(), local.getDate() + i))));
    assert.ok(none.every(day => day.code === -1 && Number.isNaN(day.max) && Number.isNaN(day.min)));
});

test("each WMO code is a sky, and one unknown is none", () => {
    const skies = { 0: "clear", 1: "fewClouds", 2: "partly", 3: "cloudy", 45: "fog", 48: "fog", 51: "drizzle", 57: "drizzle",
                    61: "rain", 67: "rain", 71: "snow", 77: "snow", 80: "showers", 82: "showers", 85: "snow", 86: "snow",
                    95: "storm", 96: "storm", 99: "storm", 4: "", 100: "" };
    for (const [code, sky] of Object.entries(skies))
        assert.strictEqual(O.sky(Number(code)), sky, code);
});

console.log(`${passed} passed`);
