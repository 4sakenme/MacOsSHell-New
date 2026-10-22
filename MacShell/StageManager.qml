// StageManager.qml — macOS Ventura / Sonoma / Sequoia style 3D Stage Manager for Hyprland
//
// Shows a perspective-angled vertical stack of background windows along the left screen edge.
// Auto-reveals on left-edge mouse hover or when free desktop space allows.
// Clicking a card brings that window onto the main stage and swaps the current active window out.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property var hub: null
    property bool enabled: (hub && hub.bar) ? hub.bar.stageManager : true
    property bool alwaysShow: false           // true = stay visible when screen isn't crowded
    property bool forceReveal: false          // true = force open panel (e.g. via gesture or IPC)
    property real activeWindowLeft: 9999

    // List of inactive/background windows on the system
    property var backgroundWindows: []
    property string activeAddress: ""

    function updateWindows() {
        if (!root.enabled) {
            root.backgroundWindows = [];
            return;
        }

        try { Hyprland.refreshToplevels(); } catch (e) {}

        var atl = ToplevelManager.activeToplevel;
        var hts = Hyprland.toplevels.values;
        var activeLeft = 9999;

        if (atl) {
            for (var i = 0; i < hts.length; i++) {
                if (hts[i].wayland === atl) {
                    var obj = hts[i].lastIpcObject || {};
                    if (obj.at && obj.at[0] !== undefined) activeLeft = obj.at[0];
                    break;
                }
            }
        }
        root.activeWindowLeft = activeLeft;

        var vals = ToplevelManager.toplevels.values;
        var list = [];

        for (var j = 0; j < vals.length; j++) {
            var w = vals[j];
            if (!w) continue;
            if (atl && w === atl) continue;

            var id = w.appId || "";
            if (id === "org.quickshell" || id === "quickshell") continue;

            // Match with Hyprland toplevel for workspace and address
            var hit = null;
            for (var k = 0; k < hts.length; k++) {
                if (hts[k].wayland === w) { hit = hts[k]; break; }
            }

            var addr = "";
            var ws = 1;
            if (hit) {
                addr = String(hit.address || "");
                if (addr.indexOf("0x") !== 0 && addr !== "") addr = "0x" + addr;
                if (hit.workspace && hit.workspace.id > 0) ws = hit.workspace.id;
                else if (hit.lastIpcObject && hit.lastIpcObject.workspace && hit.lastIpcObject.workspace.id > 0) ws = hit.lastIpcObject.workspace.id;
                var o = hit.lastIpcObject || {};
                if (ws === -98 || o.hidden || o.mapped === false) continue;
            }

            var title = w.title || (hit && hit.lastIpcObject ? hit.lastIpcObject.title : "") || id;
            var de = id ? DesktopEntries.heuristicLookup(id) : null;
            var iconPath = "";
            if (de && de.icon) iconPath = Quickshell.iconPath(de.icon, true) || "";

            list.push({
                address: addr,
                title: title,
                appId: id,
                name: de && de.name ? de.name : id,
                iconPath: iconPath,
                tl: w,
                workspace: ws
            });
        }

        root.backgroundWindows = list.slice(0, 6);
    }

    Timer {
        id: pollTimer
        interval: 650
        repeat: true
        running: root.enabled
        onTriggered: root.updateWindows()
    }

    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() { root.updateWindows(); }
    }

    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { root.updateWindows(); }
    }

    onEnabledChanged: {
        if (enabled) updateWindows();
        else backgroundWindows = [];
    }

    Component.onCompleted: updateWindows()

    function activateWindow(addr, winWs, tl) {
        var a = String(addr || "").replace(/^0x/, "");
        var lua = "";
        if (winWs && winWs > 0) {
            lua += "hl.dispatch(hl.dsp.focus({ workspace = \"" + winWs + "\" })); ";
        }
        if (a !== "") {
            lua += "hl.dispatch(hl.dsp.focus({ window = \"address:0x" + a + "\" })); ";
        }
        lua += "hl.dispatch(hl.dsp.window.bring_to_top())";
        Quickshell.execDetached(["hyprctl", "eval", lua]);
        if (tl && typeof tl.activate === "function") {
            try { tl.activate(); } catch (e) {}
        }
        if (root.hub && root.hub.bar && typeof root.hub.bar.playSound === "function") {
            root.hub.bar.playSound("tink", 0.4);
        }
        root.updateWindows();
    }

    // Per-monitor PanelWindow
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors { top: true; bottom: true; left: true }
            width: 340
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "macshell-stagemanager"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            visible: root.enabled && root.backgroundWindows.length > 0

            property bool isRevealed: false

            readonly property bool stageVisible: root.forceReveal || isRevealed || (root.alwaysShow && root.activeWindowLeft > 280)

            Timer {
                id: hideTimer
                interval: 320
                onTriggered: win.isRevealed = false
            }

            // Click-through mask: when hidden only the 18px edge strip intercepts hover;
            // when revealed the cards container handles clicks and everything else is 100% click-through.
            mask: Region {
                item: win.stageVisible ? stageContainer : triggerStrip
            }

            // ── Left edge trigger strip (18px wide) ──
            Item {
                id: triggerStrip
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 18

                HoverHandler {
                    id: edgeHover
                    onHoveredChanged: {
                        if (hovered) {
                            hideTimer.stop();
                            win.isRevealed = true;
                        }
                    }
                }
            }

            // ── Global hover area across the stage panel to avoid jitter ──
            HoverHandler {
                id: panelHover
                onHoveredChanged: {
                    if (hovered) {
                        hideTimer.stop();
                        win.isRevealed = true;
                    } else {
                        hideTimer.restart();
                    }
                }
            }

            // ── 3D Stage Cards Container ──
            Item {
                id: stageContainer
                width: 290
                height: cardsColumn.implicitHeight + 50
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -10

                // Slide in/out animation
                x: win.stageVisible ? 18 : -260
                Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.08 } }

                Column {
                    id: cardsColumn
                    anchors.centerIn: parent
                    spacing: 20

                    Repeater {
                        model: root.backgroundWindows

                        delegate: Item {
                            id: cardWrapper
                            required property var modelData
                            required property int index

                            width: 240
                            height: 150
                            z: cardHover.hovered ? 50 : (20 - index)

                            property bool isFlying: false
                            property real hoverProg: cardHover.hovered ? 1.0 : 0.0
                            Behavior on hoverProg { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                            // ── 3D Perspective Tilt & Foreshortening ──
                            property real pK: cardHover.hovered ? 0.0003 : 0.0016
                            Behavior on pK { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                            transform: [
                                Matrix4x4 {
                                    matrix: Qt.matrix4x4(
                                        1, 0, 0, 0,
                                        0, 1, 0, 0,
                                        0, 0, 1, 0,
                                        cardWrapper.pK, 0, 0, 1
                                    )
                                },
                                Rotation {
                                    origin.x: 0
                                    origin.y: cardWrapper.height / 2
                                    axis { x: 0; y: 1; z: 0 }
                                    angle: cardHover.hovered ? -6 : -28
                                    Behavior on angle { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                },
                                Translate {
                                    x: (cardHover.hovered ? 20 : 0) + (cardWrapper.isFlying ? 180 : 0)
                                    Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                },
                                Scale {
                                    origin.x: 0
                                    origin.y: cardWrapper.height / 2
                                    xScale: (cardHover.hovered ? 1.05 : 0.95) * (cardWrapper.isFlying ? 1.25 : 1.0)
                                    yScale: xScale
                                    Behavior on xScale { NumberAnimation { duration: 200 } }
                                    Behavior on yScale { NumberAnimation { duration: 200 } }
                                }
                            ]

                            // ── 3D Deep Shadow ──
                            Rectangle {
                                anchors.fill: cardFrame
                                radius: cardFrame.radius
                                color: "#90000000"
                                transform: Translate { x: 8; y: 12 }
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    blurEnabled: true
                                    blurMax: 32
                                    blur: 0.6
                                }
                            }

                            // ── Window Thumbnail Card ──
                            Rectangle {
                                id: cardFrame
                                anchors.fill: parent
                                radius: 12
                                color: Qt.rgba(0.12, 0.12, 0.15, 0.85)
                                clip: true
                                border.width: 1
                                border.color: cardHover.hovered ? "#60ffffff" : "#30ffffff"
                                Behavior on border.color { ColorAnimation { duration: 200 } }

                                // Wayland screencopy capture of the background window
                                Loader {
                                    id: scLoader
                                    anchors.fill: parent
                                    active: cardWrapper.modelData && cardWrapper.modelData.tl !== null
                                    sourceComponent: ScreencopyView {
                                        anchors.fill: parent
                                        captureSource: cardWrapper.modelData ? cardWrapper.modelData.tl : null
                                        live: false
                                        visible: hasContent
                                    }
                                }

                                // Fallback frosted card with app icon if screencopy is not ready yet
                                Item {
                                    visible: !scLoader.item || !scLoader.item.hasContent
                                    anchors.fill: parent

                                    Rectangle {
                                        anchors.fill: parent
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: Qt.rgba(0.24, 0.24, 0.28, 0.88) }
                                            GradientStop { position: 1.0; color: Qt.rgba(0.13, 0.13, 0.16, 0.92) }
                                        }
                                    }

                                    Image {
                                        anchors.centerIn: parent
                                        width: 48; height: 48
                                        sourceSize: Qt.size(64, 64)
                                        source: cardWrapper.modelData.iconPath
                                        smooth: true
                                        visible: cardWrapper.modelData.iconPath !== ""
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: cardWrapper.modelData.name
                                        color: "white"
                                        font.family: "Open Runde"
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                        visible: cardWrapper.modelData.iconPath === ""
                                    }
                                }

                                // Soft top sheen
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.12) }
                                        GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0.0) }
                                    }
                                }
                            }

                            // ── App Icon Badge (32x32px, overlapping bottom-left corner) ──
                            Rectangle {
                                id: appBadge
                                width: 32; height: 32; radius: 16
                                anchors.bottom: cardFrame.bottom
                                anchors.left: cardFrame.left
                                anchors.bottomMargin: -6
                                anchors.leftMargin: -6
                                z: 30
                                color: Qt.rgba(0.12, 0.12, 0.15, 0.95)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.35)
                                scale: cardHover.hovered ? 1.12 : 1.0
                                Behavior on scale { NumberAnimation { duration: 200 } }
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: "#90000000"
                                    shadowBlur: 0.4
                                    shadowVerticalOffset: 2
                                }

                                Image {
                                    anchors.centerIn: parent
                                    width: 20; height: 20
                                    sourceSize: Qt.size(40, 40)
                                    source: cardWrapper.modelData.iconPath
                                    smooth: true
                                    visible: cardWrapper.modelData.iconPath !== ""
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: cardWrapper.modelData.iconPath === ""
                                    text: cardWrapper.modelData.name.charAt(0).toUpperCase()
                                    color: "white"
                                    font.family: "Open Runde"
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }
                            }

                            // ── Floating Title Tooltip ──
                            Item {
                                id: titleTooltip
                                z: 40
                                opacity: cardHover.hovered ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 180 } }
                                x: cardWrapper.width + 16
                                anchors.verticalCenter: cardWrapper.verticalCenter
                                width: Math.min(220, tipText.implicitWidth + 24)
                                height: 30

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 15
                                    color: Qt.rgba(0.10, 0.10, 0.13, 0.90)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.25)
                                }

                                Text {
                                    id: tipText
                                    anchors.centerIn: parent
                                    width: parent.width - 20
                                    text: cardWrapper.modelData.title || cardWrapper.modelData.name
                                    color: "white"
                                    font.family: "Open Runde"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            // ── Hover & Click interaction ──
                            HoverHandler {
                                id: cardHover
                                onHoveredChanged: {
                                    if (hovered) {
                                        hideTimer.stop();
                                        win.isRevealed = true;
                                        if (scLoader.item && typeof scLoader.item.captureFrame === "function") {
                                            scLoader.item.captureFrame();
                                        }
                                    }
                                }
                            }

                            TapHandler {
                                onTapped: {
                                    cardWrapper.isFlying = true;
                                    flyTimer.restart();
                                }
                            }

                            Timer {
                                id: flyTimer
                                interval: 140
                                onTriggered: {
                                    root.activateWindow(cardWrapper.modelData.address, cardWrapper.modelData.workspace, cardWrapper.modelData.tl);
                                    cardWrapper.isFlying = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
