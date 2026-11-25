#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SOURCE=$(cd -- "$(dirname -- "$0")" && pwd)
BASE="$HOME/.local/share/desktop-switcher"
CONFIG="$HOME/.config"
mode=${1:-install}
case "$mode" in install|--check|--restore) ;; *) echo "Usage: $0 [--check [MONITORS_JSON]|--restore]" >&2; exit 2 ;; esac
dirs=(waybar hypr)

verify_lua() {
    local result
    result=$(Hyprland --verify-config -c "$1" 2>&1) && grep -qx 'config ok' <<< "$result" || {
        printf '%s\n' "$result" >&2
        return 1
    }
}

restore_profile() {
    local source=$1 dir
    for dir in "${dirs[@]}"; do
        rm -rf -- "$CONFIG/$dir" || return 1
        if [[ -e $source/$dir || -L $source/$dir ]]; then
            cp -a -- "$source/$dir" "$CONFIG/" || return 1
        fi
    done
}

if [[ $mode == --restore ]]; then
    [[ -f $BASE/install-backup/manifest ]] || { echo "No backup from this source installer found." >&2; exit 1; }
    if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        echo "Exit Hyprland and run --restore from a TTY or another desktop session." >&2
        exit 1
    fi
    exec 8>"$BASE/request.lock"
    flock -n 8
    exec 9>"$BASE/switch.lock"
    flock -n 9
    archive=$(mktemp -d "${BASE%/*}/desktop-switcher-restored.XXXXXXXX")
    mkdir -p -- "$archive/active-config"
    for dir in "${dirs[@]}"; do
        if [[ -e $CONFIG/$dir || -L $CONFIG/$dir ]]; then cp -a -- "$CONFIG/$dir" "$archive/active-config/"; fi
    done
    if ! restore_profile "$BASE/install-backup" || ! mv -T -- "$BASE" "$archive/runtime"; then
        restore_profile "$archive/active-config"
        exit 1
    fi
    printf 'Original config restored. Previous switcher and config saved in %s\n' "$archive"
    exit 0
fi

if [[ $mode == install && ( -e $BASE || -L $BASE ) ]]; then
    echo "An installation already exists at $BASE. Use a fresh account or restore that installation first." >&2
    exit 1
fi

for program in python Hyprland hyprctl g++ pkg-config jq; do command -v "$program" >/dev/null; done
work=$(mktemp -d)
stage="$work/runtime"
mutating=false
target=
finish() {
    local status=$?
    trap - EXIT
    trap '' HUP INT TERM
    if (( status != 0 )) && $mutating; then
        if restore_profile "$BASE/install-backup"; then
            printf 'Original config restored. Staged installation remains in %s.\n' "$BASE" >&2
        else
            printf 'Restore from the backup in %s/install-backup.\n' "$BASE" >&2
        fi
    fi
    if [[ -n $target && -d $target ]]; then rm -rf -- "$target"; fi
    rm -rf -- "$work"
    exit "$status"
}
trap finish EXIT
trap 'exit 1' HUP INT TERM

monitor_file=${2:-"$work/monitors.json"}
if [[ $mode == install || $# < 2 ]]; then
    hyprctl -j monitors > "$monitor_file"
    [[ $(hyprctl configerrors) != *"Couldn't"* ]]
fi

mkdir -p -- "$stage"
python "$SOURCE/tools/build_profiles.py" "$SOURCE" "$stage" "$BASE" "$monitor_file" "${CINEMATIC_MAIN_OUTPUT:-}"
python - "$stage/assets" <<'PY_ASSETS'
import sys
from pathlib import Path
from PySide6.QtGui import QImage

for image in Path(sys.argv[1]).glob("*.png"):
    if QImage(str(image)).isNull():
        raise SystemExit(f"Cannot decode wallpaper {image}")
PY_ASSETS
install -m755 "$SOURCE/runtime/switch.sh" "$stage/"
install -m644 "$SOURCE/runtime/"*.py "$stage/"
for audio in "$SOURCE/assets/audio/"*.wav; do
    [[ ! -f $audio ]] || cp -- "$audio" "$stage/"
done
read -r -a qt_flags <<< "$(pkg-config --cflags --libs Qt6Gui)"
g++ -shared -fPIC "$SOURCE/runtime/serpantinum_layer.cpp" -o "$stage/serpantinum_layer.so" \
    -lLayerShellQtInterface "${qt_flags[@]}"
for theme in win11 leyzs serpantinum; do verify_lua "$stage/profiles/$theme/hypr/hyprland.lua"; done
if [[ $mode == --check ]]; then
    echo "Profile generation, all three Lua configs, and the Qt layer bridge passed."
    exit 0
fi

for program in waybar hyprpaper swaync serpantinumd quickshell ffmpeg grim mpv flock wofi kitty; do
    command -v "$program" >/dev/null || { echo "Missing: $program" >&2; exit 1; }
done
python - <<'PY'
import gi
import numpy
from PySide6 import QtGui
gi.require_version("NM", "1.0")
from gi.repository import NM
PY
test -f /usr/share/serpantinum/src/quickshell/Shell.qml
mkdir -p -- "${BASE%/*}" "$CONFIG" "$stage/install-backup"
for dir in "${dirs[@]}"; do
    if [[ -e $CONFIG/$dir || -L $CONFIG/$dir ]]; then cp -a -- "$CONFIG/$dir" "$stage/install-backup/"; fi
done
printf 'cinematic-switcher source install\n' > "$stage/install-backup/manifest"
printf 'leyzs\n' > "$stage/current-theme"
# Copy into a private sibling directory so the final rename stays on one filesystem.
target=$(mktemp -d "${BASE%/*}/.desktop-switcher-install.XXXXXXXX")
cp -a -- "$stage/." "$target/"
mv -nT -- "$target" "$BASE"
[[ ! -e $target ]] || { echo "Another installation appeared at $BASE." >&2; exit 1; }
mutating=true
restore_profile "$BASE/profiles/leyzs"
mutating=false
echo "Installed. Log out and start a new Hyprland session to load LeyzS."
