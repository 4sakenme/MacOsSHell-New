// StageManager.qml — macOS Ventura / Sonoma / Sequoia style 3D Stage Manager for Hyprland
//
// Features:
// 1. Group Stacking / Multi-window Clusters (1-3 windows per slot) with 3D stacked deck visual
// 2. Hover Fan-out: Background windows in a cluster fan out when hovered for preview peeking
// 3. Multi-icon squircle badges overlapping at bottom-left and group title labels underneath
// 4. Genuine 3D Perspective Skew & Foreshortening via Matrix4x4 + Y-Rotation
// 5. Drag & Drop grouping: drag windows between clusters to merge or separate them
// 6. Full macOS-style Swap Transition: 300ms InOutCubic rotate/scale/translate animation between center & stage
// 7. Auto-shove / Hide: panel hides (x: -300) when active window touches left edge, smoothly reveals on edge hover
// 8. Multi-window Shuffle: repeated clicks on active group cycle sub-windows (z-order shuffle) without cursor warp

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

    // ── Auto-shove state ──
    // true = active window is closer than 290px to the left edge, stage manager should tuck away
    property bool autoShove: false

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

        // Fast fallback for geometry if lastIpcObject wasn't populated yet
        if (activeLeft === 9999 && root.hub && root.hub.glassClients && actAddr !== "") {
            var gc = root.hub.glassClients;
            var cleanAct = actAddr.replace(/^0x/, "");
            for (var g = 0; g < gc.length; g++) {
                var cAddr = String(gc[g].address || "").replace(/^0x/, "").toLowerCase();
                if (cAddr === cleanAct && gc[g].at) {
                    activeLeft = gc[g].at[0];
                    break;
                }
            }
        }

        root.activeAddress = actAddr;
        root.activeWindowLeft = activeLeft;
        root.activeIpcObject = actObj;

        // ── Auto-shove calculation: hide when active window is closer than 290px to the left edge ──
        root.autoShove = (activeLeft < 290);

        var vals = ToplevelManager.toplevels.values;
        var allWindows = [];
        var seenAddr = {};

        // 1. Gather all Wayland toplevels
        for (var j = 0; j < vals.length; j++) {
            var w = vals[j];
            if (!w) continue;

            var id = w.appId || "";
            if (id === "org.quickshell" || id === "quickshell") continue;

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

            if (addr !== "" && seenAddr[addr]) continue;
            if (addr !== "") seenAddr[addr] = true;

            var title = w.title || (hit && hit.lastIpcObject ? hit.lastIpcObject.title : "") || id;
            var de = id ? DesktopEntries.heuristicLookup(id) : null;
            var iconPath = "";
            if (de && de.icon) iconPath = Quickshell.iconPath(de.icon, true) || "";

            allWindows.push({
                address: addr,
                title: title,
                appId: id,
                name: de && de.name ? de.name : id,
                iconPath: iconPath,
                tl: w,
                workspace: ws,
                isActive: (addr !== "" && actAddr !== "" && addr === actAddr)
            });
        }

        // 2. Also add any Hyprland toplevels not found in ToplevelManager (e.g. XWayland)
        for (var h = 0; h < hts.length; h++) {
            var ht = hts[h];
            if (!ht) continue;
            var hAddr = root.normAddr(ht.address);
            if (hAddr === "" || seenAddr[hAddr]) continue;

            var hWs = (ht.workspace && ht.workspace.id > 0) ? ht.workspace.id : 1;
            var ho = ht.lastIpcObject || {};
            if (hWs === -98 || ho.hidden || ho.mapped === false) continue;

            var hClass = ht.appId || ho.class || "";
            if (hClass === "org.quickshell" || hClass === "quickshell") continue;

            var hDe = hClass ? DesktopEntries.heuristicLookup(hClass) : null;
            var hIcon = "";
            if (hDe && hDe.icon) hIcon = Quickshell.iconPath(hDe.icon, true) || "";

            seenAddr[hAddr] = true;
            allWindows.push({
                address: hAddr,
                title: ho.title || ht.title || hClass,
                appId: hClass,
                name: hDe && hDe.name ? hDe.name : hClass,
                iconPath: hIcon,
                tl: ht.wayland || null,
                workspace: hWs,
                isActive: (hAddr !== "" && actAddr !== "" && hAddr === actAddr)
            });
        }

        // 3. Group windows into Multi-Window Clusters (1 to 3 windows per cluster)
        var clusterMap = {};
        var clusterOrder = [];

        for (var n = 0; n < allWindows.length; n++) {
            var winObj = allWindows[n];
            var gid = root.customGroups[winObj.address];
            if (!gid) {
                gid = "ws_" + winObj.workspace;
            }

            if (!clusterMap[gid]) {
                clusterMap[gid] = {
                    id: gid,
                    name: winObj.name,
                    title: winObj.title,
                    workspace: winObj.workspace,
                    windows: []
                };
                clusterOrder.push(gid);
            }

            if (clusterMap[gid].windows.length < 3) {
                clusterMap[gid].windows.push(winObj);
            }
        }

        // 4. Build result clusters:
        //    - If a cluster has only 1 window AND that window is active: don't show on stage strip (it's already center stage)
        //    - If a cluster has >= 2 windows AND contains active window: KEEP IT on stage strip for shuffle, with active window in front
        //    - If a cluster is inactive: show on stage strip
        var resultClusters = [];
        for (var c = 0; c < clusterOrder.length && resultClusters.length < 6; c++) {
            var cl = clusterMap[clusterOrder[c]];
            if (!cl || cl.windows.length === 0) continue;

            var hasActiveWin = false;
            var activeIdx = -1;
            for (var wI = 0; wI < cl.windows.length; wI++) {
                if (cl.windows[wI].address === actAddr) {
                    hasActiveWin = true;
                    activeIdx = wI;
                    break;
                }
            }

            // A solo active window is already occupying center workspace: hide its card
            if (hasActiveWin && cl.windows.length === 1) {
                continue;
            }

            // Multi-window group that is currently active: keep active window in front (index 0)
            if (hasActiveWin && activeIdx > 0) {
                var actItem = cl.windows.splice(activeIdx, 1);
                cl.windows.unshift(actItem[0]);
            }

            var names = [];
            for (var wIdx = 0; wIdx < cl.windows.length; wIdx++) {
                var nm = cl.windows[wIdx].name || cl.windows[wIdx].appId;
                if (names.indexOf(nm) < 0) names.push(nm);
            }
            cl.appsLabel = names.join(" & ");
            cl.name = cl.appsLabel;
            resultClusters.push(cl);
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

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            var en = event.name;
            if (en === "activewindow" || en === "activewindowv2" || en === "movewindow" || en === "movewindowv2" ||
                en === "changefloatingmode" || en === "fullscreen" || en === "workspace" || en === "workspacev2") {
                root.updateWindows();
            }
        }
    }

    onEnabledChanged: {
        if (enabled) updateWindows();
        else clusters = [];
    }

    Component.onCompleted: updateWindows()

    function getFreeWorkspace(excludeWs) {
        var used = {};
        if (excludeWs) used[excludeWs] = true;
        var hts = Hyprland.toplevels.values;
        for (var i = 0; i < hts.length; i++) {
            var ht = hts[i];
            if (ht && ht.workspace && ht.workspace.id > 0) {
                used[ht.workspace.id] = true;
            }
        }
        for (var w = 1; w < 100; w++) {
            if (!used[w]) return w;
        }
        return 9;
    }

    // Helper: checks if any window in this cluster is currently the active window
    function isClusterActive(cluster) {
        if (!cluster || !cluster.windows || cluster.windows.length === 0) return false;
        var act = root.normAddr(root.activeAddress);
        if (!act) return false;
        for (var i = 0; i < cluster.windows.length; i++) {
            if (root.normAddr(cluster.windows[i].address) === act) {
                return true;
            }
        }
        return false;
    }

    // ── Shuffle / Loop between windows in a grouped cluster (Click 2+) ──
    function shuffleCluster(cluster, specificIdx) {
        if (!cluster || !cluster.windows || cluster.windows.length < 2) return;

        var wins = cluster.windows.slice();
        // If user specifically clicked a peeking sub-card, target that one; otherwise rotate to next window (index 1)
        var targetIdx = (specificIdx !== undefined && specificIdx >= 0 && specificIdx < wins.length) ? specificIdx : 1;
        var targetWin = wins[targetIdx];
        if (!targetWin) return;

        // Rotate array: targetWin moves to index 0, old front moves to back
        var removed = wins.splice(targetIdx, 1);
        wins.unshift(removed[0]);
        cluster.windows = wins;

        var targetAddr = String(targetWin.address || "").replace(/^0x/, "");
        var targetWs = targetWin.workspace || 1;

        if (targetWs) {
            Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(targetWs)]);
        }
        if (targetAddr !== "") {
            Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:0x" + targetAddr]);
            Quickshell.execDetached(["hyprctl", "dispatch", "bring_to_top"]);
        }

        if (targetWin.tl && typeof targetWin.tl.activate === "function") {
            try { targetWin.tl.activate(); } catch (e) {}
        }

        if (root.hub && root.hub.bar && typeof root.hub.bar.playSound === "function") {
            root.hub.bar.playSound("tink", 0.35);
        }

        root.activeAddress = root.normAddr(targetWin.address);
        // Force model refresh to trigger deck layer animation
        root.clusters = root.clusters.slice();
        root.updateWindows();
    }

    // ── Merge or separate window via drag-and-drop ──
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

            visible: root.enabled && root.clusters.length > 0

            property bool isRevealed: false
            readonly property bool isAutoShoved: root.autoShove && !isRevealed
            readonly property bool stageShown: !isAutoShoved && (root.forceReveal || isRevealed || !root.autoShove || (root.alwaysShow && root.activeWindowLeft > 320))
            property int hoveredCardsCount: 0

            // Drag and drop state across clusters
            property string draggingAddr: ""
            property var draggingWinObj: null
            property string hoverTargetClusterId: ""

            // Reference to swap overlay for child items
            property alias swapOverlayRef: swapOverlay

            // ── Hide Timer: smooth delay before auto-tucking away ──
            Timer {
                id: hideTimer
                interval: 400
                onTriggered: {
                    if (win.hoveredCardsCount === 0 && !panelHover.hovered && !edgeHover.hovered && !win.draggingAddr) {
                        win.isRevealed = false;
                    }
                }
            }

            // ── Wayland Input Mask ──
            // When auto-shoved: only a 24px strip at left edge captures mouse (transparent to everything else).
            // When shown: 330px covers the stage sidebar.
            // During swap animation: covers full screen to prevent accidental clicks.
            Item {
                id: inputArea
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: swapOverlay.visible ? win.width : (win.stageShown ? 330 : 24)
            }

            mask: Region {
                item: inputArea
            }

            // ── Left Edge Hover Zone (24px wide): triggers instant reveal when shoved ──
            Item {
                id: edgeHoverZone
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 24
                z: 100

                HoverHandler {
                    id: edgeHover
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onHoveredChanged: {
                        if (hovered) {
                            hideTimer.stop();
                            win.isRevealed = true;
                        } else if (!panelHover.hovered && win.hoveredCardsCount === 0 && !win.draggingAddr) {
                            hideTimer.restart();
                        }
                    }
                }
            }

            // ── Unified Hover Area across the stage panel (330px) ──
            Item {
                id: panelHoverArea
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 330

                HoverHandler {
                    id: panelHover
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onHoveredChanged: {
                        if (hovered) {
                            hideTimer.stop();
                            win.isRevealed = true;
                        } else if (!edgeHover.hovered && win.hoveredCardsCount === 0 && !win.draggingAddr) {
                            hideTimer.restart();
                        }
                    }
                }
            }

            function lerp(a, b, t) { return a + (b - a) * t; }

            // ── 3D Stage Cards Container ──
            Item {
                id: stageContainer
                width: 270
                height: cardsColumn.implicitHeight + 40
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -10

                // Slide in/out animation:
                // When shoved: slides off-screen to x: -300
                // When shown: smoothly settles at x: 12
                x: win.stageShown ? 12 : -300
                Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Column {
                    id: cardsColumn
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 26

                    Repeater {
                        model: root.clusters

                        delegate: Item {
                            id: clusterWrapper
                            required property var modelData
                            required property int index

                            width: 250
                            height: 185
                            z: isHovered ? 60 : (20 - index)

                            property int hoveredSubIndex: -1
                            readonly property bool isHovered: cardMouseArea.containsMouse
                            readonly property bool isTargetDrop: win.hoverTargetClusterId === clusterWrapper.modelData.id && win.draggingAddr !== ""

                            // ── 3D Cluster Stack Item (3D Perspective Skew & Hover Fan-out) ──
                            Item {
                                id: stackContainer
                                width: 248
                                height: 154

                                property real pK: clusterWrapper.isHovered ? 0.0004 : 0.0016
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
                                        angle: clusterWrapper.isHovered ? -7 : -25
                                        Behavior on angle { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                    },
                                    Translate {
                                        x: (clusterWrapper.isHovered ? 14 : 0) + (clusterWrapper.isTargetDrop ? 10 : 0)
                                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    },
                                    Scale {
                                        origin.x: 0
                                        origin.y: stackContainer.height / 2
                                        xScale: (clusterWrapper.isHovered ? 1.05 : 0.96) * (clusterWrapper.isTargetDrop ? 1.06 : 1.0)
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
                                        readonly property bool isThisSubHovered: clusterWrapper.hoveredSubIndex === index
                                        z: isThisSubHovered ? 45 : (10 - depth)

                                        // Sub-app hover peek / fan-out: background cards fan out gracefully when hovered
                                        x: depth * (clusterWrapper.isHovered ? 26 : 12) + (isThisSubHovered && depth > 0 ? 34 : 0)
                                        y: -depth * (clusterWrapper.isHovered ? 14 : 7) - (isThisSubHovered && depth > 0 ? 10 : 0)
                                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                                        scale: isThisSubHovered ? 1.05 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 180 } }

                                        width: 248
                                        height: 154
                                        opacity: (depth === 0 || isThisSubHovered) ? 1.0 : (depth === 1 ? (clusterWrapper.isHovered ? 0.94 : 0.84) : (clusterWrapper.isHovered ? 0.88 : 0.72))
                                        Behavior on opacity { NumberAnimation { duration: 180 } }

                                        // Hover detector for sub-app peek
                                        HoverHandler {
                                            id: subHover
                                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                            onHoveredChanged: {
                                                if (hovered) {
                                                    clusterWrapper.hoveredSubIndex = deckLayer.index;
                                                } else if (clusterWrapper.hoveredSubIndex === deckLayer.index) {
                                                    clusterWrapper.hoveredSubIndex = -1;
                                                }
                                            }
                                        }

                                        // 3D Drop Shadow per deck layer
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
                                            border.width: (clusterWrapper.isTargetDrop || deckLayer.isThisSubHovered) ? 2 : 1
                                            border.color: clusterWrapper.isTargetDrop ? "#38bdf8" : (deckLayer.isThisSubHovered ? "#38bdf8" : (clusterWrapper.isHovered ? "#60ffffff" : "#30ffffff"))
                                            Behavior on border.color { ColorAnimation { duration: 180 } }

                                            // Safe Wayland handle check
                                            readonly property var safeTl: {
                                                if (!win.stageShown) return null;
                                                var a = deckLayer.modelData ? deckLayer.modelData.address : "";
                                                if (!a) return null;
                                                if (root.hub && root.hub.closingWins && root.hub.closingWins[String(a).replace(/^0x/, "")] === true) return null;
                                                if (root.hub && typeof root.hub.tlFor === "function") {
                                                    var t = root.hub.tlTick;
                                                    return root.hub.tlFor(a);
                                                }
                                                return null;
                                            }

                                            // Wayland live capture
                                            Loader {
                                                id: scLoader
                                                anchors.fill: parent
                                                active: win.stageShown && layerFrame.safeTl !== null
                                                sourceComponent: ScreencopyView {
                                                    anchors.fill: parent
                                                    captureSource: (win.stageShown && layerFrame.safeTl) ? layerFrame.safeTl : null
                                                    live: false
                                                    visible: hasContent
                                                }
                                            }

                                            // Fallback frosted card with app icon & name
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
                                            scale: clusterWrapper.isHovered ? 1.12 : 1.0
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

                            // ── Click to Swap/Shuffle & Drag to Group/Ungroup ──
                            MouseArea {
                                id: cardMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onEntered: {
                                    win.hoveredCardsCount++;
                                    hideTimer.stop();
                                    win.isRevealed = true;
                                    if (win.draggingAddr !== "") {
                                        win.hoverTargetClusterId = clusterWrapper.modelData.id;
                                    }
                                }

                                onExited: {
                                    win.hoveredCardsCount = Math.max(0, win.hoveredCardsCount - 1);
                                    if (win.hoverTargetClusterId === clusterWrapper.modelData.id) {
                                        win.hoverTargetClusterId = "";
                                    }
                                    if (win.hoveredCardsCount === 0 && !panelHover.hovered && !edgeHover.hovered && !win.draggingAddr) {
                                        hideTimer.restart();
                                    }
                                }

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
                                            var p = mapToItem(stageContainer, mouse.x, mouse.y);
                                            dragProxy.x = p.x - 34;
                                            dragProxy.y = p.y - 34;
                                            dragProxy.visible = true;
                                        }
                                    }
                                    if (hasMoved && win.draggingAddr !== "") {
                                        var p2 = mapToItem(stageContainer, mouse.x, mouse.y);
                                        dragProxy.x = p2.x - 34;
                                        dragProxy.y = p2.y - 34;

                                        var posInCol = mapToItem(cardsColumn, mouse.x, mouse.y);
                                        var targetId = "";
                                        for (var i = 0; i < cardsColumn.children.length; i++) {
                                            var item = cardsColumn.children[i];
                                            if (!item || !item.modelData || !item.modelData.id) continue;
                                            if (item.modelData.id === clusterWrapper.modelData.id) continue;
                                            if (posInCol.x >= item.x - 25 && posInCol.x <= item.x + item.width + 25 &&
                                                posInCol.y >= item.y - 10 && posInCol.y <= item.y + item.height + 10) {
                                                targetId = item.modelData.id;
                                                break;
                                            }
                                        }
                                        win.hoverTargetClusterId = targetId;
                                    }
                                }

                                onReleased: (mouse) => {
                                    if (hasMoved && win.draggingAddr !== "") {
                                        dragProxy.visible = false;
                                        var dropP = mapToItem(stageContainer, mouse.x, mouse.y);
                                        var targetId = win.hoverTargetClusterId;
                                        if (!targetId) {
                                            var posInCol = mapToItem(cardsColumn, mouse.x, mouse.y);
                                            for (var i = 0; i < cardsColumn.children.length; i++) {
                                                var item = cardsColumn.children[i];
                                                if (!item || !item.modelData || !item.modelData.id) continue;
                                                if (item.modelData.id === clusterWrapper.modelData.id) continue;
                                                if (posInCol.x >= item.x - 35 && posInCol.x <= item.x + item.width + 35 &&
                                                    posInCol.y >= item.y - 15 && posInCol.y <= item.y + item.height + 15) {
                                                    targetId = item.modelData.id;
                                                    break;
                                                }
                                            }
                                        }

                                        if (dropP.x > 270 || dropP.x < 0) {
                                            // Dropped out onto desktop: detach into own cluster
                                            root.assignWindowToGroup(win.draggingAddr, null);
                                        } else if (targetId && targetId !== clusterWrapper.modelData.id) {
                                            // Merged into target cluster
                                            root.assignWindowToGroup(win.draggingAddr, targetId);
                                        }
                                    } else {
                                        // ── Click Action: Shuffle (if active cluster) OR Swap Animation (if switching cluster) ──
                                        var clickedSubIdx = clusterWrapper.hoveredSubIndex >= 0 ? clusterWrapper.hoveredSubIndex : undefined;
                                        var isAlreadyActive = root.isClusterActive(clusterWrapper.modelData);

                                        if (isAlreadyActive && clusterWrapper.modelData.windows.length > 1) {
                                            // Cluster has >= 2 windows and is ALREADY active in the center:
                                            // Repeated clicks trigger the Shuffle loop!
                                            root.shuffleCluster(clusterWrapper.modelData, clickedSubIdx);
                                        } else {
                                            // Click 1 (or switching to inactive cluster):
                                            // Trigger macOS App Set Swap Transition!
                                            win.swapOverlayRef.startSwap(clusterWrapper, clickedSubIdx);
                                        }
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
                width: 68; height: 68; radius: 16
                color: Qt.rgba(0.12, 0.12, 0.16, 0.94)
                border.width: 2
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
                    width: 44; height: 44
                    sourceSize: Qt.size(64, 64)
                    source: win.draggingWinObj ? (win.draggingWinObj.iconPath || "") : ""
                    smooth: true
                    visible: source !== ""
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
                    text: win.draggingWinObj ? (win.draggingWinObj.name || win.draggingWinObj.title || "App") : ""
                    color: "white"
                    font.family: "Open Runde"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    visible: !win.draggingWinObj || !win.draggingWinObj.iconPath
                }
            }

            // ═════════════════════════════════════════════════════════════════════
            // ── macOS App Set Swap Transition Overlay ──
            // ═════════════════════════════════════════════════════════════════════
            Item {
                id: swapOverlay
                anchors.fill: parent
                visible: false
                z: 400

                property real animProgress: 0.0

                property real startSlotX: 12
                property real startSlotY: 100
                property real centerW: Math.min(win.width * 0.72, 1050)
                property real centerH: Math.min(win.height * 0.72, 660)
                property real targetCenterX: (win.width - centerW) / 2 + 50
                property real targetCenterY: (win.height - centerH) / 2
                property real thumbScale: 248 / centerW

                property var incomingClusterObj: null
                property var incomingWin: null
                property var outgoingWin: null
                property string incomingTargetAddr: ""
                property int incomingTargetWs: 1

                function lerp(a, b, t) { return a + (b - a) * t; }

                function startSwap(clusterWrapper, specificIdx) {
                    var cluster = clusterWrapper.modelData;
                    if (!cluster || !cluster.windows || cluster.windows.length === 0) return;

                    var tWin = (specificIdx !== undefined && specificIdx >= 0 && specificIdx < cluster.windows.length)
                        ? cluster.windows[specificIdx]
                        : cluster.windows[0];
                    if (!tWin) return;

                    incomingClusterObj = cluster;
                    incomingWin = tWin;
                    incomingTargetAddr = String(tWin.address || "").replace(/^0x/, "");
                    incomingTargetWs = tWin.workspace || 1;

                    // Slot position of clicked card
                    var pt = clusterWrapper.mapToItem(win, 0, 0);
                    startSlotX = pt.x;
                    startSlotY = pt.y;

                    // Find currently active outgoing window
                    var outWin = null;
                    var actAddr = root.normAddr(root.activeAddress);
                    if (actAddr !== "" && actAddr !== root.normAddr(tWin.address)) {
                        var hts = Hyprland.toplevels.values;
                        for (var i = 0; i < hts.length; i++) {
                            if (root.normAddr(hts[i].address) === actAddr) {
                                var ho = hts[i].lastIpcObject || {};
                                var hClass = hts[i].appId || ho.class || "";
                                var hDe = hClass ? DesktopEntries.heuristicLookup(hClass) : null;
                                var hIcon = (hDe && hDe.icon) ? (Quickshell.iconPath(hDe.icon, true) || "") : "";
                                outWin = {
                                    address: actAddr,
                                    title: ho.title || hts[i].title || hClass,
                                    name: hDe && hDe.name ? hDe.name : hClass,
                                    iconPath: hIcon,
                                    tl: hts[i].wayland || null,
                                    workspace: (hts[i].workspace && hts[i].workspace.id > 0) ? hts[i].workspace.id : 1
                                };
                                break;
                            }
                        }
                    }
                    outgoingWin = outWin;

                    animProgress = 0.0;
                    visible = true;
                    swapParallelAnim.restart();
                }

                // ── 300ms Parallel Animation with InOutCubic easing curve ──
                ParallelAnimation {
                    id: swapParallelAnim
                    running: false

                    NumberAnimation {
                        target: swapOverlay
                        property: "animProgress"
                        from: 0.0
                        to: 1.0
                        duration: 300
                        easing.type: Easing.InOutCubic
                    }

                    onFinished: {
                        swapOverlay.visible = false;
                        var addr = swapOverlay.incomingTargetAddr;
                        var ws = swapOverlay.incomingTargetWs;

                        // Ensure other windows in the incoming cluster don't overlap on the same workspace
                        if (swapOverlay.incomingClusterObj && swapOverlay.incomingClusterObj.windows) {
                            var clusterWins = swapOverlay.incomingClusterObj.windows;
                            for (var w = 0; w < clusterWins.length; w++) {
                                if (clusterWins[w] !== swapOverlay.incomingWin) {
                                    var otherAddr = String(clusterWins[w].address || "").replace(/^0x/, "");
                                    if (clusterWins[w].workspace === ws && otherAddr !== "") {
                                        var freeWs = root.getFreeWorkspace(ws);
                                        clusterWins[w].workspace = freeWs;
                                        Quickshell.execDetached(["hyprctl", "dispatch", "movetoworkspacesilent",
                                            String(freeWs) + ",address:0x" + otherAddr]);
                                    }
                                }
                            }
                        }

                        // Send IPC Hyprland: focuswindow address:<addr> (no cursor warp)
                        if (ws) {
                            Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(ws)]);
                        }
                        if (addr !== "") {
                            Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:0x" + addr]);
                            Quickshell.execDetached(["hyprctl", "dispatch", "bring_to_top"]);
                        }

                        if (swapOverlay.incomingWin && swapOverlay.incomingWin.tl && typeof swapOverlay.incomingWin.tl.activate === "function") {
                            try { swapOverlay.incomingWin.tl.activate(); } catch (e) {}
                        }

                        if (root.hub && root.hub.bar && typeof root.hub.bar.playSound === "function") {
                            root.hub.bar.playSound("tink", 0.35);
                        }

                        root.activeAddress = root.normAddr(addr);
                        root.updateWindows();
                    }
                }

                // ── Incoming Group View: scales 0.24 -> 1.0, rotates -30° -> 0°, slides slot -> center ──
                Item {
                    id: incomingView
                    width: swapOverlay.centerW
                    height: swapOverlay.centerH
                    visible: swapOverlay.incomingWin !== null

                    x: swapOverlay.lerp(swapOverlay.startSlotX, swapOverlay.targetCenterX, swapOverlay.animProgress)
                    y: swapOverlay.lerp(swapOverlay.startSlotY, swapOverlay.targetCenterY, swapOverlay.animProgress)
                    scale: swapOverlay.lerp(swapOverlay.thumbScale, 1.0, swapOverlay.animProgress)
                    opacity: swapOverlay.lerp(0.85, 1.0, swapOverlay.animProgress)

                    transform: [
                        Matrix4x4 {
                            matrix: Qt.matrix4x4(
                                1, 0, 0, 0,
                                0, 1, 0, 0,
                                0, 0, 1, 0,
                                0.0012 * (1.0 - swapOverlay.animProgress), 0, 0, 1
                            )
                        },
                        Rotation {
                            origin.x: 0
                            origin.y: incomingView.height / 2
                            axis { x: 0; y: 1; z: 0 }
                            angle: swapOverlay.lerp(-30, 0, swapOverlay.animProgress)
                        }
                    ]

                    // Visual frame with macOS styling
                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: Qt.rgba(0.12, 0.12, 0.16, 0.94)
                        border.width: 1.5
                        border.color: Qt.rgba(1, 1, 1, 0.45)
                        clip: true

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: "#a0000000"
                            shadowBlur: 0.7
                            shadowVerticalOffset: 12
                        }

                        // Wayland live capture if available
                        Loader {
                            anchors.fill: parent
                            active: swapOverlay.incomingWin && swapOverlay.incomingWin.tl !== null
                            sourceComponent: ScreencopyView {
                                anchors.fill: parent
                                captureSource: (swapOverlay.incomingWin && swapOverlay.incomingWin.tl) ? swapOverlay.incomingWin.tl : null
                                live: false
                                visible: hasContent
                            }
                        }

                        // Frosted fallback with app icon and title
                        Item {
                            anchors.fill: parent

                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(0.24, 0.24, 0.28, 0.92) }
                                    GradientStop { position: 1.0; color: Qt.rgba(0.13, 0.13, 0.16, 0.96) }
                                }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 14

                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 80; height: 80
                                    sourceSize: Qt.size(128, 128)
                                    source: (swapOverlay.incomingWin && swapOverlay.incomingWin.iconPath) ? swapOverlay.incomingWin.iconPath : ""
                                    smooth: true
                                    visible: source !== ""
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: (swapOverlay.incomingWin && (swapOverlay.incomingWin.name || swapOverlay.incomingWin.title)) || ""
                                    color: "white"
                                    font.family: "Open Runde"
                                    font.pixelSize: 22
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        // Top sheen
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.20) }
                                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.0) }
                            }
                        }
                    }

                    // Multi-icon row at bottom-left corner
                    Row {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 14
                        spacing: -10
                        z: 50
                        visible: swapOverlay.incomingClusterObj && swapOverlay.incomingClusterObj.windows && swapOverlay.incomingClusterObj.windows.length > 1

                        Repeater {
                            model: swapOverlay.incomingClusterObj ? swapOverlay.incomingClusterObj.windows : []

                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                z: 30 - index
                                width: 36; height: 36; radius: 10
                                color: Qt.rgba(0.12, 0.12, 0.16, 0.95)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.4)

                                Image {
                                    anchors.centerIn: parent
                                    width: 24; height: 24
                                    sourceSize: Qt.size(48, 48)
                                    source: modelData.iconPath || ""
                                    visible: source !== ""
                                }
                            }
                        }
                    }
                }

                // ── Outgoing Group View: scales 1.0 -> 0.24, rotates 0° -> -30°, slides center -> slot ──
                Item {
                    id: outgoingView
                    width: swapOverlay.centerW
                    height: swapOverlay.centerH
                    visible: swapOverlay.outgoingWin !== null

                    x: swapOverlay.lerp(swapOverlay.targetCenterX, swapOverlay.startSlotX, swapOverlay.animProgress)
                    y: swapOverlay.lerp(swapOverlay.targetCenterY, swapOverlay.startSlotY, swapOverlay.animProgress)
                    scale: swapOverlay.lerp(1.0, swapOverlay.thumbScale, swapOverlay.animProgress)
                    opacity: swapOverlay.lerp(1.0, 0.85, swapOverlay.animProgress)

                    transform: [
                        Matrix4x4 {
                            matrix: Qt.matrix4x4(
                                1, 0, 0, 0,
                                0, 1, 0, 0,
                                0, 0, 1, 0,
                                0.0012 * swapOverlay.animProgress, 0, 0, 1
                            )
                        },
                        Rotation {
                            origin.x: 0
                            origin.y: outgoingView.height / 2
                            axis { x: 0; y: 1; z: 0 }
                            angle: swapOverlay.lerp(0, -30, swapOverlay.animProgress)
                        }
                    ]

                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: Qt.rgba(0.12, 0.12, 0.16, 0.94)
                        border.width: 1.5
                        border.color: Qt.rgba(1, 1, 1, 0.35)
                        clip: true

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: "#a0000000"
                            shadowBlur: 0.6
                            shadowVerticalOffset: 10
                        }

                        Loader {
                            anchors.fill: parent
                            active: swapOverlay.outgoingWin && swapOverlay.outgoingWin.tl !== null
                            sourceComponent: ScreencopyView {
                                anchors.fill: parent
                                captureSource: (swapOverlay.outgoingWin && swapOverlay.outgoingWin.tl) ? swapOverlay.outgoingWin.tl : null
                                live: false
                                visible: hasContent
                            }
                        }

                        Item {
                            anchors.fill: parent

                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(0.24, 0.24, 0.28, 0.92) }
                                    GradientStop { position: 1.0; color: Qt.rgba(0.13, 0.13, 0.16, 0.96) }
                                }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 14

                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 80; height: 80
                                    sourceSize: Qt.size(128, 128)
                                    source: (swapOverlay.outgoingWin && swapOverlay.outgoingWin.iconPath) ? swapOverlay.outgoingWin.iconPath : ""
                                    smooth: true
                                    visible: source !== ""
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: (swapOverlay.outgoingWin && (swapOverlay.outgoingWin.name || swapOverlay.outgoingWin.title)) || ""
                                    color: "white"
                                    font.family: "Open Runde"
                                    font.pixelSize: 22
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.18) }
                                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.0) }
                            }
                        }
                    }
                }
            }

        }
    }
}
