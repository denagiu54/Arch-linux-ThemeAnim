#!/usr/bin/env bash
set -Eeuo pipefail

BASE="$HOME/.local/share/desktop-switcher"
PROFILES="$BASE/profiles"
CONFIG="$HOME/.config"
SELF="$BASE/switch.sh"
STATE="$BASE/current-theme"

valid_theme() {
    case "$1" in win11|leyzs|serpantinum) return 0 ;; *) return 1 ;; esac
}

current_theme() {
    local theme
    theme=$(cat "$STATE")
    valid_theme "$theme" || { echo "Invalid current-theme: $theme" >&2; return 1; }
    printf '%s\n' "$theme"
}

mode=${1:-}
case "$mode" in
    --animate|--preview|--login|--request|--render|--apply|--start)
        shift
        theme=${1:-}
        shift || true
        ;;
    *) theme=$mode; mode=direct ;;
esac
valid_theme "$theme" || { echo "Expected win11, leyzs or serpantinum" >&2; exit 2; }

# flock owns the descriptor. --close prevents scripts and desktop daemons
# from inheriting it, including daemons that detach or outlive the switch.
case "$mode" in
    --animate|--preview)
        exec flock -n -E 0 --close "$BASE/request.lock" "$SELF" --render "$theme" "$mode" "$@"
        ;;
    --login)
        exec flock --close "$BASE/request.lock" "$SELF" --start "$theme"
        ;;
    direct)
        if [[ ${DESKTOP_SWITCH_TICKET:-} == "$BASE"/.animation.* ]]; then
            exec flock --close "$BASE/switch.lock" "$SELF" --apply "$theme"
        fi
        exec flock -n -E 0 --close "$BASE/request.lock" "$SELF" --request "$theme"
        ;;
    --request)
        old_theme=$(current_theme)
        [[ $old_theme != "$theme" ]] || exit 0
        exec flock -n --close "$BASE/switch.lock" "$SELF" --apply "$theme"
        ;;
    --render)
        render_mode=$1
        shift
        if [[ $render_mode == --animate ]]; then
            old_theme=$(current_theme)
            [[ $old_theme != "$theme" ]] || exit 0
        fi
        # Detect a still-held lock from the previous switcher before rendering.
        flock -n --close "$BASE/switch.lock" true
        ticket=$(mktemp "$BASE/.animation.XXXXXXXX")
        printf '%s\n' "$theme" > "$ticket"
        trap 'rm -f -- "$ticket"' EXIT
        args=()
        [[ $render_mode != --animate ]] || args+=(--switch)
        status=0
        DESKTOP_SWITCH_TICKET="$ticket" python "$BASE/transition.py" "$theme" "${args[@]}" "$@" || status=$?
        # Windows can finish its overlay before its background transaction.
        # A late child must acquire the transaction lock and find a valid ticket.
        flock --close "$BASE/switch.lock" rm -f -- "$ticket"
        if [[ $render_mode == --animate && $(current_theme) != "$theme" ]]; then
            echo "Theme did not change to $theme. See the switch logs in $BASE." >&2
            exit 1
        fi
        exit "$status"
        ;;
esac

cinematic_dir=
if [[ -n ${DESKTOP_SWITCH_TICKET:-} ]]; then
    [[ $DESKTOP_SWITCH_TICKET == "$BASE"/.animation.* && -f $DESKTOP_SWITCH_TICKET &&
        $(<"$DESKTOP_SWITCH_TICKET") == "$theme" ]] || exit 1
    if [[ $theme == serpantinum && ${SERPANTINUM_CINEMATIC_DIR:-} == "$BASE"/.serpantinum-frames.* ]]; then
        cinematic_dir=$SERPANTINUM_CINEMATIC_DIR
    fi
    unset DESKTOP_SWITCH_TICKET SERPANTINUM_CINEMATIC_DIR
fi

: "${HYPRLAND_INSTANCE_SIGNATURE:?Run from the Hyprland session}"
serpantinum_root=/usr/share/serpantinum/src
serpantinum_qml="$serpantinum_root/quickshell/Shell.qml"
session=(-u "$UID" --env "HYPRLAND_INSTANCE_SIGNATURE=$HYPRLAND_INSTANCE_SIGNATURE")
running() {
    pgrep "${session[@]}" -r R,S,D,I,T,t -x "$1" >/dev/null
}

stop_process() {
    local name=$1 attempt
    if running "$name"; then
        pkill "${session[@]}" -x "$name" || true
        for ((attempt = 0; attempt < 20; attempt++)); do
            running "$name" || return 0
            sleep 0.05
        done
        echo "$name did not stop" >&2
        return 1
    fi
}

stop_shell() {
    local leaving=$1 app panel
    case "$leaving" in
        serpantinum)
            SERPANTINUM_DIR="$serpantinum_root" timeout 5s serpantinumd stop >"$BASE/serpantinum-stop.log" 2>&1 || return
            ;;
        win11|leyzs)
            stop_process waybar || return
            if [[ $leaving == win11 ]]; then
                for panel in start-menu.qml serpantinum-music.qml wifi-popup.qml; do
                    timeout 1s quickshell --path "$CONFIG/waybar/$panel" kill >/dev/null 2>&1 || true
                done
            fi
            for app in wofi wlogout swaync hyprpaper mpvpaper; do
                stop_process "$app" || return
            done
            ;;
    esac
}

start_shell() {
    local selected=$1 app pid
    local -a started=()
    if [[ $selected == serpantinum ]]; then
        command -v serpantinumd >/dev/null && command -v quickshell >/dev/null || return 1
        if ! serpantinumd status >/dev/null 2>&1; then
            SERPANTINUM_DIR="$serpantinum_root" \
                nohup serpantinumd start </dev/null >"$BASE/serpantinum.log" 2>&1 &
            started+=("$!")
        fi
    else
        for app in hyprpaper swaync waybar; do
            command -v "$app" >/dev/null || return 1
            if ! running "$app"; then
                nohup "$app" </dev/null >"$BASE/$app.log" 2>&1 &
                started+=("$!")
            fi
        done
    fi
    if (( ${#started[@]} > 0 )); then
        sleep 0.35
        for pid in "${started[@]}"; do
            [[ -r /proc/$pid/stat && ! $(<"/proc/$pid/stat") =~ \)\ Z ]] || { echo "Desktop service exited. See $BASE/*.log" >&2; return 1; }
        done
    fi
}

if [[ $mode == --start ]]; then
    # The loaded Lua profile identifies the selected desktop on login.
    start_shell "$theme" >>"$BASE/login.log" 2>&1
    exit
fi

cinematic_outputs=()
check_layers() {
    local phase=$1 shell_pid=${2:-0} layers output needs_bar
    layers=$(timeout 1s hyprctl -j layers) || return 1
    for output in "${cinematic_outputs[@]}"; do
        jq -e --arg output "$output" '
            .[$output].levels["3"][-1] |
            .namespace == "serpantinum-cinematic" and .w > 0 and .h > 0
        ' <<< "$layers" >/dev/null || return 1
        if [[ $phase == wallpaper ]]; then
            needs_bar=true
            if [[ -r $CONFIG/serpantinum/settings.json ]]; then
                needs_bar=$(jq -r --arg output "$output" '
                    if (.barMonitors | type) == "array" then
                        .barMonitors | index($output) != null
                    else true end
                ' "$CONFIG/serpantinum/settings.json") || return 1
            fi
            jq -e --arg output "$output" --argjson needs_bar "$needs_bar" --argjson pid "$shell_pid" '
                .[$output].levels as $levels |
                any(($levels["0"] // [])[]; .namespace == "wallpaper-bg"
                    and .pid == $pid and .w > 0 and .h > 0 and .alpha >= 0.99)
                and (if $needs_bar then
                    any(($levels // {})[][]; .namespace == "quickshell"
                        and .pid == $pid and .w > 0 and .h > 0 and .alpha >= 0.99)
                else true end)
                and all(($levels["3"] // [])[]; .namespace != "welcome-guide")
            ' <<< "$layers" >/dev/null || return 1
        fi
    done
}

official_serpantinum_pid() {
    local instances
    instances=$(timeout 1s quickshell -p "$serpantinum_qml" list --json 2>/dev/null) || return 1
    jq -er --arg qml "$serpantinum_qml" '
        [.[] | select(.config_path == $qml) | .pid] |
        select(length == 1) | .[0] | select(type == "number" and . > 0)
    ' <<< "$instances"
}

read_serpantinum_wallpapers() {
    local shell_pid=$1 output path
    for output in "${cinematic_outputs[@]}"; do
        path=$(timeout 1s quickshell -p "$serpantinum_qml" ipc --pid "$shell_pid" \
            call wallpaper getWallpaperPath "$output" 2>/dev/null) || return 1
        [[ $path == /* && -f $path && -r $path ]] || return 1
        printf '%s\n' "$path" > "$cinematic_dir/source-$output"
    done
}

wait_for_serpantinum() {
    local deadline=$((SECONDS + 8)) desktop_ready=false shell_pid
    while (( SECONDS < deadline )); do
        if $desktop_ready; then
            if [[ -e $cinematic_dir/wallpaper-error ]]; then
                echo "The cinematic renderer could not decode the selected wallpaper." >&2
                return 1
            fi
            if [[ -e $cinematic_dir/wallpaper-loaded ]] &&
                [[ "$(official_serpantinum_pid)" == "$shell_pid" ]] &&
                check_layers wallpaper "$shell_pid"; then return 0; fi
        elif shell_pid=$(official_serpantinum_pid) &&
            check_layers wallpaper "$shell_pid" && read_serpantinum_wallpapers "$shell_pid"; then
            printf 'Official Serpantinum shell ready (PID %s).\n' "$shell_pid"
            touch "$cinematic_dir/desktop-ready"
            desktop_ready=true
        fi
        sleep 0.06
    done
    echo "Official Serpantinum wallpaper handoff timed out on: ${cinematic_outputs[*]}" >&2
    return 1
}

old_theme=$(current_theme)
[[ $old_theme != "$theme" ]] || exit 0
if [[ -n $cinematic_dir ]]; then
    if [[ ! -f $HOME/.local/state/serpantinum/first_launch.done ]]; then
        echo "Complete Serpantinum's first-run setup before using its cinematic switch." >&2
        exit 1
    fi
    mapfile -t cinematic_outputs < "$cinematic_dir/outputs"
    if (( ${#cinematic_outputs[@]} == 0 )) || ! check_layers overlay; then
        echo "The cinematic overlay is not mapped above the desktop on every output." >&2
        exit 1
    fi
fi
profile="$PROFILES/$theme"
dirs=(waybar hypr)
changed=()
saved=()
installed=()

verify_lua() {
    local result
    result=$(Hyprland --verify-config -c "$1" 2>&1) || { printf '%s\n' "$result" >&2; return 1; }
    if ! grep -qx 'config ok' <<< "$result"; then
        printf '%s\n' "$result" >&2
        return 1
    fi
}

reload_config() {
    local result
    result=$(hyprctl reload config-only) && [[ $result == ok ]] || return 1
    result=$(hyprctl configerrors) || return 1
    if [[ -n ${result//[[:space:]]/} ]]; then
        printf '%s\n' "$result" >&2
        return 1
    fi
}

case "$theme" in
    win11) wallpaper="$BASE/assets/win11.png" ;;
    leyzs) wallpaper="$BASE/assets/leyzs.png" ;;
    serpantinum) wallpaper= ;;
esac
if [[ -n $wallpaper && ! -r $wallpaper ]]; then
    echo "Missing theme wallpaper: $wallpaper" >&2
    exit 1
fi
if [[ $theme != serpantinum ]]; then
    for program in hyprpaper waybar swaync; do command -v "$program" >/dev/null; done
    test -r "$profile/hypr/hyprpaper.conf"
    test -r "$profile/waybar/style.css"
    [[ -r $profile/waybar/config || -r $profile/waybar/config.jsonc ]]
else
    for program in serpantinumd quickshell; do command -v "$program" >/dev/null; done
fi
verify_lua "$profile/hypr/hyprland.lua"
# Fail before touching the desktop if the current compositor cannot be reached.
hyprctl configerrors >/dev/null
work=$(mktemp -d "$CONFIG/.desktop-switch.XXXXXXXX")
backup=
shell_stopped=false
starting_target=false
committed=false
state_tmp=

finish() {
    local status=$? i dir recovery_failed=false
    trap - EXIT
    trap '' HUP INT TERM
    set +e
    if ! $committed && $shell_stopped; then
        echo "Theme switch failed. Restoring $old_theme from $backup." >&2
        if $starting_target; then stop_shell "$theme" || recovery_failed=true; fi
        for ((i = ${#installed[@]} - 1; i >= 0; i--)); do
            dir=${installed[i]}
            if [[ ! -e $work/new/$dir && ! -L $work/new/$dir ]]; then
                rm -rf -- "$CONFIG/$dir" || recovery_failed=true
            fi
        done
        for dir in "${saved[@]}"; do
            if [[ -e $work/old/$dir || -L $work/old/$dir ]]; then
                mv -T -- "$work/old/$dir" "$CONFIG/$dir" || recovery_failed=true
            fi
        done
        reload_config || recovery_failed=true
        start_shell "$old_theme" || recovery_failed=true
    fi
    if [[ -n $state_tmp ]]; then rm -f -- "$state_tmp"; fi
    if $recovery_failed; then
        echo "Rollback needs attention. Originals: $backup. Staging: $work." >&2
        exit 1
    fi
    rm -rf -- "$work"
    exit "$status"
}

trap finish EXIT
trap 'exit 1' HUP INT TERM
mkdir -p -- "$BASE/backups" "$work/new" "$work/old"
backup=$(mktemp -d "$BASE/backups/switch.XXXXXXXX")
for dir in "${dirs[@]}"; do
    [[ -d $profile/$dir ]] || continue
    cp -a -- "$profile/$dir" "$work/new/"
    if [[ -e $CONFIG/$dir || -L $CONFIG/$dir ]]; then
        cp -a -- "$CONFIG/$dir" "$backup/"
    fi
    changed+=("$dir")
done
cp -a -- "$STATE" "$backup/"
verify_lua "$work/new/hypr/hyprland.lua"

shell_stopped=true
stop_shell "$old_theme"
for dir in "${changed[@]}"; do
    if [[ -e $CONFIG/$dir || -L $CONFIG/$dir ]]; then
        saved+=("$dir")
        mv -T -- "$CONFIG/$dir" "$work/old/$dir"
    fi
    installed+=("$dir")
    mv -T -- "$work/new/$dir" "$CONFIG/$dir"
done
reload_config
starting_target=true
start_shell "$theme"
if [[ -n $cinematic_dir ]]; then wait_for_serpantinum; fi
state_tmp=$(mktemp "$BASE/.current-theme.XXXXXXXX")
printf '%s\n' "$theme" > "$state_tmp"
# Keep the state commit and its in-memory acknowledgement together.
trap '' HUP INT TERM
mv -fT -- "$state_tmp" "$STATE"
committed=true
trap 'exit 1' HUP INT TERM

printf 'Switched to %s. Previous configuration: %s\n' "$theme" "$backup"
