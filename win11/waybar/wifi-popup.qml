//@ pragma AppId win11-wifi-popup
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string monitorName: Quickshell.env("QS_WIFI_MONITOR")
    readonly property var targetScreen: Quickshell.screens.find(screen => screen.name === monitorName) ?? null
    readonly property real iconX: Number(Quickshell.env("QS_WIFI_X"))
    readonly property string fontFamily: Qt.fontFamilies().includes("Segoe UI") ? "Segoe UI" : "sans-serif"

    property var network: ({ available: false, enabled: false, networks: [], message: "Checking Wi-Fi…", busy: false })
    property string selectedId: ""
    readonly property var selected: network.networks.find(row => row.id === selectedId) ?? null
    property bool usePassword: false
    property bool closing: false

    function send(action) {
        if (backend.running && !closing)
            backend.write(JSON.stringify(action) + "\n");
    }

    function select(row) {
        password.clear();
        selectedId = row.id;
        usePassword = !row.connected && !row.saved && needsPassword(row);
        if (usePassword)
            Qt.callLater(() => password.forceActiveFocus());
    }

    function needsPassword(row) {
        return ["sae", "wpa-psk", "none"].includes(row.mode);
    }

    function connectSelected() {
        if (!selected || network.busy || (usePassword && !password.text))
            return;
        const action = { action: "connect", id: selected.id };
        if (usePassword)
            action.password = password.text;
        send(action);
        password.clear();
    }

    function dismiss() {
        if (closing)
            return;
        closing = true;
        password.clear();
        closeAnimation.start();
    }

    function signalIcon(strength) {
        const level = Math.max(1, Math.min(4, Math.ceil(strength / 25)));
        return Qt.resolvedUrl("status-icons/wifi-" + level + ".svg");
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
        target: "network"
        function close(): void { root.dismiss(); }
    }

    Process {
        id: backend
        command: ["python3", Quickshell.env("QS_WIFI_HELPER"), "panel"]
        running: !!root.targetScreen
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => {
                try {
                    root.network = JSON.parse(line);
                } catch (_) {
                    // Never echo backend input or diagnostic payloads.
                }
            }
        }
        onExited: {
            if (!root.closing && (root.network.available || !root.network.message))
                root.network = { available: false, enabled: false, networks: [], message: "Wi-Fi service unavailable.", busy: false };
        }
    }

    HyprlandFocusGrab {
        windows: [panel]
        active: panel.visible && !root.closing
        onCleared: root.dismiss()
    }

    component Action: Button {
        id: control
        font.family: root.fontFamily
        font.pixelSize: 13
        palette.buttonText: enabled ? "#f3f3f3" : "#a1a1a3"
        implicitHeight: 34
        padding: 9
        background: Rectangle {
            radius: 5
            color: control.down ? "#4b4b4d" : control.hovered ? "#3e3e40" : "#343436"
            border.color: control.visualFocus ? "#60cdff" : "#4a4a4c"
        }
    }

    PanelWindow {
        id: panel
        screen: root.targetScreen
        visible: !!root.targetScreen
        color: "transparent"
        anchors.left: true
        anchors.bottom: true
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: root.targetScreen ? Math.min(374, root.targetScreen.width - 16) : 374
        implicitHeight: root.targetScreen ? Math.min(455, root.targetScreen.height - 64) : 455
        margins.bottom: 56
        margins.left: root.targetScreen ? Math.max(8, Math.min(root.targetScreen.width - implicitWidth - 8,
            Math.round(root.iconX - implicitWidth / 2))) : 0

        WlrLayershell.namespace: "win11-wifi-popup"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        BackgroundEffect.blurRegion: Region { item: surface }

        Shortcut { sequence: "Escape"; onActivated: root.dismiss() }

        Rectangle {
            id: surface
            width: parent.width
            height: parent.height
            color: "#ee232325"
            border.color: "#555557"
            radius: 10
            opacity: 0
            y: 15
            clip: true
            enabled: !root.closing

            ParallelAnimation {
                id: openAnimation
                running: true
                NumberAnimation { target: surface; property: "opacity"; to: 1; duration: 155; easing.type: Easing.OutCubic }
                NumberAnimation { target: surface; property: "y"; to: 0; duration: 195; easing.type: Easing.OutCubic }
            }

            ParallelAnimation {
                id: closeAnimation
                onStarted: openAnimation.stop()
                NumberAnimation { target: surface; property: "opacity"; to: 0; duration: 125; easing.type: Easing.InCubic }
                NumberAnimation { target: surface; property: "y"; to: 15; duration: 155; easing.type: Easing.InCubic }
                onFinished: Qt.quit()
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 9

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: "Wi-Fi"
                        color: "#f4f4f4"
                        font.family: root.fontFamily
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                    }
                    Switch {
                        id: wifiSwitch
                        checked: root.network.enabled
                        enabled: root.network.available && !root.network.busy
                        Accessible.name: "Wi-Fi"
                        onClicked: {
                            password.clear();
                            root.selectedId = "";
                            root.send({action: "radio", enabled: checked});
                        }
                        indicator: Rectangle {
                            implicitWidth: 40
                            implicitHeight: 21
                            x: wifiSwitch.leftPadding
                            y: (wifiSwitch.height - height) / 2
                            radius: 11
                            color: wifiSwitch.checked ? "#60cdff" : "#414143"
                            border.color: wifiSwitch.visualFocus ? "white" : "#77777b"
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: wifiSwitch.checked ? parent.width - width - 4 : 4
                                width: 13
                                height: 13
                                radius: 7
                                color: wifiSwitch.checked ? "#153746" : "#e1e1e3"
                                Behavior on x { NumberAnimation { duration: 130 } }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#47474a" }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.network.networks
                    spacing: 2
                    activeFocusOnTab: true
                    keyNavigationEnabled: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    Keys.onReturnPressed: { if (currentItem) root.select(currentItem.modelData); }
                    Keys.onEnterPressed: { if (currentItem) root.select(currentItem.modelData); }

                    delegate: ItemDelegate {
                        id: row
                        required property var modelData
                        required property int index
                        width: list.width
                        height: 48
                        padding: 8
                        enabled: !root.network.busy
                        Accessible.name: modelData.name + ", " + modelData.security + ", " + modelData.strength + "%"
                        onClicked: {
                            list.currentIndex = index;
                            root.select(modelData);
                        }
                        background: Rectangle {
                            radius: 6
                            color: row.modelData.connected ? "#343e46"
                                : row.modelData.id === root.selectedId || row.hovered || (list.activeFocus && row.ListView.isCurrentItem)
                                    ? "#3a3a3c" : "transparent"
                            Rectangle {
                                visible: row.modelData.connected
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 2
                                height: 19
                                radius: 1
                                color: "#60cdff"
                            }
                        }
                        contentItem: RowLayout {
                            spacing: 9
                            Image {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 20
                                source: root.signalIcon(row.modelData.strength)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: "#f4f4f4"
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: (row.modelData.connected ? "Connected · " : "") + row.modelData.security
                                    elide: Text.ElideRight
                                    color: "#c8c8ca"
                                    font.pixelSize: 11
                                }
                            }
                            Label { text: row.modelData.strength + "%"; color: "#dedee0"; font.pixelSize: 11 }
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: !root.network.available ? "Wi-Fi adapter unavailable"
                            : root.network.enabled ? "No networks found" : "Wi-Fi is off"
                        color: "#c5c5c7"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.selected !== null
                    spacing: 7
                    TextField {
                        id: password
                        Layout.fillWidth: true
                        visible: root.usePassword && !!root.selected && !root.selected.connected
                        enabled: !root.network.busy
                        placeholderText: "Wi-Fi password"
                        color: "#f4f4f4"
                        placeholderTextColor: "#bdbdbf"
                        font.family: root.fontFamily
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                        onAccepted: root.connectSelected()
                        background: Rectangle {
                            radius: 5
                            color: "#1a1a1c"
                            border.color: password.activeFocus ? "#60cdff" : "#555557"
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        Action {
                            text: "Use password"
                            visible: !!root.selected && root.selected.saved && !root.selected.connected
                                && root.needsPassword(root.selected) && !root.usePassword
                            enabled: !root.network.busy
                            onClicked: {
                                root.usePassword = true;
                                password.forceActiveFocus();
                            }
                        }
                        Action {
                            text: root.selected?.connected ? "Disconnect" : "Connect"
                            enabled: !root.network.busy && !!root.selected
                                && (root.selected.connected || root.selected.saved || root.selected.mode !== "saved-only")
                                && (!password.visible || password.text.length > 0)
                            onClicked: {
                                if (root.selected.connected)
                                    root.send({action: "disconnect"});
                                else
                                    root.connectSelected();
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: root.network.message
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: "#c5c5c7"
                        font.pixelSize: 11
                    }
                    Action {
                        text: "Scan"
                        enabled: root.network.available && root.network.enabled && !root.network.busy
                        onClicked: root.send({action: "scan"})
                    }
                }
            }
        }
    }
}
