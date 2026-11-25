"""Route direct animation invocations through the same lock as the shortcuts."""

import os
import sys
from pathlib import Path


def enter(theme):
    base = Path.home() / ".local/share/desktop-switcher"
    args = sys.argv[1:]
    if theme is None:
        theme = args.pop(0) if args and not args[0].startswith("-") else "win11"

    ticket = os.environ.get("DESKTOP_SWITCH_TICKET")
    if ticket:
        path = Path(ticket)
        if path.parent == base and path.name.startswith(".animation."):
            try:
                if path.read_text().strip() == theme:
                    return
            except FileNotFoundError:
                pass

    switch = base / "switch.sh"
    mode = "--animate" if "--switch" in args else "--preview"
    os.execv(switch, [str(switch), mode, theme, *(arg for arg in args if arg != "--switch")])
