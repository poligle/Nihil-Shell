#!/usr/bin/env python3
# test_calendars.py by poligle

import datetime as dt
import fcntl
import io
import json
import os
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import calendars  # noqa: E402

# A lab on six Thursdays at 10 in Madrid's time, but not the 26th; a day off on the 20th, all
# day; a meeting at 09:00 UTC; one called off; and a floating one at 18:00, on whatever clock.
LAB = b"""BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
X-WR-CALNAME:Uni
BEGIN:VTIMEZONE
TZID:Europe/Madrid
BEGIN:STANDARD
DTSTART:19701025T030000
TZOFFSETFROM:+0200
TZOFFSETTO:+0100
RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:19700329T020000
TZOFFSETFROM:+0100
TZOFFSETTO:+0200
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU
END:DAYLIGHT
END:VTIMEZONE
BEGIN:VEVENT
UID:lab@test
DTSTART;TZID=Europe/Madrid:20261022T100000
DTEND;TZID=Europe/Madrid:20261022T120000
RRULE:FREQ=WEEKLY;COUNT=6
EXDATE;TZID=Europe/Madrid:20261126T100000
SUMMARY:Lab
LOCATION:Q2/1004
END:VEVENT
BEGIN:VEVENT
UID:off@test
DTSTART;VALUE=DATE:20261120
DTEND;VALUE=DATE:20261121
SUMMARY:Day off
END:VEVENT
BEGIN:VEVENT
UID:meet@test
DTSTART:20261118T090000Z
DURATION:PT30M
SUMMARY:  Meeting\\n  with   tutor
END:VEVENT
BEGIN:VEVENT
UID:gone@test
DTSTART:20261119T150000Z
DTEND:20261119T160000Z
STATUS:CANCELLED
SUMMARY:Called off
END:VEVENT
BEGIN:VEVENT
UID:float@test
DTSTART:20261121T180000
DTEND:20261121T190000
SUMMARY:Dinner
END:VEVENT
END:VCALENDAR
"""

OTHER = b"""BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
BEGIN:VEVENT
UID:a@other
DTSTART:20261119T080000Z
DTEND:20261119T090000Z
SUMMARY:Gym
END:VEVENT
END:VCALENDAR
"""

# The organiser's calendar, newer: the meeting moved to 11:00, the review called off, and of a
# weekly series the second moved to the afternoon and the third called off. The guest's has them
# all as they were.
ORGANISER = b"""BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
X-WR-CALNAME:Organiser
BEGIN:VEVENT
UID:meet@org
SEQUENCE:1
DTSTART:20261120T110000Z
DTEND:20261120T120000Z
SUMMARY:Meeting
END:VEVENT
BEGIN:VEVENT
UID:review@org
SEQUENCE:1
STATUS:CANCELLED
DTSTART:20261121T090000Z
DTEND:20261121T100000Z
SUMMARY:Review
END:VEVENT
BEGIN:VEVENT
UID:weekly@org
DTSTART:20261102T090000Z
DTEND:20261102T100000Z
RRULE:FREQ=WEEKLY;COUNT=4
SUMMARY:Weekly
END:VEVENT
BEGIN:VEVENT
UID:weekly@org
RECURRENCE-ID:20261109T090000Z
SEQUENCE:1
DTSTART:20261109T150000Z
DTEND:20261109T160000Z
SUMMARY:Weekly
END:VEVENT
BEGIN:VEVENT
UID:weekly@org
RECURRENCE-ID:20261116T090000Z
SEQUENCE:1
STATUS:CANCELLED
DTSTART:20261116T090000Z
DTEND:20261116T100000Z
SUMMARY:Weekly
END:VEVENT
END:VCALENDAR
"""

GUEST = b"""BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
X-WR-CALNAME:Guest
BEGIN:VEVENT
UID:meet@org
SEQUENCE:0
DTSTART:20261120T090000Z
DTEND:20261120T100000Z
SUMMARY:Meeting
END:VEVENT
BEGIN:VEVENT
UID:review@org
SEQUENCE:0
DTSTART:20261121T090000Z
DTEND:20261121T100000Z
SUMMARY:Review
END:VEVENT
BEGIN:VEVENT
UID:weekly@org
SEQUENCE:0
DTSTART:20261102T090000Z
DTEND:20261102T100000Z
RRULE:FREQ=WEEKLY;COUNT=4
SUMMARY:Weekly
END:VEVENT
END:VCALENDAR
"""

# Repeats every minute and every second of the hour, which would unfold into hundreds of thousands
# of copies, and an hourly one, which is fine.
OFTEN = b"""BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
BEGIN:VEVENT
UID:minutely@x
DTSTART:20261118T090000Z
DTEND:20261118T090100Z
RRULE:FREQ=MINUTELY
SUMMARY:Every minute
END:VEVENT
BEGIN:VEVENT
UID:seconds@x
DTSTART:20261118T100000Z
DTEND:20261118T100001Z
RRULE:FREQ=HOURLY;BYSECOND=""" + ",".join(str(i) for i in range(60)).encode() + b"""
SUMMARY:Every second of the hour
END:VEVENT
BEGIN:VEVENT
UID:hourly@x
DTSTART:20261118T120000Z
DTEND:20261118T123000Z
RRULE:FREQ=HOURLY;COUNT=3
SUMMARY:Hourly
END:VEVENT
END:VCALENDAR
"""

TODAY = dt.date(2026, 11, 18)


def at(*parts):
    return int(time.mktime(dt.datetime(*parts).timetuple()))


class Calendars(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.env = mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": self.dir + "/config", "XDG_CACHE_HOME": self.dir + "/cache",
                                                "TZ": "Europe/Madrid"})
        self.env.start()
        time.tzset()
        self.pages = {}

    def tearDown(self):
        self.env.stop()
        time.tzset()

    def reader(self, url):
        page = self.pages.get(url)
        if isinstance(page, Exception):
            raise page
        if page is None:
            raise urllib.error.URLError("nothing there")
        return page

    def add(self, url, page):
        self.pages[calendars.address(url)] = page
        return calendars.add(url, reader=self.reader)

    def test_addresses(self):
        self.assertEqual(calendars.address("  webcal://p01-caldav.icloud.com/published/2/abc  "),
                         "https://p01-caldav.icloud.com/published/2/abc")
        # The address is the secret: http is read as https, and never in clear.
        self.assertEqual(calendars.address("HTTP://example.org/a.ics"), "https://example.org/a.ics")
        self.assertEqual(calendars.address("https://calendar.google.com/calendar/ical/x/private-y/basic.ics"),
                         "https://calendar.google.com/calendar/ical/x/private-y/basic.ics")
        for bad in ["ftp://x/y.ics", "file:///etc/passwd", "javascript:alert(1)", "calendar.ics", "https://", ""]:
            self.assertIsNone(calendars.address(bad), bad)

    def test_added_once_kept_by_the_user_alone(self):
        first = self.add("webcal://example.org/uni.ics", LAB)
        self.assertEqual(first["name"], "Uni")
        self.assertEqual(self.add("https://example.org/uni.ics", LAB), first)
        path = calendars.config_path()
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
        with open(path, encoding="utf-8") as f:
            self.assertEqual(json.load(f), [{"id": first["id"], "url": "https://example.org/uni.ics", "name": "Uni"}])
        self.assertEqual(calendars.listed(), [{"id": first["id"], "name": "Uni", "host": "example.org"}])

    def test_what_isnt_added(self):
        self.assertEqual(calendars.add("ftp://example.org/a.ics", reader=self.reader), {"error": "url"})
        self.assertEqual(calendars.add("https://example.org/none.ics", reader=self.reader), {"error": "fetch"})
        self.assertEqual(self.add("https://example.org/page", b"<html>not one</html>"), {"error": "calendar"})
        self.assertEqual(calendars.listed(), [])
        self.assertFalse(os.path.exists(calendars.config_path()))

    def test_sync_unfolds_and_keeps(self):
        uni = self.add("https://example.org/uni.ics", LAB)["id"]
        gym = self.add("https://example.org/gym.ics", OTHER)["id"]
        kept = calendars.sync(today=TODAY, reader=self.reader)
        self.assertEqual([(c["name"], c["ok"]) for c in kept["calendars"]], [("Uni", True), ("example.org", True)])
        events = [(e["title"], e["start"], e["end"], e["allDay"], e["cal"]) for e in kept["events"]]
        lab = [e for e in events if e[0] == "Lab"]
        # 22 and 29 October, 5, 12 and 19 November: six counted, the 26th among them and taken out,
        # and summer time over on the 25th of October without moving the lab from ten.
        self.assertEqual([e[1] for e in lab], [at(2026, 10, 22, 10), at(2026, 10, 29, 10), at(2026, 11, 5, 10),
                                              at(2026, 11, 12, 10), at(2026, 11, 19, 10)])
        self.assertEqual(lab[0][2] - lab[0][1], 2 * 3600)
        self.assertIn(("Day off", at(2026, 11, 20), at(2026, 11, 21), True, uni), events)
        self.assertIn(("Meeting with tutor", at(2026, 11, 18, 10), at(2026, 11, 18, 10, 30), False, uni), events)
        self.assertIn(("Dinner", at(2026, 11, 21, 18), at(2026, 11, 21, 19), False, uni), events)
        self.assertIn(("Gym", at(2026, 11, 19, 9), at(2026, 11, 19, 10), False, gym), events)
        self.assertNotIn("Called off", [e[0] for e in events])
        self.assertEqual([e[1] for e in events], sorted(e[1] for e in events))
        self.assertEqual(next(e for e in kept["events"] if e["title"] == "Lab")["where"], "Q2/1004")
        self.assertEqual(stat.S_IMODE(os.stat(calendars.cache_path()).st_mode), 0o600)

    def test_one_that_cant_be_read_shows_what_it_showed(self):
        uni = self.add("https://example.org/uni.ics", LAB)["id"]
        self.add("https://example.org/gym.ics", OTHER)
        calendars.sync(today=TODAY, reader=self.reader)
        self.pages["https://example.org/uni.ics"] = urllib.error.URLError("offline")
        self.pages["https://example.org/gym.ics"] = b"BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:x\nEND:VCALENDAR\n"
        kept = calendars.sync(today=TODAY, reader=self.reader)
        self.assertEqual([(c["name"], c["ok"]) for c in kept["calendars"]], [("Uni", False), ("example.org", True)])
        titles = {e["title"] for e in kept["events"]}
        self.assertEqual(titles, {"Lab", "Day off", "Meeting with tutor", "Dinner"})
        self.assertTrue(all(e["cal"] == uni for e in kept["events"]))

    def test_one_event_in_two_calendars_shows_once(self):
        # The organiser's calendar and the guest's have the same meeting, the guest's an older copy;
        # the guest's also has it imported twice under other names, and a talk at other times.
        mine = self.add("https://example.org/mine.ics", b"""BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
BEGIN:VEVENT
UID:meet@org
SEQUENCE:0
DTSTART:20261120T090000Z
DTEND:20261120T100000Z
SUMMARY:Meeting
END:VEVENT
BEGIN:VEVENT
UID:copy-1@me
DTSTART:20261121T090000Z
DTEND:20261121T100000Z
SUMMARY:Talk
END:VEVENT
BEGIN:VEVENT
UID:copy-2@me
DTSTART:20261121T090000Z
DTEND:20261121T100000Z
SUMMARY:talk
END:VEVENT
BEGIN:VEVENT
UID:copy-3@me
DTSTART:20261122T090000Z
DTEND:20261122T100000Z
SUMMARY:Talk
END:VEVENT
END:VCALENDAR
""")["id"]
        team = self.add("https://example.org/team.ics", b"""BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
BEGIN:VEVENT
UID:meet@org
SEQUENCE:2
DTSTART:20261120T090000Z
DTEND:20261120T100000Z
SUMMARY:Meeting, room 3
END:VEVENT
END:VCALENDAR
""")["id"]
        kept = calendars.sync(today=TODAY, reader=self.reader)
        events = [(e["title"], e["start"], e["cal"]) for e in kept["events"]]
        self.assertEqual(events, [("Meeting, room 3", at(2026, 11, 20, 10), team), ("Talk", at(2026, 11, 21, 10), mine),
                                  ("Talk", at(2026, 11, 22, 10), mine)])
        self.assertTrue(all(not key.startswith("_") for e in kept["events"] for key in e))
        # And so when one can't be read: what it showed doesn't come back beside the same, read now.
        self.pages["https://example.org/team.ics"] = urllib.error.URLError("offline")
        self.pages["https://example.org/mine.ics"] = self.pages["https://example.org/mine.ics"].replace(b"Meeting", b"Meeting, room 3")
        again = calendars.sync(today=TODAY, reader=self.reader)
        self.assertEqual([e["title"] for e in again["events"]].count("Meeting, room 3"), 1)

    def test_removed(self):
        uni = self.add("https://example.org/uni.ics", LAB)["id"]
        self.assertEqual(calendars.remove("nope"), {"error": "unknown"})
        self.assertEqual(calendars.remove(uni), {"ok": True})
        self.assertEqual(calendars.listed(), [])
        self.assertEqual(calendars.sync(today=TODAY, reader=self.reader)["events"], [])

    def test_one_taken_away_while_another_is_added_stays_away(self):
        uni = self.add("https://example.org/uni.ics", LAB)["id"]

        def slow(url):
            self.assertEqual(calendars.remove(uni), {"ok": True})
            return OTHER

        gym = calendars.add("https://example.org/gym.ics", reader=slow)["id"]
        self.assertEqual([c["id"] for c in calendars.listed()], [gym])

    def test_two_added_at_once_are_both_kept(self):
        def slow(url):
            self.add("https://example.org/gym.ics", OTHER)
            return LAB

        uni = calendars.add("https://example.org/uni.ics", reader=slow)["id"]
        self.assertEqual([c["name"] for c in calendars.listed()], ["example.org", "Uni"])
        self.assertEqual(calendars.listed()[1]["id"], uni)

    def test_one_taken_away_while_they_are_read_leaves_nothing(self):
        uni = self.add("https://example.org/uni.ics", LAB)["id"]
        gym = self.add("https://example.org/gym.ics", OTHER)["id"]

        def reader(url):
            if url.endswith("/uni.ics"):
                calendars.remove(gym)
            return self.reader(url)

        kept = calendars.sync(today=TODAY, reader=reader)
        self.assertEqual([c["id"] for c in kept["calendars"]], [uni])
        self.assertTrue(kept["events"] and all(e["cal"] == uni for e in kept["events"]))

    def test_one_at_a_time(self):
        uni = self.add("https://example.org/uni.ics", LAB)["id"]
        held = os.open(calendars.config_path() + ".lock", os.O_RDWR)
        fcntl.flock(held, fcntl.LOCK_EX)
        answers = []
        worker = threading.Thread(target=lambda: answers.append(calendars.remove(uni)))
        worker.start()
        worker.join(0.3)
        self.assertTrue(worker.is_alive())
        self.assertEqual([c["id"] for c in calendars.listed()], [uni])
        os.close(held)
        worker.join(5)
        self.assertEqual(answers, [{"ok": True}])
        self.assertEqual(calendars.listed(), [])

    def test_written_whole_or_not_at_all(self):
        path = calendars.config_path()
        calendars.write_private(path, [{"id": "a"}])
        # A calendars.json.new from before, here a link to another of the user's files, is left alone.
        mine = os.path.join(self.dir, "mine")
        with open(mine, "w", encoding="utf-8") as f:
            f.write("mine")
        os.symlink(mine, path + ".new")
        with self.assertRaises(TypeError):
            calendars.write_private(path, [{"id": object()}])
        calendars.write_private(path, [{"id": "b"}])
        with open(mine, encoding="utf-8") as f:
            self.assertEqual(f.read(), "mine")
        self.assertEqual(calendars.read_json(path, None), [{"id": "b"}])
        self.assertEqual(sorted(os.listdir(os.path.dirname(path))), ["calendars.json", "calendars.json.new"])

    def test_the_newest_copy_wherever_it_went(self):
        # The guest's first, the older: the newer wins all the same.
        guest = self.add("https://example.org/guest.ics", GUEST)["id"]
        organiser = self.add("https://example.org/organiser.ics", ORGANISER)["id"]
        kept = calendars.sync(today=TODAY, reader=self.reader)
        self.assertEqual([(e["title"], e["start"]) for e in kept["events"]],
                         [("Weekly", at(2026, 11, 2, 10)), ("Weekly", at(2026, 11, 9, 16)), ("Meeting", at(2026, 11, 20, 12)),
                          ("Weekly", at(2026, 11, 23, 10))])
        self.assertEqual([e["cal"] for e in kept["events"] if e["start"] in (at(2026, 11, 9, 16), at(2026, 11, 20, 12))],
                         [organiser, organiser])
        # And on its own, the guest's shows as it is.
        calendars.remove(organiser)
        alone = calendars.sync(today=TODAY, reader=self.reader)
        self.assertEqual([(e["title"], e["start"]) for e in alone["events"]],
                         [("Weekly", at(2026, 11, 2, 10)), ("Weekly", at(2026, 11, 9, 10)), ("Weekly", at(2026, 11, 16, 10)),
                          ("Meeting", at(2026, 11, 20, 10)), ("Review", at(2026, 11, 21, 10)), ("Weekly", at(2026, 11, 23, 10))])
        self.assertTrue(all(e["cal"] == guest for e in alone["events"]))

    def test_the_cap_leaves_out_whats_over_first(self):
        now, hour = at(2026, 11, 18, 12), 3600
        over = [{"title": "over %d" % i, "start": now - (5 - i) * 24 * hour, "end": now - (5 - i) * 24 * hour + hour} for i in range(3)]
        under_way = {"title": "under way", "start": now - hour, "end": now + hour}
        coming = [{"title": "coming %d" % i, "start": now + (i + 1) * hour, "end": now + (i + 2) * hour} for i in range(3)]
        events = coming + over + [under_way]

        def titles(most):
            return [e["title"] for e in calendars.capped(events, now, most)]

        self.assertEqual(titles(5), ["over 2", "under way", "coming 0", "coming 1", "coming 2"])
        self.assertEqual(titles(3), ["under way", "coming 0", "coming 1"])
        self.assertEqual(titles(7), ["over 0", "over 1", "over 2", "under way", "coming 0", "coming 1", "coming 2"])

    def test_repeats_more_often_than_hourly_show_once(self):
        rule = calendars.icalendar.vRecur.from_ical
        for often in ["FREQ=SECONDLY", "FREQ=minutely;COUNT=5", "FREQ=HOURLY;BYSECOND=0,30", "FREQ=DAILY;BYHOUR=9;BYMINUTE=0,1"]:
            self.assertTrue(calendars.too_often(rule(often)), often)
        for fine in ["FREQ=HOURLY", "FREQ=WEEKLY;BYDAY=MO,TH", "FREQ=DAILY;BYHOUR=9;BYMINUTE=30;BYSECOND=0"]:
            self.assertFalse(calendars.too_often(rule(fine)), fine)
        self.add("https://example.org/often.ics", OFTEN)
        started = time.monotonic()
        kept = calendars.sync(today=TODAY, reader=self.reader)
        self.assertLess(time.monotonic() - started, 10)
        titles = [e["title"] for e in kept["events"]]
        self.assertEqual({title: titles.count(title) for title in titles},
                         {"Every minute": 1, "Every second of the hour": 1, "Hourly": 3})

    def test_a_run_is_bounded(self):
        probe = ("import resource, signal, sys; sys.path.insert(0, sys.argv[1]); import calendars; calendars.bounded(); "
                 "print(resource.getrlimit(resource.RLIMIT_AS)[0], signal.alarm(0))")
        memory, seconds = subprocess.run([sys.executable, "-I", "-c", probe, HERE], capture_output=True, text=True, check=True).stdout.split()
        self.assertEqual(int(memory), 1 << 30)
        self.assertTrue(115 <= int(seconds) <= 120, seconds)
        with self.assertRaises(TimeoutError):
            calendars.out_of_time(signal.SIGALRM, None)

    def test_a_slow_answer_runs_out_of_time(self):
        class Answer:
            def __init__(self, pieces, wait=0):
                self.pieces, self.wait = list(pieces), wait

            def read1(self, size):
                time.sleep(self.wait)
                return self.pieces.pop(0) if self.pieces else b""

        self.assertEqual(calendars.whole(Answer([b"BEGIN:", b"VCALENDAR"]), time.monotonic() + 5), b"BEGIN:VCALENDAR")
        # A byte at a time, each within TIMEOUT, past the deadline for the lot.
        with self.assertRaises(TimeoutError):
            calendars.whole(Answer([b"x"] * 1000, wait=0.01), time.monotonic() + 0.1)
        with mock.patch.object(calendars, "MAX_BYTES", 10), self.assertRaises(ValueError):
            calendars.whole(Answer([b"x" * 6, b"x" * 6]), time.monotonic() + 5)

    def test_redirects_only_to_https(self):
        handler = calendars.HttpsOnly()
        asked = urllib.request.Request("https://example.org/a.ics")
        for away in ["http://example.org/b.ics", "ftp://example.org/b.ics", "file:///etc/passwd"]:
            with self.assertRaises(urllib.error.HTTPError, msg=away):
                handler.redirect_request(asked, io.BytesIO(), 302, "Found", {}, away)
        self.assertEqual(handler.redirect_request(asked, io.BytesIO(), 302, "Found", {}, "https://example.net/b.ics").full_url,
                         "https://example.net/b.ics")
        # Nor does anything but https get opened at all.
        with mock.patch.dict(os.environ, {"no_proxy": "*"}):
            for other in ["http://127.0.0.1:9/a.ics", "ftp://127.0.0.1:9/a.ics", "file:///etc/hostname", "data:,BEGIN"]:
                with self.assertRaises(urllib.error.URLError, msg=other):
                    calendars.opener().open(other, timeout=2)

    def test_an_http_address_never_goes_in_clear(self):
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        server.settimeout(5)
        heard = []

        def listen():
            try:
                peer, _ = server.accept()
                peer.settimeout(2)
                heard.append(peer.recv(4096))
                peer.close()
            except OSError:
                heard.append(b"")

        listener = threading.Thread(target=listen)
        listener.start()
        with mock.patch.dict(os.environ, {"no_proxy": "*"}), self.assertRaises(OSError):
            calendars.fetch("http://127.0.0.1:%d/secret.ics" % server.getsockname()[1])
        listener.join(5)
        server.close()
        # What came was the start of a TLS handshake, which doesn't carry the path.
        self.assertTrue(heard and heard[0][:1] == b"\x16", heard)
        self.assertNotIn(b"secret", heard[0])

    def test_window(self):
        self.assertEqual(calendars.window(TODAY), (dt.date(2026, 10, 14), dt.date(2027, 1, 28)))

    def test_an_address_comes_on_stdin(self):
        self.pages["https://example.org/uni.ics"] = LAB
        out = io.StringIO()
        with mock.patch.object(calendars, "fetch", self.reader), mock.patch.object(sys, "stdin", io.StringIO("webcal://example.org/uni.ics\n")), \
                mock.patch.object(sys, "stdout", out), mock.patch.object(calendars, "bounded") as bounded:
            self.assertEqual(calendars.main(["nihil-calendar", "add"]), 0)
        bounded.assert_called_once_with()
        self.assertEqual(json.loads(out.getvalue())["name"], "Uni")
        with mock.patch.object(sys, "stderr", io.StringIO()), mock.patch.object(calendars, "bounded"):
            self.assertEqual(calendars.main(["nihil-calendar", "add", "https://example.org/uni.ics"]), 2)


if __name__ == "__main__":
    unittest.main()
