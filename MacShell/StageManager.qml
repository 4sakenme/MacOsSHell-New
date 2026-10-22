// StageManager.qml — macOS Ventura / Sonoma / Sequoia style 3D Stage Manager for Hyprland
//
// Features:
// 1. Group Stacking / Multi-window Clusters (1-3 windows per slot) with 3D stacked deck visual
// 2. Hover Fan-out: Background windows in a cluster fan out when hovered for preview peeking
// 3. Multi-icon squircle badges overlapping at bottom-left and group title labels underneath
// 4. Genuine 3D Perspective Skew & Foreshortening via Matrix4x4 + Y-Rotation
// 5. Drag & Drop grouping: drag windows between clusters to merge or separate them
// 6. Full-stage Swap & Zoom transition when activating a group onto the workspace

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

    // Grouping: maps window address -> cluster ID
    property var customGroups: ({})
    property var clusters: []
    property string activeAddress: ""
    property var activeIpcObject: null

    function normAddr(a) {
        if (!a) return "";
        var s = String(a).toLowerCase().trim();
        if (s.indexOf("0x") === 0) return s;
        return "0x" + s;
    }

    function updateWindows() {
        if (!root.enabled) {
            root.clusters = [];
            return;
        }

        try { Hyprland.refreshToplevels(); } catch (e) {}

        var atl = ToplevelManager.activeToplevel;
        var hts = Hyprland.toplevels.values;
        var actAddr = "";
        var activeLeft = 9999;
        var actObj = null;

        if (atl) {
            for (var i = 0; i < hts.length; i++) {
                if (hts[i].wayland === atl) {
                    actAddr = root.normAddr(hts[i].address);
                    var obj = hts[i].lastIpcObject || {};
                    if (obj.at && obj.at[0] !== undefined) activeLeft = obj.at[0];
                    actObj = obj;
                    break;
                }
            }
        }
        if (actAddr === "") {
            for (var aIdx = 0; aIdx < hts.length; aIdx++) {
                if (hts[aIdx].focusHistoryID === 0) {
                    actAddr = root.normAddr(hts[aIdx].address);
                    var o0 = hts[aIdx].lastIpcObject || {};
                    if (o0.at && o0.at[0] !== undefined) activeLeft = o0.at[0];
                    actObj = o0;
                    break;
                }
            }
        }
        root.activeAddress = actAddr;
        root.activeWindowLeft = activeLeft;
        root.activeIpcObject = actObj;

        var vals = ToplevelManager.toplevels.values;
        var bgWindows = [];
        var seenAddr = {};

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
                addr = root.normAddr(hit.address);
                if (hit.workspace && hit.workspace.id > 0) ws = hit.workspace.id;
                else if (hit.lastIpcObject && hit.lastIpcObject.workspace && hit.lastIpcObject.workspace.id > 0) ws = hit.lastIpcObject.workspace.id;
                var o = hit.lastIpcObject || {};
                if (ws === -98 || o.hidden || o.mapped === false) continue;
            }

            // Exclude currently active window
            if (addr !== "" && actAddr !== "" && addr === actAddr) continue;

            // Prevent duplicate entries
            if (addr !== "" && seenAddr[addr]) continue;
            if (addr !== "") seenAddr[addr] = true;

            var title = w.title || (hit && hit.lastIpcObject ? hit.lastIpcObject.title : "") || id;
            var de = id ? DesktopEntries.heuristicLookup(id) : null;
            var iconPath = "";
            if (de && de.icon) iconPath = Quickshell.iconPath(de.icon, true) || "";

            bgWindows.push({
                address: addr,
                title: title,
                appId: id,
                name: de && de.name ? de.name : id,
                iconPath: iconPath,
                tl: w,
                workspace: ws
            });
        }

        // Also add any Hyprland toplevels not found in ToplevelManager (e.g. XWayland)
        for (var h = 0; h < hts.length; h++) {
            var ht = hts[h];
            if (!ht) continue;
            var hAddr = root.normAddr(ht.address);
            if (hAddr === "" || seenAddr[hAddr] || (actAddr !== "" && hAddr === actAddr)) continue;

            var hWs = (ht.workspace && ht.workspace.id > 0) ? ht.workspace.id : 1;
            var ho = ht.lastIpcObject || {};
            if (hWs === -98 || ho.hidden || ho.mapped === false) continue;

            var hClass = ht.appId || ho.class || "";
            if (hClass === "org.quickshell" || hClass === "quickshell") continue;

            var hDe = hClass ? DesktopEntries.heuristicLookup(hClass) : null;
            var hIcon = "";
            if (hDe && hDe.icon) hIcon = Quickshell.iconPath(hDe.icon, true) || "";

            seenAddr[hAddr] = true;
            bgWindows.push({
                address: hAddr,
                title: ho.title || ht.title || hClass,
                appId: hClass,
                name: hDe && hDe.name ? hDe.name : hClass,
                iconPath: hIcon,
                tl: ht.wayland || null,
                workspace: hWs
            });
        }

        // ── Group windows into Multi-Window Clusters (1 to 3 windows per cluster) ──
        var clusterMap = {};
        var clusterOrder = [];

        for (var n = 0; n < bgWindows.length; n++) {
            var win = bgWindows[n];
            var gid = root.customGroups[win.address];
            if (!gid) {
                // Group by workspace by default
                gid = "ws_" + win.workspace;
            }

            if (!clusterMap[gid]) {
                clusterMap[gid] = {
                    id: gid,
                    name: win.name,
                    title: win.title,
                    workspace: win.workspace,
                    windows: []
                };
                clusterOrder.push(gid);
            }

            if (clusterMap[gid].windows.length < 3) {
                clusterMap[gid].windows.push(win);
            }
        }

        var resultClusters = [];
        for (var c = 0; c < clusterOrder.length && resultClusters.length < 6; c++) {
            var cl = clusterMap[clusterOrder[c]];
            if (cl && cl.windows.length > 0) {
                var names = [];
                for (var wIdx = 0; wIdx < cl.windows.length; wIdx++) {
                    var nm = cl.windows[wIdx].name || cl.windows[wIdx].appId;
                    if (names.indexOf(nm) < 0) names.push(nm);
                }
                cl.appsLabel = names.join(" & ");
                cl.name = cl.appsLabel;
                resultClusters.push(cl);
            }
        }

        root.clusters = resultClusters;
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
        else clusters = [];
    }

    Component.onCompleted: updateWindows()

    function activateCluster(cluster) {
        if (!cluster || !cluster.windows || cluster.windows.length === 0) return;

        var targetWs = cluster.workspace || (cluster.windows[0] ? cluster.windows[0].workspace : 1);
        var topAddr = String(cluster.windows[0].address || "").replace(/^0x/, "");

        // Switch to the target workspace and focus the window via Hyprland Lua
        var lua = "";
        if (targetWs) {
            lua += "hl.dispatch(hl.dsp.focus({ workspace = \"" + targetWs + "\" })); ";
        }
        if (topAddr !== "") {
            lua += "hl.dispatch(hl.dsp.focus({ window = \"address:0x" + topAddr + "\" })); ";
            lua += "hl.dispatch(hl.dsp.window.bring_to_top()); ";
        }

        Quickshell.execDetached(["hyprctl", "eval", lua]);

        if (cluster.windows[0].tl && typeof cluster.windows[0].tl.activate === "function") {
            try { cluster.windows[0].tl.activate(); } catch (e) {}
        }

        if (root.hub && root.hub.bar && typeof root.hub.bar.playSound === "function") {
            root.hub.bar.playSound("tink", 0.4);
        }
        root.updateWindows();
    }

    // Merge or separate window via drag-and-drop
    function assignWindowToGroup(winAddr, targetClusterId) {
        if (!winAddr) return;
        var map = {};
        for (var k in root.customGroups) map[k] = root.customGroups[k];
        if (targetClusterId) {
            map[winAddr] = targetClusterId;
        } else {
            // Detach to its own unique cluster
            map[winAddr] = "solo_" + Date.now() + "_" + Math.floor(Math.random() * 1000);
        }
        root.customGroups = map;
        root.updateWindows();
    }

    // Per-monitor PanelWindow
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "macshell-stagemanager"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            visible: root.enabled && (root.clusters.length > 0 || swapOverlay.running)

            property bool isRevealed: false
            readonly property bool stageVisible: root.forceReveal || isRevealed || (root.alwaysShow && root.activeWindowLeft > 320)

            // Drag and drop state across clusters
            property string draggingAddr: ""
            property var draggingWinObj: null
            property string hoverTargetClusterId: ""

            Timer {
                id: hideTimer
                interval: 360
                onTriggered: win.isRevealed = false
            }

            // Click-through mask
            mask: Region {
                item: swapOverlay.running ? null : (win.stageVisible ? stageContainer : triggerStrip)
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
            Item {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 320
                HoverHandler {
                    id: panelHover
                    onHoveredChanged: {
                        if (hovered) {
                            hideTimer.stop();
                            win.isRevealed = true;
                        } else if (!win.draggingAddr) {
                            hideTimer.restart();
                        }
                    }
                }
            }

            function lerp(a, b, t) {
                return a + (b - a) * t;
            }

            // ── 3D Stage Cards Container ──
            Item {
                id: stageContainer
                width: 300
                height: cardsColumn.implicitHeight + 40
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -10

                // Slide in/out animation
                x: win.stageVisible ? 20 : -280
                Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.08 } }

                Column {
                    id: cardsColumn
                    anchors.centerIn: parent
                    spacing: 26

                    Repeater {
                        model: root.clusters

                        delegate: Item {
                            id: clusterWrapper
                            required property var modelData
                            required property int index

                            width: 250
                            height: 185
                            z: clusterHover.hovered ? 60 : (20 - index)

                            readonly property bool isTargetDrop: win.hoverTargetClusterId === clusterWrapper.modelData.id && win.draggingAddr !== ""

                            // ── 3D Cluster Stack Item ──
                            Item {
                                id: stackContainer
                                width: 248
                                height: 154

                                property real pK: clusterHover.hovered ? 0.0003 : 0.0016
                                Behavior on pK { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                                transform: [
                                    Matrix4x4 {
                                        matrix: Qt.matrix4x4(
                                            1, 0, 0, 0,
                                            0, 1, 0, 0,
                                            0, 0, 1, 0,
                                            stackContainer.pK, 0, 0, 1
                                        )
                                    },
                                    Rotation {
                                        origin.x: 0
                                        origin.y: stackContainer.height / 2
                                        axis { x: 0; y: 1; z: 0 }
                                        angle: clusterHover.hovered ? -5 : -26
                                        Behavior on angle { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                    },
                                    Translate {
                                        x: (clusterHover.hovered ? 18 : 0) + (clusterWrapper.isTargetDrop ? 10 : 0)
                                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    },
                                    Scale {
                                        origin.x: 0
                                        origin.y: stackContainer.height / 2
                                        xScale: (clusterHover.hovered ? 1.05 : 0.96) * (clusterWrapper.isTargetDrop ? 1.06 : 1.0)
                                        yScale: xScale
                                        Behavior on xScale { NumberAnimation { duration: 200 } }
                                        Behavior on yScale { NumberAnimation { duration: 200 } }
                                    }
                                ]

                                // ── Stacked Deck Repeater (renders up to 3 windows in reverse z-order) ──
                                Repeater {
                                    model: clusterWrapper.modelData.windows

                                    delegate: Item {
                                        id: deckLayer
                                        required property var modelData
                                        required property int index

                                        // index 0 is front window; 1 is mid; 2 is back
                                        readonly property int depth: index
                                        z: 10 - depth

                                        // Hover Fan-out: cards spread out horizontally and vertically on hover
                                        property real fanSpread: clusterHover.hovered ? 1.0 : 0.0
                                        Behavior on fanSpread { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                                        x: depth * (clusterHover.hovered ? 26 : 12)
                                        y: -depth * (clusterHover.hovered ? 14 : 7)
                                        width: 248
                                        height: 154
                                        opacity: depth === 0 ? 1.0 : (depth === 1 ? (0.84 + 0.12 * fanSpread) : (0.72 + 0.18 * fanSpread))

                                        // 3D Shadow per deck layer
                                        Rectangle {
                                            anchors.fill: layerFrame
                                            radius: layerFrame.radius
                                            color: "#90000000"
                                            transform: Translate { x: 8 + depth * 3; y: 12 + depth * 2 }
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                blurEnabled: true
                                                blurMax: 32
                                                blur: 0.6
                                            }
                                        }

                                        // Window Thumbnail Frame
                                        Rectangle {
                                            id: layerFrame
                                            anchors.fill: parent
                                            radius: 12
                                            color: Qt.rgba(0.12, 0.12, 0.15, 0.88)
                                            clip: true
                                            border.width: clusterWrapper.isTargetDrop ? 2 : 1
                                            border.color: clusterWrapper.isTargetDrop ? "#38bdf8" : (clusterHover.hovered ? "#60ffffff" : "#30ffffff")
                                            Behavior on border.color { ColorAnimation { duration: 180 } }

                                            // Safe Wayland handle check
                                            readonly property var safeTl: {
                                                if (!win.stageVisible) return null;
                                                var a = deckLayer.modelData ? deckLayer.modelData.address : "";
                                                if (root.hub && a && root.hub.closingWins && root.hub.closingWins[String(a).replace(/^0x/, "")] === true) return null;
                                                if (root.hub && typeof root.hub.tlFor === "function" && a) {
                                                    var res = root.hub.tlFor(a);
                                                    if (res) return res;
                                                }
                                                return (deckLayer.modelData && deckLayer.modelData.tl) ? deckLayer.modelData.tl : null;
                                            }

                                            // Wayland live capture
                                            Loader {
                                                id: scLoader
                                                anchors.fill: parent
                                                active: win.stageVisible && layerFrame.safeTl !== null
                                                sourceComponent: ScreencopyView {
                                                    anchors.fill: parent
                                                    captureSource: (win.stageVisible && layerFrame.safeTl) ? layerFrame.safeTl : null
                                                    live: false
                                                    visible: hasContent
                                                }
                                            }

                                            // Fallback frosted card with app icon
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
                                                    width: 46; height: 46
                                                    sourceSize: Qt.size(64, 64)
                                                    source: deckLayer.modelData.iconPath
                                                    smooth: true
                                                    visible: deckLayer.modelData.iconPath !== ""
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: deckLayer.modelData.name
                                                    color: "white"
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 14
                                                    font.weight: Font.DemiBold
                                                    visible: deckLayer.modelData.iconPath === ""
                                                }
                                            }

                                            // Soft top sheen
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: parent.radius
                                                gradient: Gradient {
                                                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.14) }
                                                    GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── Multi-Icon Badges Row (Overlapping at bottom-left corner) ──
                                Row {
                                    id: multiIconRow
                                    anchors.left: stackContainer.left
                                    anchors.bottom: stackContainer.bottom
                                    anchors.leftMargin: -8
                                    anchors.bottomMargin: -8
                                    spacing: -10
                                    z: 40

                                    Repeater {
                                        model: clusterWrapper.modelData.windows

                                        delegate: Rectangle {
                                            id: appBadge
                                            required property var modelData
                                            required property int index
                                            z: 30 - index

                                            width: 32; height: 32; radius: 8
                                            color: Qt.rgba(0.12, 0.12, 0.15, 0.95)
                                            border.width: 1
                                            border.color: Qt.rgba(1, 1, 1, 0.35)
                                            scale: clusterHover.hovered ? 1.12 : 1.0
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
                                                source: appBadge.modelData.iconPath
                                                smooth: true
                                                visible: appBadge.modelData.iconPath !== ""
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                visible: appBadge.modelData.iconPath === ""
                                                text: appBadge.modelData.name.charAt(0).toUpperCase()
                                                color: "white"
                                                font.family: "Open Runde"
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                            }
                                        }
                                    }
                                }
                                // ── Workspace Tag Pill (Top-Right of card) ──
                                Rectangle {
                                    id: wsPill
                                    anchors.top: stackContainer.top
                                    anchors.right: stackContainer.right
                                    anchors.topMargin: 8
                                    anchors.rightMargin: 8
                                    height: 19
                                    radius: 6
                                    color: Qt.rgba(0.08, 0.08, 0.12, 0.78)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.22)
                                    z: 45
                                    implicitWidth: wsLabel.implicitWidth + 12

                                    Text {
                                        id: wsLabel
                                        anchors.centerIn: parent
                                        text: "Desktop " + clusterWrapper.modelData.workspace
                                        color: Qt.rgba(1, 1, 1, 0.9)
                                        font.family: "Open Runde"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            // ── Text Label Underneath (Group / Window Title & Workspace) ──
                            Column {
                                anchors.top: stackContainer.bottom
                                anchors.topMargin: 8
                                anchors.horizontalCenter: stackContainer.horizontalCenter
                                width: stackContainer.width - 16
                                spacing: 2

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: clusterWrapper.modelData.appsLabel || clusterWrapper.modelData.name || clusterWrapper.modelData.title
                                    color: Qt.rgba(1, 1, 1, 0.95)
                                    font.family: "Open Runde"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    style: Text.Outline
                                    styleColor: Qt.rgba(0, 0, 0, 0.75)
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Workspace " + clusterWrapper.modelData.workspace
                                    color: Qt.rgba(1, 1, 1, 0.65)
                                    font.family: "Open Runde"
                                    font.pixelSize: 10
                                    font.weight: Font.Normal
                                    style: Text.Outline
                                    styleColor: Qt.rgba(0, 0, 0, 0.75)
                                }
                            }

                            // ── Hover interaction ──
                            HoverHandler {
                                id: clusterHover
                                onHoveredChanged: {
                                    if (hovered) {
                                        hideTimer.stop();
                                        win.isRevealed = true;
                                        if (win.draggingAddr !== "") {
                                            win.hoverTargetClusterId = clusterWrapper.modelData.id;
                                        }
                                    } else {
                                        if (win.hoverTargetClusterId === clusterWrapper.modelData.id) {
                                            win.hoverTargetClusterId = "";
                                        }
                                    }
                                }
                            }

                            // ── Click to Swap & Drag to Group/Ungroup ──
                            MouseArea {
                                id: cardMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                property point pressPos: Qt.point(0, 0)
                                property bool hasMoved: false

                                onPressed: (mouse) => {
                                    pressPos = Qt.point(mouse.x, mouse.y);
                                    hasMoved = false;
                                    if (clusterWrapper.modelData.windows.length > 0) {
                                        win.draggingAddr = clusterWrapper.modelData.windows[0].address;
                                        win.draggingWinObj = clusterWrapper.modelData.windows[0];
                                    }
                                }

                                onPositionChanged: (mouse) => {
                                    var dx = Math.abs(mouse.x - pressPos.x);
                                    var dy = Math.abs(mouse.y - pressPos.y);
                                    if (!hasMoved && (dx > 8 || dy > 8)) {
                                        hasMoved = true;
                                        if (win.draggingWinObj) {
                                            var p = mapToItem(swapOverlay, mouse.x, mouse.y);
                                            dragProxy.x = p.x - 30;
                                            dragProxy.y = p.y - 30;
                                            dragProxy.visible = true;
                                        }
                                    }
                                    if (hasMoved && win.draggingAddr !== "") {
                                        var p2 = mapToItem(swapOverlay, mouse.x, mouse.y);
                                        dragProxy.x = p2.x - 30;
                                        dragProxy.y = p2.y - 30;
                                    }
                                }

                                onReleased: (mouse) => {
                                    if (hasMoved && win.draggingAddr !== "") {
                                        dragProxy.visible = false;
                                        var dropP = mapToItem(swapOverlay, mouse.x, mouse.y);
                                        if (dropP.x > 320) {
                                            // Dropped out onto desktop: detach into own cluster
                                            root.assignWindowToGroup(win.draggingAddr, null);
                                        } else if (win.hoverTargetClusterId && win.hoverTargetClusterId !== clusterWrapper.modelData.id) {
                                            // Merged into target cluster
                                            root.assignWindowToGroup(win.draggingAddr, win.hoverTargetClusterId);
                                        }
                                    } else {
                                        // User clicked: trigger Stage swap & activation!
                                        swapOverlay.startSwap(clusterWrapper.modelData, stackContainer);
                                    }
                                    win.draggingAddr = "";
                                    win.draggingWinObj = null;
                                    win.hoverTargetClusterId = "";
                                    hasMoved = false;
                                }
                            }
                        }
                    }
                }
            }

            // ── Floating Drag Proxy (follows cursor while dragging a thumbnail) ──
            Rectangle {
                id: dragProxy
                width: 60; height: 60; radius: 14
                color: Qt.rgba(0.12, 0.12, 0.15, 0.95)
                border.width: 1.5
                border.color: "#38bdf8"
                visible: false
                z: 200

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#90000000"
                    shadowBlur: 0.6
                    shadowVerticalOffset: 6
                }

                Image {
                    anchors.centerIn: parent
                    width: 36; height: 36
                    sourceSize: Qt.size(64, 64)
                    source: win.draggingWinObj ? win.draggingWinObj.iconPath : ""
                    smooth: true
                    visible: win.draggingWinObj && win.draggingWinObj.iconPath !== ""
                }
            }

            // ════════════════════════════════════════════════════════════════════
            // SWAP & ZOOM-OUT TRANSITION OVERLAY (macOS Stage Manager Window Swap)
            // ════════════════════════════════════════════════════════════════════
            Item {
                id: swapOverlay
                anchors.fill: parent
                visible: running
                property bool running: false
                property real progress: 0.0

                property var incomingCluster: null
                property var outgoing: null

                NumberAnimation {
                    id: swapAnim
                    target: swapOverlay
                    property: "progress"
                    from: 0.0
                    to: 1.0
                    duration: 290
                    easing.type: Easing.OutCubic
                    onFinished: {
                        swapOverlay.running = false;
                        var cl = swapOverlay.incomingCluster;
                        if (cl) {
                            root.activateCluster(cl);
                        }
                        swapOverlay.incomingCluster = null;
                        swapOverlay.outgoing = null;
                    }
                }

                function startSwap(clusterData, cardItem) {
                    if (swapOverlay.running) return;
                    var atl = ToplevelManager.activeToplevel;
                    var actAddr = root.activeAddress;
                    var actObj = root.activeIpcObject || {};

                    var actRect = {
                        x: (actObj.at && actObj.at[0] !== undefined) ? actObj.at[0] : 140,
                        y: (actObj.at && actObj.at[1] !== undefined) ? actObj.at[1] : 45,
                        width: (actObj.size && actObj.size[0] !== undefined) ? actObj.size[0] : (win.width - 280),
                        height: (actObj.size && actObj.size[1] !== undefined) ? actObj.size[1] : (win.height - 90)
                    };

                    var actIcon = "";
                    var actTitle = "";
                    if (actObj.class) {
                        var de = DesktopEntries.heuristicLookup(actObj.class);
                        if (de && de.icon) actIcon = Quickshell.iconPath(de.icon, true) || "";
                        actTitle = actObj.title || actObj.class;
                    }

                    var p = cardItem.mapToItem(swapOverlay, 0, 0);
                    var cardRect = { x: p.x, y: p.y, width: cardItem.width, height: cardItem.height };

                    incomingCluster = clusterData;
                    outgoing = {
                        address: actAddr,
                        tl: atl,
                        iconPath: actIcon,
                        title: actTitle,
                        startRect: actRect,
                        targetRect: cardRect
                    };

                    progress = 0.0;
                    running = true;
                    swapAnim.restart();
                }

                // ── Pha 2: Cụm cửa sổ active ở giữa (outgoing) co nhỏ, nghiêng dần về 3D và trượt lùi về cột Stage ──
                Rectangle {
                    id: outCard
                    visible: swapOverlay.outgoing !== null
                    radius: 12
                    color: Qt.rgba(0.12, 0.12, 0.15, 0.88)
                    border.width: 1
                    border.color: "#30ffffff"
                    clip: true
                    z: 80

                    property real p: swapOverlay.progress
                    property var o: swapOverlay.outgoing || ({ startRect: {x:0,y:0,width:1,height:1}, targetRect: {x:0,y:0,width:1,height:1} })

                    x: win.lerp(o.startRect.x, o.targetRect.x, p)
                    y: win.lerp(o.startRect.y, o.targetRect.y, p)
                    width: Math.max(1, win.lerp(o.startRect.width, o.targetRect.width, p))
                    height: Math.max(1, win.lerp(o.startRect.height, o.targetRect.height, p))
                    opacity: 1.0 - 0.25 * p

                    transform: [
                        Matrix4x4 {
                            matrix: Qt.matrix4x4(
                                1, 0, 0, 0,
                                0, 1, 0, 0,
                                0, 0, 1, 0,
                                win.lerp(0.0, 0.0016, outCard.p), 0, 0, 1
                            )
                        },
                        Rotation {
                            origin.x: 0
                            origin.y: outCard.height / 2
                            axis { x: 0; y: 1; z: 0 }
                            angle: win.lerp(0, -26, outCard.p)
                        }
                    ]

                    Image {
                        anchors.centerIn: parent
                        width: 52; height: 52
                        sourceSize: Qt.size(64, 64)
                        source: outCard.o.iconPath || ""
                        smooth: true
                        visible: outCard.o.iconPath !== ""
                    }
                }

                // ── Pha 1: Cụm được chọn (incoming) xoay từ nghiêng 3D về phẳng, phóng to và lướt ra giữa màn hình ──
                Rectangle {
                    id: inCard
                    visible: swapOverlay.incomingCluster !== null && swapOverlay.incomingCluster.windows.length > 0
                    radius: 12
                    color: Qt.rgba(0.12, 0.12, 0.15, 0.92)
                    border.width: 1
                    border.color: inCard.p < 0.8 ? "#50ffffff" : Qt.rgba(1, 1, 1, 1.0 - inCard.p)
                    clip: true
                    z: 100

                    property real p: swapOverlay.progress
                    readonly property var topWin: (swapOverlay.incomingCluster && swapOverlay.incomingCluster.windows.length > 0) ? swapOverlay.incomingCluster.windows[0] : null
                    property var startRect: (swapOverlay.outgoing && swapOverlay.outgoing.targetRect) ? swapOverlay.outgoing.targetRect : ({ x: 20, y: 200, width: 248, height: 154 })
                    property var targetRect: (swapOverlay.outgoing && swapOverlay.outgoing.startRect) ? swapOverlay.outgoing.startRect : ({ x: 140, y: 45, width: 1400, height: 800 })

                    x: win.lerp(startRect.x, targetRect.x, p)
                    y: win.lerp(startRect.y, targetRect.y, p)
                    width: Math.max(1, win.lerp(startRect.width, targetRect.width, p))
                    height: Math.max(1, win.lerp(startRect.height, targetRect.height, p))
                    opacity: 1.0

                    transform: [
                        Matrix4x4 {
                            matrix: Qt.matrix4x4(
                                1, 0, 0, 0,
                                0, 1, 0, 0,
                                0, 0, 1, 0,
                                win.lerp(0.0016, 0.0, inCard.p), 0, 0, 1
                            )
                        },
                        Rotation {
                            origin.x: 0
                            origin.y: inCard.height / 2
                            axis { x: 0; y: 1; z: 0 }
                            angle: win.lerp(-26, 0, inCard.p)
                        }
                    ]

                    Image {
                        anchors.centerIn: parent
                        width: 64; height: 64
                        sourceSize: Qt.size(80, 80)
                        source: inCard.topWin ? inCard.topWin.iconPath : ""
                        smooth: true
                        visible: inCard.topWin && inCard.topWin.iconPath !== ""
                    }

                    Text {
                        anchors.centerIn: parent
                        text: inCard.topWin ? inCard.topWin.title : ""
                        color: "white"
                        font.family: "Open Runde"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        visible: !inCard.topWin || inCard.topWin.iconPath === ""
                    }
                }
            }
        }
    }
}
