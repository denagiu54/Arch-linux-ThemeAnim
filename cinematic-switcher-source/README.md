# Hyprland Cinematic Desktop Switcher

Switch between three Hyprland desktops with live, per-monitor animations. The renderers use Python, NumPy and Qt through PySide6. Hyprland stays running during a theme switch, so applications and workspaces stay in the session.

| Shortcut | Theme | Desktop |
| --- | --- | --- |
| **Super+F1** | **Serpantinum** | Official Quickshell shell, wallpaper picker, dock and notifications |
| **Super+F2** | **LeyzS-inspired** | Translucent Waybar, Hyprpaper, Wofi and SwayNC with a monochrome landscape |
| **Super+F3** | **Windows 11-inspired** | Dark Waybar with centered launchers and Quickshell Start, music and Wi-Fi popups |

The switcher serializes requests, ignores requests for the active theme, verifies Lua before applying a profile and rolls back failed switches. Serpantinum’s transition uses a native Wayland overlay and checks the official shell’s per-output wallpaper IPC and mapped layers before the reveal. The last successful theme starts again with the next Hyprland session.

## Screenshots

| Theme | Preview |
| --- | --- |
| Windows 11-inspired | Screenshot pending |
| Serpantinum | Screenshot pending |
| LeyzS-inspired | Screenshot pending |

## Requirements

- Arch Linux and an existing, working Hyprland Wayland session. This export was checked with Hyprland **0.57.2**, Hyprpaper **0.8.5** and Quickshell **0.3.2**. Older Hyprland versions using legacy configuration syntax are outside the tested setup.
- Bash, Python, PySide6, NumPy, Qt Wayland and LayerShellQt. The installer builds the small C++ bridge locally.
- The official Serpantinum package and a Quickshell build with Hyprland and Wayland support. The music popup imports the installed Serpantinum music component, so upstream changes to that component can affect the popup.
- NetworkManager and its Python GI bindings for Wi-Fi actions. The popup uses NetworkManager’s session permissions. A working PipeWire/PulseAudio-compatible session is needed for the volume module and audio playback.
- Default per-user paths under `~/.config`, `~/.local/share`, `~/.local/state` and `~/.cache`.

The export includes portable profiles and generated fallback wallpapers. The Windows startup recording and branded assets are optional local inputs. The archive is designed for a fresh user install and refuses an existing switcher runtime.

## Install on Arch Linux

### 1. Install dependencies

Run as your normal user. Review the package transaction before confirming.

```bash
sudo pacman -Syu --needed base-devel git unzip hyprland xdg-desktop-portal-hyprland \
  bash python pyside6 python-numpy python-gobject libnm networkmanager \
  qt6-base qt6-declarative qt6-wayland qt6-svg layer-shell-qt pkgconf \
  quickshell waybar hyprpaper swaync wofi kitty grim mpv ffmpeg jq
```

Optional launcher apps can be installed separately. The Steam and Chat buttons are configured for Flatpak applications and can be removed from Waybar if you do not use them.

```bash
sudo pacman -S --needed nautilus epiphany gnome-text-editor flatpak adwaita-icon-theme
```

For the Wi-Fi popup, check the network service with `nmcli general status` and `systemctl is-active NetworkManager`. If you already use a different network manager, plan the migration before changing services. The project installer leaves networking and login services alone.

### 2. Install official Serpantinum

If `serpantinumd` already exists and the official QML file is installed, skip the build. Otherwise use the upstream Arch package recipe as a normal user. Inspect the `PKGBUILD` before building. The commands below follow the official [Serpantinum Arch installation guide](https://serpantinum.dev/installation).

```bash
mkdir -p "$HOME/src"
cd "$HOME/src"
git clone --depth 1 https://github.com/ilyamiro/serpantinum.git
cd serpantinum/packaging/aur/serpantinum
less PKGBUILD
makepkg -si
command -v serpantinumd
test -r /usr/share/serpantinum/src/quickshell/Shell.qml
```

The originating system used a 2.5.3-based Serpantinum build. The current upstream recipe may install a later version. Keep the official package layout expected by the switcher and check the upstream release notes before upgrading.

### 3. Extract and inspect the export

With the ZIP in Downloads, run:

```bash
mkdir -p "$HOME/src"
unzip "$HOME/Downloads/cinematic-switcher-source.zip" -d "$HOME/src"
cd "$HOME/src/cinematic-switcher-source"
```

If you want to use your own approved assets at first install, provide actual PNG files as `assets/win11.png` and `assets/leyzs.png`. You can also provide `assets/audio/startup.wav` for the Windows sound cue. The installer generates fallback wallpapers when the optional PNGs are absent.

### 4. Verify and install from inside Hyprland

Connect the monitors you want to use. Inspect the current layout and confirm the active config uses Lua. Review the profile templates before installing. The installer snapshots and replaces `~/.config/hypr` and `~/.config/waybar`; merge existing custom settings into the templates first if you need them.

```bash
hyprctl monitors
hyprctl configerrors
bash install.sh --check
bash install.sh
```

For a specific animation output, use its actual connector name. In this example it is `eDP-1`.

```bash
CINEMATIC_MAIN_OUTPUT=eDP-1 bash install.sh
```

Use that command **instead of** the plain install command. By default, the installer prefers an active laptop output, then the first active output. The generated profiles use the positions, scales, refresh rates and transforms reported by the current session. Other screens receive a fallback monitor rule.

Save your work and log out of Hyprland, then log back in. You can end the current Hyprland session with `hyprctl dispatch 'hl.dsp.exit()'`. **LeyzS** is the initial theme. This loads its login hook and starts Waybar, Hyprpaper and SwayNC.

### 5. Complete Serpantinum setup

On a first-time Serpantinum install, enter its profile directly and finish the official welcome flow before using its cinematic shortcut.

```bash
switcher="$HOME/.local/share/desktop-switcher"
"$switcher/switch.sh" serpantinum
```

In Serpantinum, use **Super+W** to select wallpaper for every connected monitor. For example, you can assign the included generated landscape to all outputs.

```bash
serpantinum ipc call wallpaper setWallpaper all \
  "$HOME/.local/share/desktop-switcher/assets/leyzs.png" fade
```

Replace `eDP-1` below with a connector from `hyprctl monitors` and repeat for each screen. Check that each command returns the intended file.

```bash
serpantinum ipc call wallpaper getWallpaperPath eDP-1
```

## Switching and customization

Use **Super+F1**, **Super+F2** or **Super+F3**. You can also call the same entry point from a Hyprland terminal.

```bash
switcher="$HOME/.local/share/desktop-switcher"
"$switcher/switch.sh" --animate win11
"$switcher/switch.sh" leyzs       # direct switch
"$switcher/switch.sh" --preview serpantinum
```

Edit the installed profiles under `~/.local/share/desktop-switcher/profiles/` to keep changes across switches. Edit each profile’s `hypr/monitors.lua` for output layout or `hypr/hyprland.lua` for shortcuts and keyboard layout. The default keyboard layout is US. The active profile is copied into `~/.config/hypr` and, where provided, `~/.config/waybar` on the next switch.

- **Windows and LeyzS wallpaper:** replace `~/.local/share/desktop-switcher/assets/win11.png` or `leyzs.png` with a PNG, then switch away and back. Hyprpaper and the corresponding animation use those same paths.
- **Serpantinum wallpaper:** use the official picker or its IPC command. For video wallpapers, the cinematic uses a decoded frame from the selected video and the live shell plays the video independently.
- **Waybar and popups:** edit the installed `profiles/win11/waybar/config` and `style.css`. The QML files and their Python helpers live beside them. Adjust `APP_COMMANDS` in `app-indicator.py` if you use different app packages.
- **Animation and audio:** use the three renderer sources under `runtime/` as the editable originals. The installed copies are next to `switch.sh`. Copy a changed renderer into that directory while the switcher is idle. Keep the audio filenames `leyzs.wav`, `serpantinum.wav` and optional `startup.wav`. The Windows cue is skipped if its recording is absent.
- **Main animation output:** update `~/.local/share/desktop-switcher/main-output` to an active connector. Keep the same monitor layout in all profiles for a consistent live switch.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Installation says a runtime already exists | Use a fresh user account, or use the original installation’s rollback procedure. This installer cannot migrate it. |
| The shortcut appears to do nothing | Check `cat ~/.local/share/desktop-switcher/current-theme`. Current-theme requests and requests during an existing switch are ignored. In other cases, try the direct command in a terminal to see validation errors. |
| Lua/profile switch fails | Run `hyprctl configerrors` and `Hyprland --verify-config -c ~/.local/share/desktop-switcher/profiles/leyzs/hypr/hyprland.lua`. Change the theme in the path as needed. Inspect `switch.log`, `leyzs-switch.log` or `serpantinum-switch.log` in the runtime directory. |
| Serpantinum rolls back or cannot find wallpaper | Complete the direct-switch first-run setup, confirm the official QML path, and verify the selected path on every active output. Check `serpantinum.log` and `serpantinum-switch.log`. |
| Initial bar or wallpaper is missing | Re-enter Hyprland after installation, inspect `login.log`, `waybar.log` and `hyprpaper.log`, and check for a conflicting shell or wallpaper process. The profile expects Hyprpaper’s 0.8-style wallpaper blocks. |
| Wi-Fi popup shows no devices | Check `nmcli device status` and NetworkManager’s permissions. Enterprise networks must already have a saved connection profile. |
| Music popup fails | Confirm the installed Serpantinum QML media component is available and version-compatible. Inspect the error from `quickshell -p ~/.config/waybar/serpantinum-music.qml` after closing the current popup. |
| No Windows cue plays | Supply your own permitted `startup.wav` to the runtime directory and check MPV/audio output. |

## Rollback and uninstall

A failed switch restores the previous profile automatically. It prints the backup directory if recovery needs attention. Per-switch backups live under `~/.local/share/desktop-switcher/backups/`.

To remove this source installation, log out of Hyprland and run from a TTY or another desktop session as the same user:

```bash
cd "$HOME/src/cinematic-switcher-source"
bash install.sh --restore
```

The command restores the pre-install Hyprland and Waybar directories and moves the switcher runtime and outgoing config into a uniquely named backup directory printed by the script. Start Hyprland again to use the restored configuration. Packages, Serpantinum’s separate settings and other user data stay installed.

## Project structure

| Path | Purpose |
| --- | --- |
| `install.sh` | Profile check, fresh install and pre-install config restore |
| `runtime/` | Python renderers, launch guard, switch transaction and LayerShellQt bridge |
| `win11/`, `leyzs/`, `serpantinum/` | Hyprland Lua profiles and theme-specific desktop configuration |
| `win11/waybar/` | Waybar configuration, Start menu, music and Wi-Fi popup sources |
| `assets/audio/` | LeyzS and Serpantinum project audio plus an optional local Windows cue |
| `tools/` | Profile and fallback wallpaper generator with example monitor input |
| `REPORT.txt` | Export contents, rights review and validation notes |

## Credits and third-party licenses

- [LeyzS Arch + Hyprland Dotfiles](https://github.com/L3yzs/By-LeyzS-Arch-Hyprland-Dotfiles) and [Windows-inspired Hyprland theme](https://github.com/L3yzs/win11themehyprland) by L3yzs informed the designs. The exported profiles use replacement templates and styling.
- [Serpantinum](https://github.com/ilyamiro/serpantinum) is AGPL-3.0 and runs from its separately installed package. The music popup interoperates with its installed QML component.
- [Quickshell](https://git.outfoxxed.me/quickshell/quickshell), [KDE LayerShellQt](https://invent.kde.org/plasma/layer-shell-qt), [Hyprland](https://github.com/hyprwm/Hyprland), [Waybar](https://github.com/Alexays/Waybar) and [Qt for Python](https://doc.qt.io/qtforpython-6/) are separately installed dependencies. Their respective upstream license terms apply.
- The Windows name describes the visual inspiration. Microsoft and other app branding remain with their owners. Review [REPORT.txt](REPORT.txt) before public publication or reuse. A project-wide license has not been assigned.

## Contributing

Open an issue with the theme, package versions, output count and reproduction steps. Attach sanitized logs and screenshots with private information removed. Keep animation or theme changes separate from installer changes when possible.

Before submitting, run the configuration and bridge preflight:

```bash
bash install.sh --check tools/example-monitors.json
```

For session changes, test all three shortcuts, both output layouts you support and one rollback. Include any new dependency or manual setup step in this README. Submit only assets you have permission to redistribute.
