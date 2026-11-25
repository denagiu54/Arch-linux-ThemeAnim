"""Generate output configuration and original fallback wallpapers for a local install."""

import json
import re
import shutil
import struct
import sys
import zlib
from pathlib import Path

THEMES = ("win11", "leyzs", "serpantinum")


def chunk(kind, data):
    return (struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data)))


def wallpaper(path, theme):
    width, height = 960, 600
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            if theme == "win11":
                glow = max(0, 1 - (((x - 570) / 550) ** 2 + ((y - 250) / 360) ** 2))
                color = (int(14 + 18 * glow), int(20 + 38 * glow), int(33 + 64 * glow))
            else:
                ridge = 325 - abs((x % 410) - 205) * 0.65
                shade = int(25 + 25 * y / height) if y > ridge else int(79 - 34 * y / height)
                color = (shade, shade, shade)
            rows.extend(color)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(rows))
                     + chunk(b"IEND", b""))


def main():
    root, stage, destination, monitor_file = map(Path, sys.argv[1:5])
    outputs = [m for m in json.loads(monitor_file.read_text()) if not m.get("disabled")]
    if not outputs or any(not re.fullmatch(r"[A-Za-z0-9_.-]+", m["name"]) for m in outputs):
        raise SystemExit("Expected at least one active Hyprland output with a supported connector name.")

    primary = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] else next(
        (m["name"] for m in outputs if re.match(r"^(eDP|LVDS)-", m["name"])),
        outputs[0]["name"],
    )
    if primary not in {m["name"] for m in outputs}:
        raise SystemExit(f"Main animation output {primary} is not active.")

    (stage / "main-output").write_text(primary + "\n")
    assets = stage / "assets"
    assets.mkdir()
    for theme in THEMES:
        profile = stage / "profiles" / theme
        shutil.copytree(root / theme, profile)
        monitors = []
        for output in outputs:
            refresh = float(output.get("refreshRate") or 0)
            mode = f'{int(output["width"])}x{int(output["height"])}@{refresh:.3f}' if refresh else "preferred"
            monitors.append(
                'hl.monitor({ output = "%s", mode = "%s", position = "%dx%d", scale = %s, transform = %d })'
                % (output["name"], mode, output["x"], output["y"], float(output["scale"]),
                   int(output.get("transform", 0))))
        monitors.append('hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })')
        (profile / "hypr/monitors.lua").write_text("\n".join(monitors) + "\n")
        if theme == "serpantinum":
            continue

        image = assets / f"{theme}.png"
        custom = root / "assets" / image.name
        if custom.is_file():
            shutil.copy2(custom, image)
        else:
            wallpaper(image, theme)
        path = destination / "assets" / image.name
        if any(c in str(path) for c in "\n\r#"):
            raise SystemExit("The runtime path contains characters unsupported by the Hyprpaper configuration.")
        # The wildcard block also covers outputs connected after installation.
        (profile / "hypr/hyprpaper.conf").write_text(
            f"splash = false\nipc = true\n\nwallpaper {{\n    monitor =\n"
            f"    path = {path}\n    fit_mode = cover\n}}\n"
        )


if __name__ == "__main__":
    main()
