//@ pragma AppId win11-start-menu
import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string monitorName: Quickshell.env("QS_START_MONITOR")
    readonly property var targetScreen: Quickshell.screens.find(screen => screen.name === monitorName) ?? null
    readonly property string userName: Quickshell.env("QS_START_USER") || "User"
    readonly property string avatarUrl: Quickshell.env("QS_START_AVATAR") || ""
    readonly property var recent: JSON.parse(Quickshell.env("QS_START_RECENT") || "[]")
    readonly property var pinnedIcons: JSON.parse(Quickshell.env("QS_START_PIN_ICONS") || "{}")
    readonly property string fontFamily: Qt.fontFamilies().includes("Segoe UI") ? "Segoe UI" : "sans-serif"
    readonly property string musicId: "serpantinum-music"
    readonly property int pinColumns: 6
    readonly property int pinRows: 3
    readonly property int pageSize: pinColumns * pinRows
    readonly property var defaultPins: [
        "org.gnome.Nautilus", "org.gnome.Epiphany", "org.gnome.TextEditor",
        "com.valvesoftware.Steam", "dev.vencord.Vesktop", "org.gnome.Console",
        "org.gnome.Software", "org.gnome.Settings", "org.gnome.Calculator", musicId
    ]
    readonly property var apps: {
        const entries = DesktopEntries.applications.values.filter(entry => !entry.noDisplay && entry.name);
        const model = entries.map(entry => ({
            key: entry.id.replace(/\.desktop$/, ""), name: entry.name, icon: entry.icon,
            keywords: [entry.id, entry.genericName, ...(entry.keywords || [])].join(" "), entry: entry
        }));
        model.push({key: musicId, name: "Music", icon: Quickshell.env("QS_START_MUSIC_ICON") || "multimedia-player", keywords: "Serpantinum Music player media", entry: null});
        return model.sort((a, b) => a.name.localeCompare(b.name));
    }
    readonly property var pinnedApps: preferences.pins.map(key => apps.find(app => app.key === key)).filter(app => app)
    readonly property int pageCount: Math.max(1, Math.ceil(pinnedApps.length / pageSize))
    readonly property var shownApps: {
        const query = search.text.trim().toLowerCase();
        if (query)
            return apps.filter(app => query.split(/\s+/).every(word => (app.name + " " + app.keywords).toLowerCase().includes(word)));
        if (allApps)
            return apps;
        return pinnedApps.slice(pinPage * pageSize, (pinPage + 1) * pageSize);
    }

    property int pinPage: 0
    property bool allApps: false
    property bool powerOpen: false
    property string confirmation: ""
    property bool closing: false
    property var pendingAction: null

    onPageCountChanged: pinPage = Math.min(pinPage, pageCount - 1)

    function showPinPage(page, index) {
        if (page < 0 || page >= pageCount || page === pinPage)
            return;
        pinPage = page;
        applications.currentIndex = Math.min(index, shownApps.length - 1);
        applications.forceActiveFocus();
    }

    function relativeTime(modified) {
        if (typeof modified !== "number")
            return "";
        const seconds = Math.max(0, Math.floor(Date.now() / 1000 - modified));
        if (seconds < 60)
            return "Just now";
        const units = [[86400, "day"], [3600, "hour"], [60, "minute"]];
        for (const [scale, label] of units) {
            const count = Math.floor(seconds / scale);
            if (count)
                return count + " " + label + (count === 1 ? "" : "s") + " ago";
        }
        return "";
    }

    function dismiss(action) {
        if (closing)
            return;
        closing = true;
        pendingAction = action || null;
        exitAnimation.start();
    }

    function launch(app) {
        if (!app)
            return;
        if (app.key === musicId) {
            dismiss(() => Quickshell.execDetached(["env", "WAYBAR_OUTPUT_NAME=" + monitorName,
                "python3", Quickshell.env("QS_START_HELPER"), "spotify", "--activate"]));
        } else {
            dismiss(() => app.entry.execute());
        }
    }

    function togglePin(app) {
        if (!app)
            return;
        const pins = preferences.pins;
        preferences.pins = pins.includes(app.key) ? pins.filter(key => key !== app.key) : [...pins, app.key];
        preferences.sync();
    }

    function power(action) {
        if (action === "Restart" || action === "Shut down") {
            confirmation = action;
            cancelButton.forceActiveFocus();
        } else {
            const command = action === "Lock" ? ["hyprlock"] : ["systemctl", "suspend"];
            dismiss(() => Quickshell.execDetached(command));
        }
    }

    function confirmPower() {
        if (confirmation !== "Restart" && confirmation !== "Shut down")
            return;
        const command = confirmation === "Restart" ? "reboot" : "poweroff";
        dismiss(() => Quickshell.execDetached(["systemctl", command]));
    }

    function iconPath(icon) {
        if (icon.startsWith("/") || icon.startsWith("file:"))
            return icon;
        return Quickshell.iconPath(icon || "application-x-executable", "application-x-executable");
    }

    onTargetScreenChanged: {
        if (!targetScreen)
            Qt.callLater(Qt.quit);
    }

    Component.onCompleted: {
        if (!targetScreen)
            Qt.callLater(Qt.quit);
        else
            search.forceActiveFocus();
    }

    Settings {
        id: preferences
        location: "file://" + Quickshell.env("QS_START_SETTINGS")
        property var pins: root.defaultPins
    }

    IpcHandler {
        target: "start"
        function close(): void { root.dismiss(); }
    }

    HyprlandFocusGrab {
        windows: [panel]
        active: panel.visible && !root.closing
        onCleared: root.dismiss()
    }

    component Action: Button {
        id: button
        focusPolicy: Qt.StrongFocus
        font.family: root.fontFamily
        implicitHeight: 36
        leftPadding: 12
        rightPadding: 12
        palette.buttonText: "#f2f3f5"
        palette.highlight: "#60cdff"
        background: Rectangle {
            radius: 7
            color: button.down ? "#414751" : button.hovered || button.visualFocus ? "#353b45" : "#2b3039"
            border.color: button.visualFocus ? "#60cdff" : "#424953"
        }
    }

    component LineIcon: Canvas {
        property bool powerIcon: false
        width: 20
        height: 20
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = "#f0f0f0";
            ctx.lineWidth = 1.5;
            ctx.lineCap = "round";
            ctx.beginPath();
            if (powerIcon) {
                ctx.arc(10, 11, 6, -Math.PI / 4, Math.PI * 5 / 4);
                ctx.moveTo(10, 3);
                ctx.lineTo(10, 10);
            } else {
                ctx.arc(8.5, 8.5, 5, 0, Math.PI * 2);
                ctx.moveTo(12, 12);
                ctx.lineTo(16, 16);
            }
            ctx.stroke();
        }
    }

    PanelWindow {
        id: panel

        screen: root.targetScreen
        visible: root.targetScreen !== null
        color: "transparent"
        anchors.left: true
        anchors.bottom: true
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: root.targetScreen ? Math.min(640, root.targetScreen.width - 16) : 640
        implicitHeight: root.targetScreen ? Math.min(720, root.targetScreen.height - 64) : 720
        margins.bottom: 56
        // Start is three 44 px buttons to the left of the centered pin row's midpoint.
        margins.left: root.targetScreen
            ? Math.max(8, Math.min(root.targetScreen.width - implicitWidth - 8,
                Math.round((root.targetScreen.width - implicitWidth) / 2 - 132)))
            : 0
        WlrLayershell.namespace: "win11-start-menu-" + root.monitorName
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        BackgroundEffect.blurRegion: Region { item: surface }

        Shortcut {
            sequence: "Escape"
            onActivated: root.dismiss()
        }
        Shortcut {
            sequence: "Ctrl+P"
            enabled: !root.powerOpen
            onActivated: root.togglePin(root.shownApps[applications.currentIndex])
        }

        Rectangle {
            id: surface
            width: parent.width
            height: parent.height
            color: "#eb232325"
            radius: 10
            border.color: "#525254"
            opacity: 0
            y: 18
            clip: true
            enabled: !root.closing

            ParallelAnimation {
                id: entrance
                running: true
                NumberAnimation { target: surface; property: "opacity"; to: 1; duration: 165; easing.type: Easing.OutCubic }
                NumberAnimation { target: surface; property: "y"; to: 0; duration: 205; easing.type: Easing.OutCubic }
            }

            ParallelAnimation {
                id: exitAnimation
                onStarted: entrance.stop()
                NumberAnimation { target: surface; property: "opacity"; to: 0; duration: 130; easing.type: Easing.InCubic }
                NumberAnimation { target: surface; property: "y"; to: 16; duration: 160; easing.type: Easing.InCubic }
                onFinished: {
                    try {
                        if (root.pendingAction)
                            root.pendingAction();
                    } finally {
                        Qt.quit();
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 23
                anchors.leftMargin: 27
                anchors.rightMargin: 27
                anchors.bottomMargin: 12
                spacing: 12
                enabled: !root.powerOpen

                TextField {
                    id: search
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    placeholderText: "Search apps"
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    color: "#f4f6f7"
                    placeholderTextColor: "#aeb8c4"
                    selectByMouse: true
                    leftPadding: 40
                    selectionColor: "#60cdff"
                    selectedTextColor: "#121212"
                    background: Rectangle {
                        radius: 7
                        color: "#1c1c1e"
                        border.color: search.activeFocus ? "#68686a" : "#505052"
                        LineIcon {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 10
                            height: 2
                            radius: 1
                            color: "#60cdff"
                            visible: search.activeFocus
                        }
                    }
                    onTextChanged: applications.currentIndex = 0
                    onAccepted: root.launch(root.shownApps[applications.currentIndex] || root.shownApps[0])
                    Keys.onDownPressed: {
                        if (applications.count)
                            applications.forceActiveFocus();
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: search.text.trim() ? "Search results" : root.allApps ? "All apps" : "Pinned"
                        color: "#f4f6f7"
                        font.family: root.fontFamily
                        font.pixelSize: 18
                        font.bold: true
                    }
                    Action {
                        implicitHeight: 30
                        font.pixelSize: 12
                        text: root.allApps ? "‹  Back" : "All apps  ›"
                        background: Rectangle {
                            radius: 5
                            color: parent.down ? "#444446" : parent.hovered ? "#3c3c3e" : "#303032"
                            border.color: parent.visualFocus ? "#60cdff" : "#454547"
                        }
                        onClicked: {
                            root.allApps = !root.allApps;
                            search.clear();
                            applications.currentIndex = 0;
                            applications.forceActiveFocus();
                        }
                    }
                }

                GridView {
                    id: applications
                    readonly property bool grid: !root.allApps && !search.text.trim()
                    Layout.fillWidth: true
                    Layout.fillHeight: !grid
                    Layout.preferredHeight: grid ? root.pinRows * cellHeight : 400
                    Layout.minimumHeight: 0
                    clip: true
                    cellWidth: grid ? Math.floor(width / root.pinColumns) : width
                    cellHeight: grid ? Math.min(78, Math.max(64, Math.floor(panel.height / 9))) : 46
                    model: root.shownApps
                    keyNavigationEnabled: true
                    activeFocusOnTab: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: !grid
                    ScrollBar.vertical: ScrollBar { policy: applications.grid ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded }
                    Keys.onReturnPressed: root.launch(root.shownApps[currentIndex])
                    Keys.onEnterPressed: root.launch(root.shownApps[currentIndex])
                    Keys.onUpPressed: event => {
                        if (grid && currentIndex < root.pinColumns && root.pinPage > 0) {
                            root.showPinPage(root.pinPage - 1, root.pageSize - root.pinColumns + currentIndex);
                            event.accepted = true;
                        } else if (currentIndex < (grid ? root.pinColumns : 1)) {
                            search.forceActiveFocus();
                            event.accepted = true;
                        } else {
                            moveCurrentIndexUp();
                            event.accepted = true;
                        }
                    }
                    Keys.onPressed: event => {
                        if (!grid)
                            return;
                        const countOnPage = count;
                        const finalRow = currentIndex + root.pinColumns >= countOnPage;
                        if (event.key === Qt.Key_PageDown || (event.key === Qt.Key_Down && finalRow)
                                || (event.key === Qt.Key_Right && currentIndex === countOnPage - 1)) {
                            root.showPinPage(root.pinPage + 1, event.key === Qt.Key_Down ? currentIndex % root.pinColumns : 0);
                            event.accepted = root.pageCount > 1;
                        } else if (event.key === Qt.Key_PageUp || (event.key === Qt.Key_Left && currentIndex === 0 && root.pinPage > 0)) {
                            root.showPinPage(root.pinPage - 1, event.key === Qt.Key_Left ? root.pageSize - 1 : 0);
                            event.accepted = root.pageCount > 1;
                        }
                    }

                    delegate: Item {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool pinned: preferences.pins.includes(modelData.key)
                        width: applications.cellWidth
                        height: applications.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: 6
                            color: clickArea.containsMouse || pinButton.hovered || (applications.activeFocus && applications.currentIndex === tile.index)
                                ? "#38383a" : "transparent"
                            Behavior on color { ColorAnimation { duration: 110 } }
                        }

                        Image {
                            id: appIcon
                            source: root.iconPath(applications.grid ? root.pinnedIcons[tile.modelData.key] || tile.modelData.icon : tile.modelData.icon)
                            width: applications.grid ? 36 : 25
                            height: width
                            sourceSize.width: width
                            sourceSize.height: height
                            anchors.left: parent.left
                            anchors.leftMargin: applications.grid ? (parent.width - width) / 2 : 12
                            anchors.top: parent.top
                            anchors.topMargin: applications.grid ? 8 : (parent.height - height) / 2
                        }

                        Label {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: applications.grid ? 6 : 48
                            anchors.rightMargin: applications.grid ? 6 : 45
                            anchors.top: parent.top
                            anchors.topMargin: applications.grid ? 47 : 0
                            anchors.bottom: parent.bottom
                            color: "#f2f3f5"
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            text: tile.modelData.name
                            textFormat: Text.PlainText
                            horizontalAlignment: applications.grid ? Text.AlignHCenter : Text.AlignLeft
                            verticalAlignment: applications.grid ? Text.AlignTop : Text.AlignVCenter
                            elide: Text.ElideRight
                            wrapMode: applications.grid ? Text.Wrap : Text.NoWrap
                            maximumLineCount: applications.grid ? 2 : 1
                        }

                        MouseArea {
                            id: clickArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                applications.currentIndex = tile.index;
                                if (mouse.button === Qt.RightButton)
                                    root.togglePin(tile.modelData);
                                else
                                    root.launch(tile.modelData);
                            }
                        }

                        Action {
                            id: pinButton
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 4
                            width: 30
                            height: 30
                            leftPadding: 0
                            rightPadding: 0
                            visible: clickArea.containsMouse || hovered
                                || (applications.activeFocus && applications.currentIndex === tile.index)
                            text: tile.pinned ? "−" : "+"
                            Accessible.name: tile.pinned ? "Unpin " + tile.modelData.name : "Pin " + tile.modelData.name
                            ToolTip.visible: hovered
                            ToolTip.delay: 500
                            ToolTip.text: tile.pinned ? "Unpin from Start" : "Pin to Start"
                            onClicked: root.togglePin(tile.modelData)
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    visible: applications.grid && root.pageCount > 1
                    spacing: 6
                    Repeater {
                        model: root.pageCount
                        Button {
                            id: pageButton
                            required property int index
                            implicitWidth: 22
                            implicitHeight: 18
                            Accessible.name: "Pinned page " + (index + 1)
                            onClicked: root.showPinPage(index, 0)
                            background: Rectangle {
                                radius: 4
                                color: pageButton.hovered || pageButton.visualFocus ? "#414143" : "transparent"
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: pageButton.index === root.pinPage ? 12 : 5
                                    height: 5
                                    radius: 3
                                    color: pageButton.index === root.pinPage ? "#60cdff" : "#9b9b9d"
                                }
                            }
                        }
                    }
                }

                Label {
                    visible: applications.count === 0
                    text: search.text.trim() ? "No matching apps" : "Use All apps to add pins."
                    color: "#b8c1cc"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: applications.grid
                    spacing: 6
                    Label {
                        text: "Recommended"
                        color: "#f4f6f7"
                        font.family: root.fontFamily
                        font.pixelSize: 17
                        font.bold: true
                    }
                    Label {
                        visible: root.recent.length === 0
                        text: "No recent files available"
                        color: "#aeb8c4"
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 5
                        Repeater {
                            model: root.recent
                            Action {
                                id: recentButton
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.preferredHeight: 48
                                text: modelData.name
                                background: Rectangle {
                                    radius: 6
                                    color: recentButton.hovered || recentButton.visualFocus ? "#38383a" : "transparent"
                                    border.color: recentButton.visualFocus ? "#60cdff" : "transparent"
                                }
                                contentItem: RowLayout {
                                    spacing: 10
                                    Image {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        sourceSize.width: 28
                                        sourceSize.height: 28
                                        source: Quickshell.hasThemeIcon(recentButton.modelData.icon || "text-x-generic")
                                            ? Quickshell.iconPath(recentButton.modelData.icon || "text-x-generic")
                                            : "file:///usr/share/icons/Adwaita/scalable/mimetypes/text-x-generic.svg"
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label {
                                            Layout.fillWidth: true
                                            text: recentButton.modelData.name
                                            textFormat: Text.PlainText
                                            elide: Text.ElideMiddle
                                            color: "#f2f2f2"
                                            font.family: root.fontFamily
                                            font.pixelSize: 13
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: root.relativeTime(recentButton.modelData.modified)
                                            visible: text.length > 0
                                            elide: Text.ElideRight
                                            color: "#bababc"
                                            font.family: root.fontFamily
                                            font.pixelSize: 12
                                        }
                                    }
                                }
                                ToolTip.visible: hovered
                                ToolTip.text: modelData.folder || ""
                                onClicked: root.dismiss(() => Quickshell.execDetached(["xdg-open", modelData.path]))
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true; visible: applications.grid }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 62
                    Layout.leftMargin: -16
                    Layout.rightMargin: -16
                    radius: 7
                    color: "#d21a1a1c"
                    border.color: "#3b3b3d"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 15
                        spacing: 11
                        Rectangle {
                            Layout.preferredWidth: 35
                            Layout.preferredHeight: 35
                            radius: 18
                            color: "#424246"
                            Label {
                                anchors.centerIn: parent
                                visible: avatar.status !== Image.Ready
                                text: root.userName.slice(0, 1).toUpperCase()
                                color: "#f0f0f2"
                            }
                            Image { id: avatar; anchors.fill: parent; source: root.avatarUrl; fillMode: Image.PreserveAspectCrop }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: root.userName
                            color: "#f2f2f2"
                            font.family: root.fontFamily
                            font.pixelSize: 13
                        }
                        Button {
                            id: powerButton
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            padding: 0
                            Accessible.name: "Power"
                            ToolTip.visible: hovered
                            ToolTip.delay: 500
                            ToolTip.text: "Power"
                            background: Rectangle {
                                radius: 6
                                color: powerButton.down ? "#48484a" : powerButton.hovered || powerButton.visualFocus ? "#38383a" : "transparent"
                                border.color: powerButton.visualFocus ? "#60cdff" : "transparent"
                            }
                            LineIcon { anchors.centerIn: parent; powerIcon: true }
                            onClicked: {
                                root.powerOpen = true;
                                lockButton.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                visible: root.powerOpen
                color: "#900d1014"
                MouseArea { anchors.fill: parent; onClicked: { root.powerOpen = false; root.confirmation = ""; search.forceActiveFocus(); } }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 32, 312)
                    height: powerActions.implicitHeight + 32
                    radius: 12
                    color: "#242932"
                    border.color: "#596270"
                    MouseArea { anchors.fill: parent }

                    ColumnLayout {
                        id: powerActions
                        anchors.fill: parent
                        anchors.margins: 16
                        Label {
                            color: "#f2f3f5"
                            text: root.confirmation ? root.confirmation + " this computer?" : "Power"
                            font.pixelSize: 17
                            font.bold: true
                        }
                        Action { id: lockButton; visible: !root.confirmation; Layout.fillWidth: true; text: "Lock"; onClicked: root.power(text) }
                        Action { visible: !root.confirmation; Layout.fillWidth: true; text: "Sleep"; onClicked: root.power(text) }
                        Action { visible: !root.confirmation; Layout.fillWidth: true; text: "Restart"; onClicked: root.power(text) }
                        Action { visible: !root.confirmation; Layout.fillWidth: true; text: "Shut down"; onClicked: root.power(text) }
                        Action {
                            id: cancelButton
                            Layout.fillWidth: true
                            text: "Cancel"
                            onClicked: {
                                if (root.confirmation) {
                                    root.confirmation = "";
                                    lockButton.forceActiveFocus();
                                } else {
                                    root.powerOpen = false;
                                    search.forceActiveFocus();
                                }
                            }
                        }
                        Action {
                            visible: !!root.confirmation
                            Layout.fillWidth: true
                            text: root.confirmation || "Confirm"
                            onClicked: root.confirmPower()
                        }
                    }
                }
            }
        }
    }
}
