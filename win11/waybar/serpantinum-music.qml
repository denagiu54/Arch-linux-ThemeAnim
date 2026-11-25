//@ pragma AppId win11-serpantinum-music
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "file:///usr/share/serpantinum/src/quickshell/media" as Serpantinum

ShellRoot {
    id: root

    readonly property string monitorName: Quickshell.env("QS_MUSIC_MONITOR") || ""
    readonly property var targetScreen: Quickshell.screens.find(screen => screen.name === monitorName) ?? null
    property bool closing: false

    function dismiss() {
        if (closing)
            return;
        closing = true;
        music.startExit(() => Qt.quit());
        closeTimeout.start();
    }

    onTargetScreenChanged: {
        if (!targetScreen)
            Qt.callLater(Qt.quit);
    }

    Component.onCompleted: {
        if (!targetScreen)
            Qt.callLater(Qt.quit);
    }

    IpcHandler {
        target: "music"
        function close(): void { root.dismiss(); }
    }

    Timer {
        id: closeTimeout
        interval: 700
        onTriggered: Qt.quit()
    }

    PanelWindow {
        id: panel
        screen: root.targetScreen
        visible: root.targetScreen !== null
        color: "transparent"
        anchors.left: true
        anchors.bottom: true
        exclusionMode: ExclusionMode.Ignore

        implicitWidth: root.targetScreen ? Math.min(625, root.targetScreen.width - 16) : 625
        implicitHeight: root.targetScreen ? Math.min(565, root.targetScreen.height - 64) : 565
        margins.bottom: 56
        // Spotify is one 44 px button to the right of the centered pin row's midpoint.
        margins.left: root.targetScreen
            ? Math.max(8, Math.min(root.targetScreen.width - implicitWidth - 8,
                                  Math.round((root.targetScreen.width - implicitWidth) / 2 + 44)))
            : 0

        WlrLayershell.namespace: "win11-serpantinum-music-" + root.monitorName
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Shortcut {
            sequence: "Escape"
            enabled: !root.closing && !music.lyricsPickerPopup.visible
            onActivated: root.dismiss()
        }

        Serpantinum.MusicPopup {
            id: music
            anchors.fill: parent
            visible: panel.visible
            enabled: !root.closing
        }
    }

    HyprlandFocusGrab {
        windows: [panel, music.lyricsPickerPopup]
        active: panel.visible && !root.closing
        onCleared: root.dismiss()
    }
}
