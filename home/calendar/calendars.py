#!/usr/bin/env python3
# calendars.py by poligle

"""nihil-calendar: the calendars NIHIL shows, read from their iCalendar addresses.

An address is a secret: whoever has it reads the calendar. They live in a file only the user can
read, $XDG_CONFIG_HOME/nihil/calendars.json, never in settings.json, which ends in the Nix store
for every user to read. What they hold, from a month back to two ahead, is kept for the shell in
$XDG_CACHE_HOME/nihil/calendar.json, the user's alone as well.

  nihil-calendar list          the calendars, without their addresses: [{id, name, host}]
  nihil-calendar add           an address on stdin, read once and kept if it gives a calendar:
                               {id, name}, or {error}: url, fetch or calendar
  nihil-calendar remove ID     {ok} or {error}
  nihil-calendar sync          reads them all, keeps what they hold and prints it

Every answer is JSON on stdout. An address comes on stdin, never as an argument, which anyone on
the computer could read in /proc. A calendar that can't be read keeps what was read of it before.
An event in two of them (an invitation is in the organiser's calendar and in the guest's, and a
calendar can be added by two addresses) shows once, as its newest copy has it: moved, or not at all
if called off. An address is read over https alone, redirects too; http is read as https, as
webcal is, so that the secret never goes in clear.
"""

import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
import resource
import signal
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

import icalendar
import recurring_ical_events

TIMEOUT = 20
FETCH_SECONDS = 60
CHUNK = 64 * 1024
MAX_BYTES = 20 * 1000 * 1000
MAX_MEMORY = 1 << 30
MAX_SECONDS = 120
DAYS_BEFORE = 35
DAYS_AFTER = 70
MAX_EVENTS = 3000
MAX_TEXT = 200


def home_dir(variable, fallback):
    base = os.environ.get(variable) or os.path.join(os.path.expanduser("~"), fallback)
    return os.path.join(base, "nihil")


def config_path():
    return os.path.join(home_dir("XDG_CONFIG_HOME", ".config"), "calendars.json")


def cache_path():
    return os.path.join(home_dir("XDG_CACHE_HOME", ".cache"), "calendar.json")


def read_json(path, empty):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return empty


def write_private(path, value):
    """Written whole or not at all, and readable by the user alone from its first byte: into a file
    of its own beside it, which no other write shares, and moved over it once it's all there."""
    folder = os.path.dirname(path)
    os.makedirs(folder, mode=0o700, exist_ok=True)
    fd, fresh = tempfile.mkstemp(dir=folder, prefix="." + os.path.basename(path) + ".")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(value, f, ensure_ascii=False)
        os.replace(fresh, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(fresh)
        raise


@contextlib.contextmanager
def locked():
    """add, remove and sync one at a time where they read the list and write what they make of it,
    so that none writes over what another has just changed."""
    os.makedirs(os.path.dirname(config_path()), mode=0o700, exist_ok=True)
    fd = os.open(config_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def kept_calendars():
    kept = read_json(config_path(), [])
    return [c for c in kept if isinstance(c, dict) and isinstance(c.get("id"), str) and isinstance(c.get("url"), str)] \
        if isinstance(kept, list) else []


def address(text):
    """webcal is https by another name, and http is read as https, as the address is a secret;
    anything else is no calendar's address."""
    url = str(text).strip()
    parts = urllib.parse.urlsplit(url)
    scheme = parts.scheme.lower()
    if scheme not in ("webcal", "http", "https") or not parts.netloc:
        return None
    if scheme != "https":
        url = urllib.parse.urlunsplit(("https",) + tuple(parts[1:]))
    return url


def calendar_id(url):
    return hashlib.sha256(url.encode("utf-8")).hexdigest()[:10]


def host(url):
    return urllib.parse.urlsplit(url).hostname or ""


class HttpsOnly(urllib.request.HTTPRedirectHandler):
    """A redirect is followed to https alone: to http the secret would go in clear, and ftp or the
    computer's own files are no calendar's."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urllib.parse.urlsplit(newurl).scheme.lower() != "https":
            raise urllib.error.HTTPError(newurl, code, "redirected away from https", headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def opener():
    """urllib's, without plain http, ftp, files or data: any of those is an unknown kind of address."""
    director = urllib.request.OpenerDirector()
    for handler in (urllib.request.ProxyHandler(), urllib.request.UnknownHandler(), urllib.request.HTTPSHandler(),
                    urllib.request.HTTPDefaultErrorHandler(), HttpsOnly(), urllib.request.HTTPErrorProcessor()):
        director.add_handler(handler)
    return director


def fetch(url):
    """What an address holds, over https, whole within FETCH_SECONDS and no bigger than MAX_BYTES."""
    url = address(url)
    if url is None:
        raise ValueError("no address")
    deadline = time.monotonic() + FETCH_SECONDS
    request = urllib.request.Request(url, headers={"User-Agent": "NIHIL calendar", "Accept": "text/calendar, */*"})
    with opener().open(request, timeout=TIMEOUT) as answer:
        return whole(answer, deadline)


def whole(answer, deadline):
    """An answer read as it comes, a piece at a time, by a deadline for the lot: TIMEOUT bounds only
    each wait, which a server that sends a byte every few seconds never runs out of."""
    data = bytearray()
    while True:
        if time.monotonic() > deadline:
            raise TimeoutError("too slow")
        piece = answer.read1(CHUNK)
        if not piece:
            return bytes(data)
        data += piece
        if len(data) > MAX_BYTES:
            raise ValueError("too big")


def parse(data):
    calendar = icalendar.Calendar.from_ical(data)
    if calendar.name != "VCALENDAR":
        raise ValueError("not a calendar")
    return calendar


def text(value):
    return " ".join(str(value or "").split())[:MAX_TEXT]


def stamp(moment):
    """Seconds since 1970: a time with its zone is that instant; one without (floating) and a day
    (from its midnight) are on this computer's clock, summer time included."""
    if isinstance(moment, dt.datetime):
        if moment.tzinfo is not None:
            return int(moment.timestamp())
        return int(time.mktime(moment.timetuple()))
    return int(time.mktime((moment.year, moment.month, moment.day, 0, 0, 0, 0, 0, -1)))


def too_often(rule):
    """A repeat more often than hourly, which no calendar's events have: every minute or second, or
    at more than one minute or second of the hour. Unfolded over the days kept, one such event is
    hundreds of thousands of copies, or millions, and all the memory there is."""
    if not hasattr(rule, "get"):
        return False
    every = str((rule.get("FREQ") or [""])[0]).upper()
    return every in ("SECONDLY", "MINUTELY") or len(rule.get("BYSECOND") or []) > 1 or len(rule.get("BYMINUTE") or []) > 1


def tamed(calendar):
    """The calendar without the repeats that are too often: such an event shows once, at its start."""
    for event in calendar.walk("VEVENT"):
        rules = event.get("RRULE")
        if rules is None:
            continue
        rules = rules if isinstance(rules, list) else [rules]
        kept = [rule for rule in rules if not too_often(rule)]
        if len(kept) < len(rules):
            del event["RRULE"]
            for rule in kept:
                event.add("RRULE", rule)
    return calendar


def occurrences(calendar, cal_id, first_day, last_day):
    """Each event between two days (the second left out), repeats unfolded, as the shell reads them,
    and those called off too, marked, for merged to take their older copies away."""
    calendar = tamed(calendar)
    # A repeat is told from the others of its series by the start it was given, its RECURRENCE-ID;
    # an event on its own is the same wherever a newer copy moves it, so its UID alone tells it.
    repeating = {str(event.get("UID")) for event in calendar.walk("VEVENT")
                 if any(name in event for name in ("RRULE", "RDATE", "RECURRENCE-ID"))}
    out = []
    for event in recurring_ical_events.of(calendar).between(first_day, last_day):
        begin = event.get("DTSTART")
        if begin is None:
            continue
        begin = begin.dt
        finish = event.get("DTEND")
        finish = finish.dt if finish is not None else None
        if finish is None and event.get("DURATION") is not None:
            finish = begin + event.get("DURATION").dt
        all_day = not isinstance(begin, dt.datetime)
        if finish is None:
            finish = begin + dt.timedelta(days=1) if all_day else begin
        start, end = stamp(begin), stamp(finish)
        uid = str(event.get("UID") or "")
        given = event.get("RECURRENCE-ID")
        out.append({
            "cal": cal_id,
            "title": text(event.get("SUMMARY")),
            "where": text(event.get("LOCATION")),
            "allDay": all_day,
            "start": start,
            "end": max(start, end),
            # Only to tell copies apart, and not kept.
            "_uid": uid,
            "_rid": (stamp(given.dt) if given is not None else start) if uid in repeating else None,
            "_seq": sequence(event),
            "_cancelled": str(event.get("STATUS", "")).upper() == "CANCELLED",
        })
    return out


def sequence(event):
    try:
        return int(event.get("SEQUENCE", 0))
    except (TypeError, ValueError):
        return 0


def identity(event):
    """What its copies in other calendars share: its UID and, for a repeat, which of its series."""
    return (event["_uid"], event.get("_rid")) if event.get("_uid") else None


def merged(events):
    """One of each: of the copies of an event in two calendars, the newest by SEQUENCE, wherever it
    has moved, and none if that one is called off; and of those that would show alike (the same
    title at the same times) the first."""
    newest = {}
    for event in events:
        key = identity(event)
        if key is not None and (key not in newest or event.get("_seq", 0) > newest[key].get("_seq", 0)):
            newest[key] = event
    out, shown = [], set()
    for event in events:
        key = identity(event)
        if (key is not None and newest[key] is not event) or event.get("_cancelled"):
            continue
        looks = (str(event.get("title", "")).casefold(), event.get("start"), event.get("end"), bool(event.get("allDay")))
        if looks in shown:
            continue
        shown.add(looks)
        out.append({key: value for key, value in event.items() if not key.startswith("_")})
    return out


def order(event):
    return (event.get("start", 0), event.get("end", 0), event.get("title", ""))


def capped(events, now, most=MAX_EVENTS):
    """At most so many, in order: past that, what's over goes first, as the shell shows what's to
    come, and what's left of it is the latest."""
    events = sorted(events, key=order)
    if len(events) <= most:
        return events
    coming = [e for e in events if e.get("end", 0) >= now]
    over = [e for e in events if e.get("end", 0) < now]
    room = max(0, most - len(coming))
    return sorted(over[len(over) - room:] + coming[:most], key=order)


def window(today=None):
    today = today or dt.date.today()
    return today - dt.timedelta(days=DAYS_BEFORE), today + dt.timedelta(days=DAYS_AFTER + 1)


def name_of(calendar, url):
    return text(calendar.get("X-WR-CALNAME")) or host(url)


def sync(today=None, reader=None):
    reader = reader or fetch
    first_day, last_day = window(today)
    read = []
    for cal in kept_calendars():
        try:
            calendar = parse(reader(cal["url"]))
            read.append((cal, name_of(calendar, cal["url"]), occurrences(calendar, cal["id"], first_day, last_day)))
        except Exception:  # noqa: BLE001 — a calendar that can't be read shows what it showed
            read.append((cal, None, None))
    # Kept with the list as it is now: one taken away while they were read leaves nothing behind.
    with locked():
        still = {cal["id"] for cal in kept_calendars()}
        before = read_json(cache_path(), {})
        old = before.get("events", []) if isinstance(before, dict) else []
        calendars, events = [], []
        for cal, name, found in read:
            if cal["id"] not in still:
                continue
            if found is None:
                calendars.append({"id": cal["id"], "name": cal.get("name") or host(cal["url"]), "ok": False})
                events += [e for e in old if isinstance(e, dict) and e.get("cal") == cal["id"]]
            else:
                calendars.append({"id": cal["id"], "name": name, "ok": True})
                events += found
        kept = {"updated": int(time.time()), "calendars": calendars, "events": capped(merged(events), time.time())}
        write_private(cache_path(), kept)
    return kept


def add(given, reader=None):
    reader = reader or fetch
    url = address(given)
    if url is None:
        return {"error": "url"}
    cal_id = calendar_id(url)
    for cal in kept_calendars():
        if cal["id"] == cal_id:
            return {"id": cal_id, "name": cal.get("name") or host(url)}
    try:
        data = reader(url)
    except (urllib.error.URLError, OSError, ValueError):
        return {"error": "fetch"}
    try:
        calendar = parse(data)
    except Exception:  # noqa: BLE001 — anything that isn't a calendar
        return {"error": "calendar"}
    name = name_of(calendar, url)
    # The list again, as it is once it's read: another add or a remove may have changed it meanwhile.
    with locked():
        kept = kept_calendars()
        for cal in kept:
            if cal["id"] == cal_id:
                return {"id": cal_id, "name": cal.get("name") or host(url)}
        write_private(config_path(), kept + [{"id": cal_id, "url": url, "name": name}])
    return {"id": cal_id, "name": name}


def remove(cal_id):
    with locked():
        kept = kept_calendars()
        left = [cal for cal in kept if cal["id"] != cal_id]
        if len(left) == len(kept):
            return {"error": "unknown"}
        write_private(config_path(), left)
    return {"ok": True}


def listed():
    return [{"id": cal["id"], "name": cal.get("name") or host(cal["url"]), "host": host(cal["url"])} for cal in kept_calendars()]


def out_of_time(signum, frame):
    raise TimeoutError("out of time")


def bounded():
    """However a calendar is made, a run takes at most MAX_MEMORY and MAX_SECONDS: past either, what
    it was doing fails, and a calendar it was reading keeps what it showed."""
    soft, hard = resource.getrlimit(resource.RLIMIT_AS)
    most = MAX_MEMORY if soft == resource.RLIM_INFINITY else min(MAX_MEMORY, soft)
    resource.setrlimit(resource.RLIMIT_AS, (most, hard))
    signal.signal(signal.SIGALRM, out_of_time)
    signal.alarm(MAX_SECONDS)


def main(argv):
    os.umask(0o077)
    bounded()
    if len(argv) == 2 and argv[1] == "list":
        answer = listed()
    elif len(argv) == 2 and argv[1] == "sync":
        answer = sync()
    elif len(argv) == 2 and argv[1] == "add":
        answer = add(sys.stdin.readline())
    elif len(argv) == 3 and argv[1] == "remove":
        answer = remove(argv[2])
    else:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    json.dump(answer, sys.stdout, ensure_ascii=False)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
