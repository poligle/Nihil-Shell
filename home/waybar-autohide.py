#!/usr/bin/env python3

import json
import os
import subprocess
import time


BAR_HEIGHT = int(os.getenv("WAYBAR_AUTOHIDE_BAR_HEIGHT", "50"))
HEIGHT_THRESHOLD = int(os.getenv("WAYBAR_AUTOHIDE_HEIGHT_THRESHOLD", "20"))
WAYBAR_PROC = os.getenv("WAYBAR_AUTOHIDE_PROCNAME", "waybar")
REFRESH_RATE = float(os.getenv("WAYBAR_AUTOHIDE_REFRESH_RATE", "0.5"))
STARTUP_TIMEOUT = float(os.getenv("WAYBAR_AUTOHIDE_STARTUP_TIMEOUT", "15"))
BAR_OUTPUTS = {
    name.strip()
    for name in os.getenv("WAYBAR_AUTOHIDE_OUTPUTS", "").split(",")
    if name.strip()
}

VISIBLE = True
HIDDEN = False


def run_quietly(command: list[str]) -> bool:
    result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return result.returncode == 0


def is_waybar_running() -> bool:
    return run_quietly(["pgrep", "-x", WAYBAR_PROC])


def is_hyprland_running() -> bool:
    return run_quietly(["hyprctl", "version"])


def wait_until(predicate, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.25)
    return predicate()


def hyprctl_json(query: str):
    return json.loads(subprocess.check_output(["hyprctl", "-j", query]))


def bar_monitors(monitors: list[dict]) -> list[dict]:
    return [
        monitor
        for monitor in monitors
        if not monitor.get("disabled", False)
        and (not BAR_OUTPUTS or monitor["name"] in BAR_OUTPUTS)
    ]


def logical_box(monitor: dict) -> tuple[float, float, float, float]:
    width, height = monitor["width"], monitor["height"]
    if monitor.get("transform", 0) % 2 == 1:
        width, height = height, width
    scale = monitor.get("scale", 1) or 1
    return monitor["x"], monitor["y"], width / scale, height / scale


def cursor_position() -> tuple[float, float]:
    output = subprocess.check_output(["hyprctl", "cursorpos"], text=True)
    x, y = output.strip().split(",")
    return float(x), float(y)


def cursor_near_bar(monitors: list[dict], state: bool) -> bool:
    x, y = cursor_position()
    reach = BAR_HEIGHT if state == VISIBLE else 0

    for monitor in monitors:
        left, top, width, height = logical_box(monitor)
        if left <= x < left + width and top <= y < top + height:
            return y - top <= reach

    return False


def window_under_bar(monitors: list[dict], clients: list[dict]) -> bool:
    monitors_by_id = {monitor["id"]: monitor for monitor in monitors}
    active_workspaces = {monitor["activeWorkspace"]["id"] for monitor in monitors}

    for client in clients:
        if not client.get("mapped") or client.get("hidden") or client.get("fullscreen"):
            continue

        monitor = monitors_by_id.get(client.get("monitor"))
        if monitor is None or client["workspace"]["id"] not in active_workspaces:
            continue

        top = client["at"][1] - monitor["y"]
        if top < BAR_HEIGHT + HEIGHT_THRESHOLD and top + client["size"][1] > 0:
            return True

    return False


def next_state(state: bool) -> bool:
    monitors = bar_monitors(hyprctl_json("monitors"))

    if cursor_near_bar(monitors, state):
        return VISIBLE

    if window_under_bar(monitors, hyprctl_json("clients")):
        return HIDDEN

    return VISIBLE


def main():
    if not wait_until(is_waybar_running, STARTUP_TIMEOUT):
        print("Waybar is not running. Exiting.")
        return

    if not is_hyprland_running():
        print("Hyprland is not running. Exiting.")
        return

    state = VISIBLE if os.getenv("WAYBAR_AUTOHIDE_STATE", "1") == "1" else HIDDEN

    while True:
        try:
            target = next_state(state)
        except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError, ValueError):
            target = state

        if target != state:
            subprocess.run(["pkill", "-USR1", "-x", WAYBAR_PROC], check=False)
            state = target

        time.sleep(REFRESH_RATE)


if __name__ == "__main__":
    main()
