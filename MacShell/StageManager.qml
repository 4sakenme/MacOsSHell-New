// StageManager.qml — macOS Ventura / Sonoma / Sequoia style 3D Stage Manager for Hyprland
//
// Features:
// 1. Group Stacking / Multi-window Clusters (1-3 windows per slot) with 3D stacked deck visual
// 2. Hover Fan-out: Background windows in a cluster fan out when hovered for preview peeking
// 3. Multi-icon squircle badges overlapping at bottom-left and group title labels underneath
// 4. Genuine 3D Perspective Skew & Foreshortening via Matrix4x4 + Y-Rotation
// 5. Drag & Drop grouping: drag windows between clusters to merge or separate them
// 6. Full macOS-style Swap Transition: 300ms InOutCubic rotate/scale/translate animation
// 7. Auto-shove: panel hides when active window touches left edge, re-appears on edge hover
// 8. Shuffle / loop: repeated clicks on same multi-window group cycle focus among sub-windows

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

    // ── Animation state for swap transition ──
    // ID of the cluster currently being animated in (incoming)
    property string animatingInClusterId: ""
    // ID of the cluster currently being animated out (outgoing)
    property string animatingOutClusterId: ""

    // ── Auto-shove state ──
    // true = active window is too close to left edge, panel should hide
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
        root.activeAddress = actAddr;
        root.activeWindowLeft = activeLeft;
        root.activeIpcObject = actObj;

        // ── Auto-shove: hide panel when active window touches left edge ──
        // Stage panel width is ~270px; hide when window.x < 290
        root.autoShove = (activeLeft < 290);

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

    property var clusterCycleMap: ({})

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

    // Helper to get currently active cluster (the one containing the active window)
    function getActiveCluster() {
        var actAddr = root.activeAddress;
        if (!actAddr) return null;
        for (var i = 0; i < root.clusters.length; i++) {
            var cl = root.clusters[i];
            for (var j = 0; j < cl.windows.length; j++) {
                if (cl.windows[j].address === actAddr) {
                    return cl;
                }
            }
        }
        return null;
    }

    // ── Focus a specific window via Hyprland IPC (no cursor warp) ──
    function focusWindow(targetWin) {
        if (!targetWin) return;
        var targetAddr = String(targetWin.address || "").replace(/^0x/, "");
        if (targetAddr === "") return;

        // hyprctl dispatch focuswindow address:0x<addr>  — does NOT warp cursor
        Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:0x" + targetAddr]);

        if (targetWin.tl && typeof targetWin.tl.activate === "function") {
            try { targetWin.tl.activate(); } catch (e) {}
        }

        if (root.hub && root.hub.bar && typeof root.hub.bar.playSound === "function") {
            root.hub.bar.playSound("tink", 0.35);
        }

        root.updateWindows();
    }

    // ── Cycle through apps in a grouped stage (Shuffle), or directly activate a chosen sub-app ──
    function cycleOrActivateCluster(cluster, specificWinIndex) {
        if (!cluster || !cluster.windows || cluster.windows.length === 0) return;

        var wins = cluster.windows;
        var targetWin = null;

        if (specificWinIndex !== undefined && specificWinIndex >= 0 && specificWinIndex < wins.length) {
            // User hovered and clicked directly on a specific stacked card behind
            targetWin = wins[specificWinIndex];
        } else if (wins.length === 1) {
            targetWin = wins[0];
        } else {
            // Multi-window group: shuffle / cycle windows one by one
            var actAddr = root.normAddr(root.activeAddress);
            var activeInClusterIdx = -1;
            for (var i = 0; i < wins.length; i++) {
                if (root.normAddr(wins[i].address) === actAddr) {
                    activeInClusterIdx = i;
                    break;
                }
            }

            var nextIdx = 0;
            if (activeInClusterIdx >= 0) {
                // Currently active on a window from this cluster: cycle to the next
                nextIdx = (activeInClusterIdx + 1) % wins.length;
            } else {
                var lastIdx = root.clusterCycleMap[cluster.id] || 0;
                nextIdx = lastIdx % wins.length;
            }

            root.clusterCycleMap[cluster.id] = (nextIdx + 1) % wins.length;
            targetWin = wins[nextIdx];
        }

        if (!targetWin) return;

        // Move other windows in the cluster to separate workspaces so they don't overlap
        var targetWs = targetWin.workspace || 1;
        for (var w = 0; w < wins.length; w++) {
            if (wins[w] !== targetWin) {
                var otherAddr = String(wins[w].address || "").replace(/^0x/, "");
                if (wins[w].workspace === targetWs && otherAddr !== "") {
                    var freeWs = root.getFreeWorkspace(targetWs);
                    wins[w].workspace = freeWs;
                    Quickshell.execDetached(["hyprctl", "dispatch", "movetoworkspacesilent",
                        String(freeWs) + ",address:0x" + otherAddr]);
                }
            }
        }

        root.focusWindow(targetWin);
    }

    // ── macOS-style Swap Transition (300ms, InOutCubic) ──
    // Called when user clicks a stage card. Animates the visual clusterWrapper items.
    // incomingClusterId: cluster being brought to foreground
    // outgoingClusterId: cluster currently in foreground (being sent back)
    // After animation completes, focuses the window via Hyprland IPC.
    function triggerSwapAnimation(incomingCluster, outgoingCluster, subIdx) {
        // Signal the Repeater delegates via the animating IDs.
        // The delegates watch these IDs and animate themselves accordingly.
        root.animatingInClusterId  = incomingCluster ? incomingCluster.id : "";
        root.animatingOutClusterId = outgoingCluster  ? outgoingCluster.id  : "";

        // After 300ms animation completes, focus the window and clear animation state
        swapEndTimer.pendingCluster = incomingCluster;
        swapEndTimer.pendingSubIdx  = (subIdx !== undefined) ? subIdx : -1;
        swapEndTimer.restart();
    }

    // Timer that fires when the 300ms swap animation finishes
    Timer {
        id: swapEndTimer
        interval: 310   // slightly after animation duration (300ms)
        repeat: false
        property var pendingCluster: null
        property int pendingSubIdx: -1
        onTriggered: {
            if (pendingSubIdx >= 0) {
                root.cycleOrActivateCluster(pendingCluster, pendingSubIdx);
            } else {
                root.cycleOrActivateCluster(pendingCluster, undefined);
            }
            // Clear animating IDs so delegates return to normal state
            root.animatingInClusterId  = "";
            root.animatingOutClusterId = "";
        }
    }

    // ── Click handler entry point called from MouseArea ──
    function activateCluster(cluster, subIdx) {
        var outgoing = getActiveCluster();
        triggerSwapAnimation(cluster, outgoing, subIdx);
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

            visible: root.enabled && root.clusters.length > 0

            property bool isRevealed: false
            // edgeHoverOverride: set true when user hovers the very left edge while auto-shoved
            property bool edgeHoverOverride: false
            readonly property bool stageVisible: root.forceReveal || isRevealed ||
                (root.alwaysShow && root.activeWindowLeft > 320) ||
                edgeHoverOverride
            property int hoveredCardsCount: 0

            // Drag and drop state across clusters
            property string draggingAddr: ""
            property var draggingWinObj: null
            property string hoverTargetClusterId: ""

            Timer {
                id: hideTimer
                interval: 500
                onTriggered: {
                    if (win.hoveredCardsCount === 0 && !panelHover.hovered && !win.draggingAddr) {
                        win.isRevealed = false;
                    }
                }
            }

            // Click-through mask: covers entire stage sidebar when open (330px) or edge strip (6px) when closed
            Item {
                id: inputArea
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: win.stageVisible ? 330 : 6
            }

            mask: Region {
                item: inputArea
            }

            // ── Thin invisible edge-hover zone so user can re-reveal panel after auto-shove ──
            Item {
                id: edgeHoverZone
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 6
                z: 100

                HoverHandler {
                    id: edgeHover
                    onHoveredChanged: {
                        if (hovered && root.autoShove) {
                            win.edgeHoverOverride = true;
                        } else if (!hovered) {
                            win.edgeHoverOverride = false;
                        }
                    }
                }
            }

            // ── Unified hover area across the stage panel (auto-clipped to 6px by Wayland mask when hidden) ──
            Item {
                id: panelHoverArea
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 330

                HoverHandler {
                    id: panelHover
                    onHoveredChanged: {
                        if (hovered) {
                            hideTimer.stop();
                            win.isRevealed = true;
                        } else if (!win.draggingAddr && win.hoveredCardsCount === 0) {
                            hideTimer.restart();
                        }
                    }
                }
            }

            function lerp(a, b, t) { return a + (b - a) * t; }  // kept for legacy ref

            // ── 3D Stage Cards Container ──
            Item {
                id: stageContainer
                width: 270
                height: cardsColumn.implicitHeight + 40
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -10

                // Slide in/out:
                //   - Normally: 12px from edge when visible, -300 when hidden
                //   - Auto-shove: hide to -300 unless edgeHoverOverride
                x: {
                    if (root.autoShove && !win.edgeHoverOverride) return -300;
                    return win.stageVisible ? 12 : -300;
                }
                Behavior on x { NumberAnimation { duration: 270; easing.type: Easing.OutCubic } }

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

                            // ── Swap animation state per-delegate ──
                            readonly property bool isAnimatingIn:  root.animatingInClusterId  === clusterWrapper.modelData.id
                            readonly property bool isAnimatingOut: root.animatingOutClusterId === clusterWrapper.modelData.id

                            // Extra rotation driven by swap animation (-30° → 0° for incoming, 0° → -30° for outgoing)
                            property real swapAngle: isAnimatingIn ? 0 : (isAnimatingOut ? -30 : 0)
                            Behavior on swapAngle { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }

                            // Extra scale driven by swap animation (0.2 → 1.0 for incoming, 1.0 → 0.2 for outgoing)
                            property real swapScale: isAnimatingIn ? 1.0 : (isAnimatingOut ? 0.15 : 1.0)
                            Behavior on swapScale { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }

                            // Extra X translation (slide from/to center of screen during swap)
                            // incoming: slides from 0 to +screen offset (handled by swapScale growing)
                            // We slide the card toward the screen center when incoming by translating right
                            property real swapTranslateX: isAnimatingIn ? 0 : 0
                            // No explicit translateX needed — scale + rotation from origin.x=0 provides the macOS look.

                            // ── 3D Cluster Stack Item (3D Perspective Skew + Swap rotation) ──
                            Item {
                                id: stackContainer
                                width: 248
                                height: 154

                                property real pK: clusterWrapper.isHovered ? 0.0004 : 0.0016
                                Behavior on pK { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                                // Combined 3D rotation = idle skew angle + swap animation angle
                                property real idleAngle: clusterWrapper.isHovered ? -7 : -25

                                transform: [
                                    // Perspective foreshortening matrix
                                    Matrix4x4 {
                                        matrix: Qt.matrix4x4(
                                            1, 0, 0, 0,
                                            0, 1, 0, 0,
                                            0, 0, 1, 0,
                                            stackContainer.pK, 0, 0, 1
                                        )
                                    },
                                    // Y-axis rotation: idle tilt + swap angle (swap takes precedence)
                                    Rotation {
                                        origin.x: 0
                                        origin.y: stackContainer.height / 2
                                        axis { x: 0; y: 1; z: 0 }
                                        angle: {
                                            // During swap animation, add the swap angle on top of idle angle
                                            if (clusterWrapper.isAnimatingIn || clusterWrapper.isAnimatingOut) {
                                                return clusterWrapper.swapAngle;
                                            }
                                            return stackContainer.idleAngle;
                                        }
                                        Behavior on angle { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                    },
                                    // Hover translate X
                                    Translate {
                                        x: (clusterWrapper.isHovered ? 14 : 0) + (clusterWrapper.isTargetDrop ? 10 : 0)
                                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    },
                                    // Scale: hover scale * swap scale
                                    Scale {
                                        origin.x: 0
                                        origin.y: stackContainer.height / 2
                                        xScale: {
                                            var base = (clusterWrapper.isHovered ? 1.05 : 0.96) * (clusterWrapper.isTargetDrop ? 1.06 : 1.0);
                                            if (clusterWrapper.isAnimatingIn || clusterWrapper.isAnimatingOut) {
                                                return base * clusterWrapper.swapScale;
                                            }
                                            return base;
                                        }
                                        yScale: xScale
                                        Behavior on xScale { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
                                        Behavior on yScale { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
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

                                        // Sub-app hover peek: when hovering a background app, it fans out
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

                                        // Hover detector for each background app in a group
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
                                            border.width: (clusterWrapper.isTargetDrop || deckLayer.isThisSubHovered) ? 2 : 1
                                            border.color: clusterWrapper.isTargetDrop ? "#38bdf8" : (deckLayer.isThisSubHovered ? "#38bdf8" : (clusterWrapper.isHovered ? "#60ffffff" : "#30ffffff"))
                                            Behavior on border.color { ColorAnimation { duration: 180 } }

                                            // Safe Wayland handle check
                                            readonly property var safeTl: {
                                                if (!win.stageVisible) return null;
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

                            // ── Click to Swap & Drag to Group/Ungroup ──
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
                                    if (win.hoveredCardsCount === 0 && !panelHover.hovered && !win.draggingAddr) {
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

                                        // Hit-test against cardsColumn children to find target cluster underneath cursor
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
                                        // ── Click: trigger macOS-style swap animation ──
                                        // If hovering a specific sub-card, open that app directly
                                        var clickedSubIdx = clusterWrapper.hoveredSubIndex >= 0
                                            ? clusterWrapper.hoveredSubIndex
                                            : undefined;
                                        root.activateCluster(clusterWrapper.modelData, clickedSubIdx);
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

        }
    }
}
