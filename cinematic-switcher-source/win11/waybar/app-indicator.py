"""Track pinned Hyprland windows and activate them from Waybar."""

import json
import mimetypes
import os
from pathlib import Path
import pwd
import re
import socket
import subprocess
import sys
import time
from urllib.parse import unquote, urlsplit
from xml.etree import ElementTree


APP_CLASSES = {
    "explorer": {"org.gnome.nautilus", "nautilus"},
    "firefox": {"org.gnome.epiphany", "epiphany", "firefox", "org.mozilla.firefox"},
    "notepad": {"org.gnome.texteditor", "gnome-text-editor"},
    "steam": {"steam", "com.valvesoftware.steam"},
    "discord": {"vesktop", "dev.vencord.vesktop"},
}

APP_COMMANDS = {
    "notepad": ("gnome-text-editor",),
    "steam": ("flatpak", "run", "com.valvesoftware.Steam"),
    "discord": ("flatpak", "run", "dev.vencord.Vesktop"),
}

MUSIC_CONFIG = Path(__file__).with_name("serpantinum-music.qml").resolve()
MUSIC_NAMESPACE = "win11-serpantinum-music-"
START_CONFIG = Path(__file__).with_name("start-menu.qml").resolve()
START_NAMESPACE = "win11-start-menu-"
NETWORK_CONFIG = Path(__file__).with_name("wifi-popup.qml").resolve()

# Close animations finish before another taskbar popup takes the focus grab.
PANELS = {
    "launcher": (START_CONFIG, "start", 0.22),
    "spotify": (MUSIC_CONFIG, "music", 0.72),
    "network": (NETWORK_CONFIG, "network", 0.22),
}


def request(directory, command):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(2)
        connection.connect(str(directory / ".socket.sock"))
        connection.sendall(command.encode("ascii"))
        with connection.makefile("rb") as reply:
            return json.load(reply)


def address(value):
    return value.lower().removeprefix("0x")


def matches(window, classes):
    return any(window.get(key, "").casefold() in classes for key in ("class", "initialClass"))


def music_environment():
    source = Path("/usr/share/serpantinum/src")
    home = Path.home()
    state_home = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state"))
    cache_home = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache"))
    state = state_home / "win11-serpantinum-music"
    runtime = Path(os.environ["XDG_RUNTIME_DIR"]) / "win11-serpantinum-music"
    music_runtime = runtime / "music"
    state.mkdir(parents=True, exist_ok=True)
    music_runtime.mkdir(parents=True, exist_ok=True)
    settings = state / "settings.json"
    if not settings.exists():
        # Disable theme generation and keep the component's settings writes private.
        settings.write_text('{"theme":{"matugen":false}}\n')

    return {
        **os.environ,
        "SERPANTINUM_DIR": str(source),
        "QS_DIR": str(source / "quickshell"),
        "QS_SETTINGS": str(settings),
        "QS_STATE_DIR": str(state),
        "QS_CACHE_DIR": str(cache_home / "win11-serpantinum-music"),
        "QS_RUN_DIR": str(runtime),
        "QS_RUN_MUSIC": str(music_runtime),
        "QS_COLORS_JSON": str(state_home / "serpantinum/qs_colors.json"),
    }


def monitor_at_cursor(monitors, cursor):
    for monitor in monitors:
        width, height = monitor["width"], monitor["height"]
        if monitor["transform"] % 2:
            width, height = height, width
        x, y, scale = monitor["x"], monitor["y"], monitor["scale"]
        if x <= cursor["x"] < x + width / scale and y <= cursor["y"] < y + height / scale:
            return monitor["name"]
    return next((monitor["name"] for monitor in monitors if monitor["focused"]), None)


def recent_files(path):
    try:
        bookmarks = ElementTree.parse(path).getroot().findall("bookmark")
    except (OSError, ElementTree.ParseError):
        return []
    bookmarks.sort(key=lambda bookmark: bookmark.get("visited") or bookmark.get("modified", ""), reverse=True)
    recent = []
    for bookmark in bookmarks:
        if any(child.tag.rsplit("}", 1)[-1] == "private" for child in bookmark.iter()):
            continue
        try:
            uri = urlsplit(bookmark.get("href", ""))
        except ValueError:
            continue
        if uri.scheme != "file" or uri.netloc not in {"", "localhost"}:
            continue
        file = Path(unquote(uri.path))
        try:
            modified = file.stat().st_mtime if file.is_file() else None
        except OSError:
            continue
        if modified is None:
            continue
        mime = mimetypes.guess_type(file)[0] or "text/plain"
        recent.append({
            "name": file.name, "folder": file.parent.name, "path": str(file),
            "modified": modified, "icon": mime.replace("/", "-"),
        })
        if len(recent) == 4:
            break
    return recent


def start_environment():
    home = Path.home()
    data = Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share")
    state = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state") / "win11-start-menu"
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    user = pwd.getpwuid(os.getuid()).pw_name
    avatar = next((path for path in (
        home / ".face", home / ".face.icon", Path("/var/lib/AccountsService/icons") / user
    ) if path.is_file()), None)
    entries = (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    entries.extend([str(data / "flatpak/exports/share"), "/var/lib/flatpak/exports/share"])
    assets = home / ".config/Win11-Theme"
    music_icon = assets / "spotify.png"
    pinned_icons = {
        app: (assets / filename).as_uri()
        for app, filename in {
            "org.gnome.Nautilus": "explorer.png",
            "org.gnome.Epiphany": "microsoft-edge.png",
            "org.gnome.TextEditor": "notepad.png",
            "com.valvesoftware.Steam": "steam.png",
            "dev.vencord.Vesktop": "discord.png",
        }.items()
        if (assets / filename).is_file()
    }
    return {
        **os.environ,
        "XDG_DATA_DIRS": ":".join(dict.fromkeys(entries)),
        "QS_START_SETTINGS": str(state / "pins.ini"),
        "QS_START_RECENT": json.dumps(recent_files(data / "recently-used.xbel")),
        "QS_START_USER": user,
        "QS_START_AVATAR": avatar.as_uri() if avatar else "",
        "QS_START_HELPER": str(Path(__file__).resolve()),
        "QS_START_MUSIC_ICON": music_icon.as_uri() if music_icon.is_file() else "multimedia-player",
        "QS_START_PIN_ICONS": json.dumps(pinned_icons),
    }


def panel_command(config):
    return ["quickshell", "--path", str(config)]


def close_panel(config, target):
    result = subprocess.run(
        [*panel_command(config), "ipc", "call", target, "close"], capture_output=True, timeout=2
    )
    return result.returncode == 0


def toggle_panel(directory, app):
    config, target, _ = PANELS[app]
    if close_panel(config, target):
        return
    output = os.environ.get("WAYBAR_OUTPUT_NAME")
    if not output or app == "network":
        monitors = request(directory, "j/monitors")
        cursor = request(directory, "j/cursorpos")
        output = monitor_at_cursor(monitors, cursor) or output
    if not output:
        raise SystemExit("Could not locate the monitor for the taskbar popup.")

    wait = max(
        (delay for name, (other_config, other_target, delay) in PANELS.items()
         if name != app and close_panel(other_config, other_target)),
        default=0,
    )
    if wait:
        time.sleep(wait)

    if app == "launcher":
        environment = start_environment()
        environment["QS_START_MONITOR"] = output
    elif app == "spotify":
        environment = music_environment()
        environment["QS_MUSIC_MONITOR"] = output
    else:
        monitor = next(item for item in monitors if item["name"] == output)
        environment = {
            **os.environ,
            "QS_WIFI_MONITOR": output,
            "QS_WIFI_X": str(round(cursor["x"] - monitor["x"])),
            "QS_WIFI_HELPER": str(Path(__file__).with_name("wifi.py").resolve()),
        }
    # Keep the popup in Waybar's command group so it closes when the bar ends.
    command = panel_command(config)
    os.execvpe(command[0], [*command, "--no-duplicate"], environment)


def activate(directory, classes, app):
    try:
        clients = request(directory, "j/clients")
    except (OSError, ValueError):
        clients = []

    windows = (
        window for window in clients
        if window.get("mapped", True) and matches(window, classes)
    )

    # Prefer an available window, then the one Hyprland focused most recently.
    def focus_order(window):
        history = window.get("focusHistoryID", -1)
        return (
            window.get("hidden", False) or window.get("minimized", False),
            history < 0,
            history,
        )

    for window in sorted(windows, key=focus_order):
        target = address(window.get("address", ""))
        if not re.fullmatch(r"[0-9a-f]+", target):
            continue
        dispatcher = f'hl.dsp.focus({{window = "address:0x{target}"}})'
        result = subprocess.run(
            ["hyprctl", "dispatch", dispatcher], capture_output=True, text=True
        )
        if result.returncode == 0 and result.stdout.strip() == "ok":
            return

    # Keep launched apps alive when Waybar reloads or the desktop profile changes.
    subprocess.Popen(APP_COMMANDS[app], start_new_session=True, stdin=subprocess.DEVNULL)


def states(events, clients, active, classes):
    app_windows = {
        address(window["address"]) for window in clients if matches(window, classes)
    }
    minimized = {
        address(window["address"]) for window in clients if window.get("minimized", False)
    }
    focused = address(active.get("address", ""))

    def current():
        if focused in app_windows and focused not in minimized:
            return "app-focused"
        return "app-running" if app_windows else "app-closed"

    yield current()
    for line in events:
        event, separator, data = line.rstrip("\n").partition(">>")
        if not separator:
            continue

        if event == "openwindow":
            fields = data.split(",", 3)
            if len(fields) == 4 and fields[2].casefold() in classes:
                app_windows.add(address(fields[0]))
        elif event == "closewindow":
            closed = address(data)
            app_windows.discard(closed)
            minimized.discard(closed)
            if focused == closed:
                focused = ""
        elif event == "activewindowv2":
            focused = address(data)
            minimized.discard(focused)
        elif event == "minimized":
            window, _, flag = data.partition(",")
            if flag == "1":
                minimized.add(address(window))
            elif flag == "0":
                minimized.discard(address(window))
        else:
            continue

        yield current()


def panel_states(events, layers, namespace, active):
    opened = any(
        layer["namespace"] == namespace
        for monitor in layers.values()
        for level in monitor["levels"].values()
        for layer in level
    )
    yield active if opened else "app-closed"
    for line in events:
        event, _, name = line.rstrip("\n").partition(">>")
        if name == namespace and event in {"openlayer", "closelayer"}:
            yield active if event == "openlayer" else "app-closed"


def watch(directory, app):
    # Subscribe before reading the initial snapshot so changes during startup are queued.
    with socket.socket(socket.AF_UNIX) as connection:
        connection.connect(str(directory / ".socket2.sock"))
        with connection.makefile("r", encoding="utf-8", errors="replace") as events:
            if app in PANELS:
                layers = request(directory, "j/layers")
                output = os.environ.get("WAYBAR_OUTPUT_NAME", "")
                if app == "launcher":
                    yield from panel_states(events, layers, START_NAMESPACE + output, "start-open")
                else:
                    yield from panel_states(events, layers, MUSIC_NAMESPACE + output, ["app-focused", "music-open"])
            else:
                clients = request(directory, "j/clients")
                active = request(directory, "j/activewindow")
                yield from states(events, clients, active, APP_CLASSES[app])


def main():
    app = sys.argv[1]
    directory = Path(os.environ["XDG_RUNTIME_DIR"]) / "hypr" / os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    if sys.argv[2:] == ["--activate"]:
        try:
            if app in {"spotify", "launcher"}:
                toggle_panel(directory, app)
            else:
                activate(directory, APP_CLASSES[app], app)
        except FileNotFoundError:
            raise SystemExit(f"Could not launch the {app} pin: required executable is missing.")
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            raise SystemExit(f"Could not open the {app} pin: {error}.")
        return

    previous = None

    def publish(state):
        nonlocal previous
        if state != previous:
            print(json.dumps({"text": " ", "tooltip": " ", "class": state}), flush=True)
            previous = state

    while True:
        try:
            for state in watch(directory, app):
                publish(state)
        except BrokenPipeError:
            return
        except (OSError, ValueError):
            pass

        # Retry only when the Hyprland connection is unavailable.
        try:
            publish("app-closed")
        except BrokenPipeError:
            return
        time.sleep(2)


if __name__ == "__main__":
    main()
