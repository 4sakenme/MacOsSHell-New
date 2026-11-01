// macdock v2 — a macOS-style dock for Hyprland, built on Quickshell. vSuol
//
// Part of the combined macbar + macdock shell (see shell.qml). Keep this file, MacBar.qml, shell.qml and
// liquidglass.frag together in ~/.config/quickshell/macbar/ and run:  qs -c macbar
// Pins are saved to ~/.config/macdock/pinned.json once you use "Keep in Dock".
//
// Settings are saved to ~/.config/macdock/settings.json (right-click the dock → Dock Preferences…).
// The settings window is frameless and always opens floating + centred: the shell registers the Hyprland window rule for it
// itself (registerSettingsRule below), so nothing has to be added to the Hyprland config.
//
// Dock style (Dock Preferences → Appearance):
//   Normal Blur         – the original translucent tint; blur comes from the Hyprland layer rule below.
//   Apple Liquid Glass  – real-time refraction shader (liquidglass.frag, next to this file). It is compiled
//                         with `qsb` (package qt6-shadertools) on first use and cached in ~/.config/macdock/.
//                         The backdrop it refracts is the wallpaper + the live windows behind the Dock;
//                         set "wallpaperPath" in settings.json if the wallpaper isn't auto-detected.
//
// Hyprland (Lua) layer rule for the glass:
//   hl.layer_rule({ name = "macdock", match = { namespace = "macdock" },
//                   blur = true, ignore_alpha = 0.2, no_anim = true })

import QtQuick
import QtQuick.Effects
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import "I18n.js" as I18n
import "modules"
import "Fonts.js" as Fonts

Scope {
    id: root

    // shared helpers from shell.qml (window geometry poller, wallpaper lookup)
    property var hub: null
    property bool dockEnabled: true      // false = no Dock at all (settings window stays available)
    property bool settingsEnabled: true  // false = keep the System Settings window closed
    property bool desktopIcons: true     // show files, folders and .desktop shortcuts from the XDG Desktop directory
    property int desktopIconSize: 48     // Desktop icon size in logical pixels
    property var bar: hub ? hub.bar : null
    Connections {
        target: root.bar
        function onDarkModeChanged() {
            if (root.darkMode !== root.bar.darkMode) root.darkMode = root.bar.darkMode;
        }
        function onAppearanceModeChanged() {
            if (root.appearanceMode !== root.bar.appearanceMode) root.appearanceMode = root.bar.appearanceMode;
        }
    }
    property string userName: Quickshell.env("USER") || ""

    // ═════ Displays: main display + resolution / refresh, with a macOS-style "keep or revert" safety net ═════
    property var displays: ({ primary: "", modes: {} })      // saved in ~/.config/macshell/displays.json
    property var monList: []                                  // hyprctl monitors (live)
    property string pendingOut: ""                            // a mode change waiting for "Keep"
    property string pendingPrev: ""
    property int revertLeft: 0
    FileView {
        id: dispFile
        path: Quickshell.env("HOME") + "/.config/macshell/displays.json"
        printErrors: false
        onLoaded: { try { root.displays = JSON.parse(text()); } catch (e) {} root.applySavedModes(); }
    }
    function saveDisplays() { dispFile.setText(JSON.stringify(root.displays, null, 2)); }
    function refreshMons() { if (!monListProc.running) monListProc.running = true; }
    Process {
        id: monListProc
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector { onStreamFinished: { try { root.monList = JSON.parse(text); } catch (e) {} } }
    }
    function modeOf(m) { return m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2); }
    function applyMode(out, mode) {
        var m = null;
        for (var i = 0; i < monList.length; i++) if (monList[i].name === out) m = monList[i];
        var pos = m ? (m.x + "x" + m.y) : "auto", sc = m ? m.scale : 1;
        Quickshell.execDetached(["hyprctl", "eval", "hl.monitor({ output = \"" + out + "\", mode = \"" + mode + "\", position = \"" + pos + "\", scale = " + sc + " })"]);
        monRefreshSoon.restart();
    }
    Timer { id: monRefreshSoon; interval: 700; onTriggered: root.refreshMons() }
    // change a monitor's mode; it reverts by itself after 15 s unless kept
    function tryMode(out, mode) {
        var m = null;
        for (var i = 0; i < monList.length; i++) if (monList[i].name === out) m = monList[i];
        if (!m) return;
        if (pendingOut === "") pendingPrev = modeOf(m);
        pendingOut = out;
        applyMode(out, mode);
        pendingMode = mode;
        revertLeft = 15;
        revertTimer.restart();
    }
    property string pendingMode: ""
    Timer {
        id: revertTimer; interval: 1000; repeat: true
        onTriggered: { root.revertLeft--; if (root.revertLeft <= 0) root.revertMode(); }
    }
    function keepMode() {
        revertTimer.stop();
        var d = displays, mm = {}; for (var k in d.modes) mm[k] = d.modes[k];
        mm[pendingOut] = pendingMode;
        displays = { primary: d.primary || "", modes: mm };
        saveDisplays();
        pendingOut = ""; pendingMode = "";
    }
    function revertMode() {
        revertTimer.stop();
        if (pendingOut !== "" && pendingPrev !== "") applyMode(pendingOut, pendingPrev);
        pendingOut = ""; pendingMode = "";
    }
    function applySavedModes() {
        var mm = displays.modes || {};
        for (var k in mm) Quickshell.execDetached(["hyprctl", "eval", "hl.monitor({ output = \"" + k + "\", mode = \"" + mm[k] + "\", position = \"auto\", scale = 1 })"]);
        if (displays.primary) root.monitorPrimary = displays.primary;
        refreshMons();
    }
    property string monitorPrimary: ""
    function setPrimary(name) {
        var d = displays;
        displays = { primary: name, modes: d.modes || {} };
        saveDisplays();
        monitorPrimary = name;
        root.monitor = name;                                         // the Dock lives on the main display
    }
    Process {
        running: true
        command: ["sh", "-c", "n=$(getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1); printf '%s' \"${n:-$USER}\""]
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "") root.userName = text.trim() }
    }
    readonly property bool captureCut: hub ? hub.captureCut : false
    readonly property bool glassHold: hub ? hub.glassHold : false          // windows opening / closing: the glass's live captures pause, source stays attached
    readonly property bool previewHold: hub ? hub.previewHold : false
    readonly property bool captureHold: hub ? hub.captureHold : false     // windows opening / closing: the dock PREVIEW capture stops (source released 0.5 s later); the glass is not affected
    // appearance values shared by Dock and Menu Bar
    function setLook(k, v) { root[k] = v; if (bar) bar[k] = v; }
    // Appearance: the Menu Bar resolves "auto" (light by day, dark by night) and keeps both windows in step
    function setAppearance(mode) {
        if (["light", "dark", "auto"].indexOf(mode) < 0) return;
        appearanceMode = mode;
        if (mode === "auto") {
            var h = new Date().getHours();
            darkMode = bar && bar.autoIsDark ? bar.autoIsDark() : (h < 7 || h >= 19);
        } else darkMode = mode === "dark";
        // Update this window first so its palette reacts immediately, then keep the Menu Bar in sync.
        if (bar && bar.setAppearance) {
            bar.setAppearance(mode);
            appearanceMode = mode;
            darkMode = bar.darkMode;
        }
    }

    // ───────────── CONFIG ───────────── Lachowski
    property string monitor: ""          // "" = every monitor, or e.g. "DP-1"
    property int iconSize: 52
    property real magnification: 1.7     // peak icon scale
    property int spacing: 6
    property int hPad: 10
    property int topPad: 8
    property int bottomPad: 9            // room under icons (running dots live here)
    property int cornerRadius: 18
    readonly property real uiS: bar ? bar.uiScale : 1      // UI scale (Settings → Menu Bar): Settings / About windows follow it
    property int margin: 6
    property bool darkMode: true
    // the dock keeps one fixed look (dark): switching the system between Light and Dark does not change its colours
    readonly property bool dockDark: true
    property string appearanceMode: "dark"      // light | dark | auto (kept in step with the Menu Bar, see setAppearance)
    property string dockStyle: "blur"   // "blur" = Normal Blur, "liquid" = Apple Liquid Glass
    // new windows open floating (macOS-like) instead of tiling; written to a Lua file the session config reads
    property bool windowsFloat: true
    onWindowsFloatChanged: if (settingsReady) applyWindowsFloat()
    function applyWindowsFloat() {
        var rule = windowsFloat ? "hl.window_rule({ match = { class = \".*\" }, float = true })\n" : "";
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.config/macshell\"; printf '%s' \"$1\" > \"$HOME/.config/macshell/windows.lua\"; "
            + "if [ -n \"$1\" ]; then hyprctl eval \"$1\" >/dev/null 2>&1; else hyprctl reload >/dev/null 2>&1; fi", "sh", rule]);
    }
    // Liquid Glass tuning (settings.json): rim = edge highlight, grain = noise, liquid = refraction depth
    property real glassRim: 0.45
    property real glassGrain: 0.03
    property real glassLiquid: 1.0
    // The Dock's own real-time switch (Dock Preferences -> Appearance). It used to follow the Menu Bar's "Real-time glass" toggle, which is OFF by
    // default, so the Dock glass was a 15 fps, pause-while-windows-open snapshot unless that was found and switched on.
    property bool glassLive: true
    readonly property bool glassRT: glassLive
    property real glassBlur: 5            // Liquid Glass backdrop blur radius, px (settings slider)
    readonly property real dockBlurBoost: 8    // extra px of blur added on top of glassBlur for the Dock glass only
    property bool glassDebug: false       // settings.json only: draw the raw Liquid Glass backdrop texture
    property string wallpaperPath: ""    // optional override for the wallpaper the Liquid Glass refracts
    property real glassOpacity: 0.42     // 0 = fully clear; below the layerrule's ignore_alpha (0.2) the blur turns off
    // "smart"  = hide while a non-floating window is open on that monitor's workspace
    // "always" = always auto-hide, "never" = always visible and reserves space
    property string hideMode: "smart"
    property bool showTrash: true
    property string fontFamily: "Open Runde"  // bundled in assets/fonts (shell.qml loads it); falls back to the system font if missing
    readonly property string boldFontFamily: hub && hub.boldFontFamily ? hub.boldFontFamily : "Open Runde Semibold"
    // Open Runde: bold text uses its Semibold face; another selected font keeps its own family (and real bold weight)
    function fontForWeight(weight, regularFamily) { return (Number(weight) >= Font.DemiBold && regularFamily === "Open Runde") ? boldFontFamily : regularFamily; }
    onFontFamilyChanged: if (fontFamily.indexOf("Inter") === 0) fontFamily = "Open Runde"
    property bool magnificationEnabled: true
    property bool showLabels: true       // hover tooltips
    property bool showIndicators: true   // dots under running apps
    property bool bounceOnLaunch: true
    property bool showThumbs: true       // open windows get a live preview cell next to the Trash
    property bool windowCapture: true    // live window capture for those previews (off: the cells show the app icon, nothing is captured). Liquid Glass is not affected
    property string minimizeAnimation: "genie" // "genie", "scale", "none"
    property int hideDelay: 450          // ms before the dock hides after the pointer leaves
    readonly property var accentChoices: [
        { name: "Blue",     c: "#0a84ff" }, { name: "Purple", c: "#bf5af2" },
        { name: "Pink",     c: "#ff375f" }, { name: "Red",    c: "#ff453a" },
        { name: "Orange",   c: "#ff9f0a" }, { name: "Yellow", c: "#ffd60a" },
        { name: "Green",    c: "#30d158" }, { name: "Graphite", c: "#8e8e93" }
    ]
    property color accent: "#0A84FF"     // menu highlight (macOS blue)
    // Dock icon tint: every icon is re-coloured with one colour (works with any icon pack)
    property bool iconTint: false
    property string iconTintColor: "#0a84ff"
    property real iconTintStrength: 1.0
    readonly property var tintChoices: [
        { name: "Blue",     c: "#0a84ff" }, { name: "Purple", c: "#bf5af2" }, { name: "Pink",  c: "#ff375f" },
        { name: "Red",      c: "#ff453a" }, { name: "Orange", c: "#ff9f0a" }, { name: "Yellow", c: "#ffd60a" },
        { name: "Green",    c: "#30d158" }, { name: "Teal",   c: "#40c8e0" }, { name: "Graphite", c: "#8e8e93" },
        { name: "White",    c: "#ffffff" }, { name: "Black",  c: "#1c1c1e" }
    ]
    readonly property var defaultPinned: [
        "org.gnome.Nautilus", "org.kde.dolphin", "thunar",
        "firefox", "zen", "chromium", "google-chrome",
        "kitty", "com.mitchellh.ghostty", "Alacritty", "foot",
        "code", "discord", "spotify", "steam", "obsidian"
    ]   // used until you change pins from the dock; unknown ids are skipped
    property var pinned: defaultPinned
    // ──────────────────────────────────

    // ═════════════════════════════════════════════════════════════════
    //  SETTINGS UI  —  macOS "System Settings" look
    //  (inline components; they receive the palette through `t`)
    // ═════════════════════════════════════════════════════════════════

    // Rounded, inset group box (the white/grey "card" in System Settings)
    component SCard: Rectangle {
        id: card
        required property var t
        default property alias content: col.data
        width: parent ? parent.width : 0
        height: col.implicitHeight
        radius: 22
        color: t.card
        border.width: 1
        border.color: t.cardBorder
        Column { id: col; width: parent.width }
    }

    // One row inside a card: title (+ subtitle) on the left, control on the right
    component SRow: Item {
        id: r
        required property var t
        property string title: ""
        property string subtitle: ""
        property url iconSource: ""
        default property alias control: slot.data
        width: parent ? parent.width : 0
        height: Math.max(44, textCol.height + 22, slot.height + 20)

        Rectangle {
            visible: r.y > 0.5
            x: 14
            width: parent.width - 14
            height: 1
            color: r.t.sep
        }
        Image {
            id: ic
            visible: r.iconSource != ""
            source: r.iconSource
            x: 14
            width: 28; height: 28
            anchors.verticalCenter: parent.verticalCenter
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
        Column {
            id: textCol
            x: ic.visible ? 54 : 14
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, r.width - x - slot.width - 28)
            spacing: 2
            Text {
                width: parent.width
                text: r.title
                elide: Text.ElideRight
                color: r.t.text
                font.family: root.fontForWeight(Font.Normal, r.t.fam)
                font.pixelSize: 13
            }
            Text {
                visible: r.subtitle !== ""
                width: parent.width
                text: r.subtitle
                wrapMode: Text.WordWrap
                color: r.t.text2
                font.family: root.fontForWeight(Font.Normal, r.t.fam)
                font.pixelSize: 12
            }
        }
        Item {
            id: slot
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    // Section header / footnote text
    component SLabel: Text {
        required property var t
        property bool header: false
        width: parent ? parent.width : 0
        leftPadding: 4
        topPadding: header ? 8 : 0
        wrapMode: Text.WordWrap
        color: t.text2
        font.family: root.fontForWeight((header ? Font.DemiBold : Font.Normal), t.fam)
        font.pixelSize: header ? 12 : 12
        font.weight: header ? Font.DemiBold : Font.Normal
    }

    // macOS toggle switch: capsule knob, draggable, fluid slide, the knob turns into Liquid Glass while held (see GlassSwitch.qml)
    component SSwitch: GlassSwitch {
        required property var t
        accentColor: "#30D158"
        offColor: t.switchOff
        knobColor: t.dark ? "#DCDDDA" : "white"
        dark: t.dark
        baseColor: t.dark ? "#2B2B2D" : "#FFFFFF"
        glass: root.settingsGlass
        shaderUrl: root.glassShaderUrl
        glassLiquid: root.glassLiquid
        glassRim: root.glassRim
        glassGrain: root.glassGrain
        glassTint: root.glassOpacity
        borderTint: root.bar ? root.bar.menuBorderColor : "#8A9AB5"
        onGlassFailed: root.glassState = "failed"
    }

    // slider: identical to the Control Center sliders (thin bar, knob on hover, Liquid Glass knob while held; see GlassSlider.qml)
    component SSlider: GlassSlider {
        required property var t
        fg: t.text
        fillColor: t.accent
        knobColor: "white"
        knobSize: 1.2
        pressGrow: 0.8
        trackColor: t.track
        labelColor: t.text2
        fontFamily: t.fam
        dark: t.dark
        baseColor: t.dark ? "#2B2B2D" : "#FFFFFF"
        glass: root.settingsGlass
        shaderUrl: root.glassShaderUrl
        glassLiquid: root.glassLiquid
        glassRim: root.glassRim
        glassGrain: root.glassGrain
        glassTint: root.glassOpacity
        borderTint: root.bar ? root.bar.menuBorderColor : "#8A9AB5"
        onGlassFailed: root.glassState = "failed"

        // "Reset to default": every settings slider can name its default (resetValue, in the slider's own from..to units).
        // The link shows under the track only while the value differs from it; clicking it sends the default through moved().
        property var resetValue: undefined
        readonly property bool canReset: resetValue !== undefined && Math.abs(value - Number(resetValue)) > Math.max(1e-6, Math.abs(to - from) * 0.004)
        height: (leftLabel !== "" || rightLabel !== "" || resetValue !== undefined) ? 40 : 22
        Text {
            id: resetLink
            visible: parent.resetValue !== undefined
            opacity: parent.canReset ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            x: (parent.width - width) / 2
            y: 25
            text: I18n.tr("Reset to default")
            color: parent.t.accent
            font.family: parent.t.fam
            font.pixelSize: 11
            MouseArea {
                anchors.fill: parent; anchors.margins: -5
                enabled: parent.parent.canReset
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.parent.moved(Number(parent.parent.resetValue))
            }
        }
    }

    // macOS segmented control: capsule track, dividers between the options, and a marker that turns into Liquid Glass while it
    // slides to the chosen option (see GlassSegmented.qml)
    component SSegmented: GlassSegmented {
        required property var t
        segWidth: 72
        dark: t.dark
        textColor: t.text
        fontFamily: t.fam
        fontSize: 12
        trackColor: t.ctrl
        pillColor: t.ctrlSel
        baseColor: t.dark ? "#2B2B2D" : "#FFFFFF"
        glass: root.settingsGlass
        shaderUrl: root.glassShaderUrl
        glassLiquid: root.glassLiquid
        glassRim: root.glassRim
        glassGrain: root.glassGrain
        glassTint: root.glassOpacity
        borderTint: root.bar ? root.bar.menuBorderColor : "#8A9AB5"
        onGlassFailed: root.glassState = "failed"
    }

    // macOS push button
    component SButton: Rectangle {
        id: b
        required property var t
        property string text: ""
        property bool destructive: false
        signal clicked()
        width: lbl.implicitWidth + 26
        height: 24
        radius: 10
        color: ma.pressed ? t.buttonPressed : t.button
        border.width: 1
        border.color: t.buttonBorder
        Text {
            id: lbl
            anchors.centerIn: parent
            text: b.text
            color: b.destructive ? b.t.danger : b.t.text
            font.family: root.fontForWeight(Font.Normal, b.t.fam)
            font.pixelSize: 13
        }
        MouseArea { id: ma; anchors.fill: parent; onClicked: b.clicked() }
    }

    // Light / Dark appearance thumbnail
    component SThemeTile: Item {
        id: tile
        required property var t
        property bool dark: false
        property bool split: false            // Auto: left half light, right half dark
        property bool selected: false
        property string label: ""
        signal clicked()
        width: 84; height: 78
        readonly property bool leftDark: split ? false : dark
        // the little desktop picture (left half, or the whole tile)
        Item {
            width: 84; height: 56
            Rectangle { width: 84; height: 56; radius: 8; color: tile.leftDark ? "#141416" : "#D9DDE6" }
            Rectangle {   // mini window
                x: 14; y: 9
                width: 56; height: 32
                radius: 4
                color: tile.leftDark ? "#2C2C2E" : "#FFFFFF"
                Rectangle { x: 0; y: 0; width: 15; height: parent.height; radius: 4; color: tile.leftDark ? "#3A3A3C" : "#E9E9EE" }
                Rectangle { x: 20; y: 7;  width: 28; height: 3; radius: 1.5; color: tile.leftDark ? "#5A5A5E" : "#C8C8CE" }
                Rectangle { x: 20; y: 14; width: 20; height: 3; radius: 1.5; color: tile.leftDark ? "#48484A" : "#DADADF" }
                Rectangle { x: 20; y: 21; width: 24; height: 3; radius: 1.5; color: tile.leftDark ? "#48484A" : "#DADADF" }
            }
            Rectangle {   // mini dock
                x: 26; y: 46
                width: 32; height: 6
                radius: 3
                color: tile.leftDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.75)
            }
        }
        // Auto: the right half is the dark picture
        Item {
            visible: tile.split
            x: 42; width: 42; height: 56
            clip: true
            Item {
                x: -42; width: 84; height: 56
                Rectangle { width: 84; height: 56; radius: 8; color: true ? "#141416" : "#D9DDE6" }
                Rectangle {   // mini window
                    x: 14; y: 9
                    width: 56; height: 32
                    radius: 4
                    color: true ? "#2C2C2E" : "#FFFFFF"
                    Rectangle { x: 0; y: 0; width: 15; height: parent.height; radius: 4; color: true ? "#3A3A3C" : "#E9E9EE" }
                    Rectangle { x: 20; y: 7;  width: 28; height: 3; radius: 1.5; color: true ? "#5A5A5E" : "#C8C8CE" }
                    Rectangle { x: 20; y: 14; width: 20; height: 3; radius: 1.5; color: true ? "#48484A" : "#DADADF" }
                    Rectangle { x: 20; y: 21; width: 24; height: 3; radius: 1.5; color: true ? "#48484A" : "#DADADF" }
                }
                Rectangle {   // mini dock
                    x: 26; y: 46
                    width: 32; height: 6
                    radius: 3
                    color: true ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.75)
                }
            }
        }
        Rectangle {   // selection / outline ring
            width: 84; height: 56
            radius: 8
            color: "transparent"
            border.width: tile.selected ? 3 : 1
            border.color: tile.selected ? tile.t.accent : tile.t.sep
        }
        Text {
            y: 60
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr(tile.label)
            color: tile.t.text
            font.family: root.fontForWeight(Font.Normal, tile.t.fam)
            font.pixelSize: 12
        }
        MouseArea { anchors.fill: parent; onClicked: tile.clicked() }
    }

    // Colored rounded-square sidebar icon with a tiny drawn glyph
    component SGlyph: Rectangle {
        id: gl
        property string kind: ""
        property string fam: "Open Runde"   // the selected UI font (set by the sidebar)
        property string wg: ""          // a menu-bar glyph (WGlyph.qml) instead of the hand-drawn kinds below
        property color c1: "#4FA8FF"
        property color c2: "#0A6CFF"
        width: 24; height: 24; radius: 6
        gradient: Gradient {
            GradientStop { position: 0.0; color: gl.c1 }
            GradientStop { position: 1.0; color: gl.c2 }
        }
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.14)

        WGlyph { visible: gl.wg !== ""; anchors.centerIn: parent; width: 16; height: 16; kind: gl.wg; color: "white" }
        Item {
            anchors.centerIn: parent
            width: 16; height: 16
            visible: gl.wg === ""

            // dock
            Item {
                visible: gl.kind === "dock"; anchors.fill: parent
                Rectangle { x: 1; y: 11; width: 14; height: 4; radius: 2; color: "white" }
                Rectangle { x: 2;    y: 4.5; width: 3.4; height: 3.4; radius: 1; color: "white" }
                Rectangle { x: 6.3;  y: 4.5; width: 3.4; height: 3.4; radius: 1; color: "white" }
                Rectangle { x: 10.6; y: 4.5; width: 3.4; height: 3.4; radius: 1; color: "white" }
            }
            // appearance (half-filled circle)
            Item {
                visible: gl.kind === "appearance"; anchors.fill: parent
                Rectangle {
                    x: 1.5; y: 1.5; width: 13; height: 13; radius: 6.5
                    color: "transparent"; border.width: 2; border.color: "white"
                }
                Item {
                    x: 8; y: 1.5; width: 6.5; height: 13; clip: true
                    Rectangle { x: -6.5; width: 13; height: 13; radius: 6.5; color: "white" }
                }
            }
            // siri (apple intelligence glowing orb)
            Item {
                visible: gl.kind === "siri"; anchors.fill: parent
                Rectangle {
                    anchors.centerIn: parent
                    width: 12; height: 12; radius: 6
                    color: "white"
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 6; height: 6; radius: 3
                    color: gl.c2
                }
            }
            // behavior (two toggles)
            Item {
                visible: gl.kind === "behavior"; anchors.fill: parent
                Rectangle { x: 1; y: 2; width: 14; height: 5.5; radius: 2.75; color: "white" }
                Rectangle { x: 10.2; y: 3.2; width: 3.1; height: 3.1; radius: 1.55; color: gl.c2 }
                Rectangle {
                    x: 1; y: 9.5; width: 14; height: 5.5; radius: 2.75
                    color: "transparent"; border.width: 1; border.color: "white"
                }
                Rectangle { x: 2.7; y: 10.7; width: 3.1; height: 3.1; radius: 1.55; color: "white" }
            }
            // widgets (three tiles and an empty slot)
            Item {
                visible: gl.kind === "widgets"; anchors.fill: parent
                Rectangle { x: 1.5; y: 1.5; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Rectangle { x: 8.9; y: 1.5; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Rectangle { x: 1.5; y: 8.9; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Rectangle { x: 8.9; y: 8.9; width: 5.6; height: 5.6; radius: 1.6; color: "transparent"; border.width: 1.2; border.color: "white" }
            }
            // applications (2×2 grid)
            Item {
                visible: gl.kind === "apps"; anchors.fill: parent
                Rectangle { x: 1.5; y: 1.5; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Rectangle { x: 8.9; y: 1.5; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Rectangle { x: 1.5; y: 8.9; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Rectangle { x: 8.9; y: 8.9; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
            }
            // menu bar
            Item {
                visible: gl.kind === "menubar"; anchors.fill: parent
                Rectangle { x: 1; y: 2; width: 14; height: 4.5; radius: 1.5; color: "white" }
                Rectangle { x: 2.5; y: 3.4; width: 4; height: 1.6; radius: 0.8; color: gl.c2 }
                Rectangle {
                    x: 1; y: 8.5; width: 14; height: 6.5; radius: 2
                    color: "transparent"; border.width: 1; border.color: "white"
                }
            }
            // wallpaper (picture with a sun and hills)
            Item {
                visible: gl.kind === "wallpaper"; anchors.fill: parent
                Rectangle {
                    x: 1; y: 2.5; width: 14; height: 11; radius: 2
                    color: "transparent"; border.width: 1.5; border.color: "white"
                }
                Rectangle { x: 9.5; y: 4.6; width: 2.8; height: 2.8; radius: 1.4; color: "white" }
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var c = getContext("2d"); c.reset(); c.fillStyle = "white";
                        c.beginPath(); c.moveTo(2.5, 12.5); c.lineTo(6.2, 7.6); c.lineTo(9.2, 11); c.lineTo(10.8, 9.4); c.lineTo(13.5, 12.5); c.closePath(); c.fill();
                    }
                }
            }
            // about
            Item {
                visible: gl.kind === "about"; anchors.fill: parent
                Rectangle {
                    x: 1; y: 1; width: 14; height: 14; radius: 7
                    color: "transparent"; border.width: 2; border.color: "white"
                }
                Text {
                    anchors.centerIn: parent
                    text: "i"
                    color: "white"
                    font.family: Fonts.forWeight(Font.Bold, gl.fam); font.pixelSize: 10
                    font.bold: true
                }
            }
        }
    }

    // ─────────────────────────── THE WINDOW ───────────────────────────
    Window {
        id: prefsWindow
        title: "macshell Settings"
        // NOT bindings: a bound size gets re-applied by Qt and snaps the window back while it is being resized by hand.
        // The size is set once when the window opens and again only when the UI scale itself changes (see below).
        width: 800
        height: 880
        minimumWidth: 400
        minimumHeight: 300
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint

        // where this window sits on its monitor, for the glass sidebar's backdrop
        QtObject {
            id: prefsGlassGeo
            readonly property var g: {
                var cs = root.glassClients || [], ms = root.hub ? (root.hub.monData || []) : [];
                for (var i = 0; i < cs.length; i++) {
                    var c = cs[i];
                    if (c.title !== prefsWindow.title || !c.mapped) continue;
                    for (var j = 0; j < ms.length; j++) {
                        var mm = ms[j];
                        if (mm.id !== c.monitor) continue;
                        var sc = mm.scale || 1;
                        return { x: c.at[0] - mm.x, y: c.at[1] - mm.y, mw: mm.width / sc, mh: mm.height / sc, mon: mm.name };
                    }
                }
                return null;
            }
            readonly property bool ok: g !== null
            // the window content is drawn scaled by the UI scale, so these are expressed in that scaled coordinate space
            readonly property real x: ok ? g.x / root.uiS : 0
            readonly property real y: ok ? g.y / root.uiS : 0
            readonly property real mw: ok ? g.mw / root.uiS : 1
            readonly property real mh: ok ? g.mh / root.uiS : 1
            readonly property string mon: ok ? g.mon : ""
        }

        // ── navigation state ──
        property int cur: 0
        property var backStack: []
        property var fwdStack: []
        property string query: ""

        // grouped like macOS System Settings (sec = sidebar section; a gap is drawn between sections)
        readonly property var panes: [
            // 1 · Connectivity
            { id: "wifi",       sec: 1, name: "Wi-Fi",           wg: "wifi",       c1: "#3D9BFF", c2: "#0A6CFF", keys: "wireless network internet ssid join" },
            { id: "bluetooth",  sec: 1, name: "Bluetooth",       wg: "bluetooth",  c1: "#3D9BFF", c2: "#0A6CFF", keys: "devices pair headphones mouse keyboard" },
            { id: "network",    sec: 1, name: "Network",         wg: "ethernet",   c1: "#3D9BFF", c2: "#0A6CFF", keys: "ethernet ip address vpn tailscale connection" },
            // 2 · System
            { id: "general",    sec: 2, name: "General",         glyph: "behavior", c1: "#8E8E93", c2: "#636366", keys: "language shell enable disable dock menu bar panel show hide off on" },
            { id: "appearance", sec: 2, name: "Appearance",      glyph: "appearance", c1: "#3A3A3C", c2: "#1C1C1E", keys: "theme dark light auto mode accent color glass liquid apple style blur font spotlight top bar menus" },
            { id: "siri",       sec: 2, name: "Apple Intelligence & Siri", glyph: "siri", c1: "#00F0FF", c2: "#FF2D55", keys: "siri voice assistant ai gemini intelligence wake word edge glow type to siri" },
            { id: "wallpaper",  sec: 2, name: "Wallpaper",       glyph: "wallpaper", c1: "#5AC8FA", c2: "#007AFF", keys: "wallpaper background picture image video animated live motion desktop dynamic" },
            { id: "displays",   sec: 2, name: "Displays",        wg: "sun",        c1: "#3D9BFF", c2: "#0A6CFF", keys: "brightness night shift monitor resolution refresh scale" },
            { id: "battery",    sec: 2, name: "Battery",         wg: "bolt",       c1: "#4CD964", c2: "#28A745", keys: "power energy charge profile performance game mode gaming fullscreen" },
            // 3 · Desktop
            { id: "dock",       sec: 3, name: "Desktop & Dock",  glyph: "dock",     c1: "#2C2C2E", c2: "#1C1C1E", keys: "size icon magnification zoom spacing margin distance corner radius round square edge hide auto labels indicators bounce trash monitor preview app switcher alt tab" },
            { id: "menubar",    sec: 3, name: "Menu Bar",        glyph: "menubar",  c1: "#3D9BFF", c2: "#0A6CFF", keys: "panel bar height clock date seconds 24 hour battery tray search spotlight week monday style liquid bluetooth screenshots" },
            { id: "controlcenter", sec: 3, name: "Control Center", wg: "cc",       c1: "#8E8E93", c2: "#636366", keys: "modules tiles controls" },
            { id: "widgets",    sec: 3, name: "Widgets",         glyph: "widgets",  c1: "#FF9F0A", c2: "#FF7A00", keys: "desktop widgets weather clock calendar player image photo add remove arrange edit size temperature fahrenheit celsius city location" },
            // 4 · Notifications & Sound
            { id: "notifications", sec: 4, name: "Notifications", wg: "bell",      c1: "#FF5E57", c2: "#E8342A", keys: "alerts banners popups do not disturb screenshot" },
            { id: "sound",      sec: 4, name: "Sound",           wg: "speaker",    c1: "#FF5E7E", c2: "#E8344F", keys: "volume output input microphone speakers headphones effects ui sounds" },
            { id: "focus",      sec: 4, name: "Focus",           wg: "moon",       c1: "#7D7AFF", c2: "#5856D6", keys: "do not disturb keep awake sleep" },
            // 5 · Security & Accounts
            { id: "lockscreen", sec: 5, name: "Lock Screen",     wg: "lock",       c1: "#3A3A3C", c2: "#1C1C1E", keys: "lock password album lyrics media clock" },
            { id: "users",      sec: 5, name: "Users & Groups",  wg: "smile",      c1: "#3D9BFF", c2: "#0A6CFF", keys: "account user name picture avatar" },
            // 6 · Input
            { id: "keyboard",   sec: 6, name: "Keyboard",        wg: "keyboard",   c1: "#A7A7AD", c2: "#7C7C82", keys: "repeat rate delay layout typing" },
            { id: "mouse",      sec: 6, name: "Mouse",           wg: "mouse",      c1: "#A7A7AD", c2: "#7C7C82", keys: "tracking speed scroll natural" },
            { id: "trackpad",   sec: 6, name: "Trackpad",        wg: "trackpad",   c1: "#A7A7AD", c2: "#7C7C82", keys: "tap click natural scroll touchpad gestures" },
            // 7 · Apps & About
            { id: "apps",       sec: 7, name: "Applications",    glyph: "apps",     c1: "#FFB340", c2: "#FF9500", keys: "pinned apps keep remove reset dock" },
            { id: "about",      sec: 7, name: "About",           glyph: "about",    c1: "#A7A7AD", c2: "#7C7C82", keys: "version reset config folder macdock macbar macshell" }
        ]

        readonly property var filtered: {
            var q = query.trim().toLowerCase();
            var out = [];
            for (var i = 0; i < panes.length; i++) {
                var hay = (panes[i].name + " " + panes[i].keys).toLowerCase();
                if (q === "" || hay.indexOf(q) >= 0) out.push(i);
            }
            return out;
        }

        function go(i) {
            if (i === cur) return;
            backStack = backStack.concat([cur]);
            fwdStack = [];
            cur = i;
        }
        function back() {
            if (backStack.length === 0) return;
            var b = backStack.slice();
            var p = b.pop();
            fwdStack = fwdStack.concat([cur]);
            backStack = b;
            cur = p;
        }
        function forward() {
            if (fwdStack.length === 0) return;
            var f = fwdStack.slice();
            var p = f.pop();
            backStack = backStack.concat([cur]);
            fwdStack = f;
            cur = p;
        }
        onCurChanged: flick.contentY = 0

        Shortcut { sequences: ["Escape", "Ctrl+W"]; onActivated: prefsWindow.visible = false }

        // Settings always opens as a floating, centred window: the shell registers its own window rule (root.registerSettingsRule),
        // so no windowrule is needed in the Hyprland config. The dispatches below are only the fallback / re-apply.
        onVisibleChanged: if (visible) { root.registerSettingsRule(false); if (root.bar) { root.bar.updateDialogOpen = root.bar.updateState === "available"; root.bar.checkForUpdates(true); } showNormal(); applyScaledSize(); floatTries = 0; floatTimer.restart(); if (root.glassState === "idle") root.startGlass(); }
        property int floatTries: 0
        readonly property int preferredWidth: Math.round(800 * root.uiS)
        readonly property int preferredHeight: Math.round(880 * root.uiS)
        // the UI scale changed while the window is open: Hyprland keeps the old floating size (and its blur / shadow region), so
        // tell it the new size again
        // ── resize that only applies when you let go ──
        // The edge handles no longer start the compositor's live resize: they remember where the drag began, and when the button is
        // released the window is resized once, to the size the drag ended at (left / top edges also move the window so the opposite
        // edge stays put).
        property var rs: null
        function rsBegin(edges, p) { rs = { e: edges, x: p.x, y: p.y, w: width, h: height }; }
        function rsEnd(p) {
            if (!rs) return;
            var e = rs.e, dx = p.x - rs.x, dy = p.y - rs.y;
            rs = null;
            var minW = Math.round(560 * root.uiS), minH = Math.round(380 * root.uiS);
            var nw = width, nh = height;
            if (e & Qt.RightEdge)  nw = width + dx;
            if (e & Qt.LeftEdge)   nw = width - dx;
            if (e & Qt.BottomEdge) nh = height + dy;
            if (e & Qt.TopEdge)    nh = height - dy;
            nw = Math.max(minW, Math.round(nw)); nh = Math.max(minH, Math.round(nh));
            console.log('[macshell-settings] resize on release:', width + 'x' + height, '->', nw + 'x' + nh);
            if (nw === width && nh === height) return;
            var sel = 'window = "title:^(' + title + ')$"';
            // current position (left / top edges keep the opposite edge fixed by moving the window as well)
            var ox = null, oy = null, cs = root.glassClients || [];
            for (var i = 0; i < cs.length; i++) if (cs[i].title === title && cs[i].mapped) { ox = cs[i].at[0]; oy = cs[i].at[1]; break; }
            Hyprland.dispatch('hl.dsp.window.resize({ x = ' + nw + ', y = ' + nh + ', "exact", ' + sel + ' })');
            if (ox !== null && ((e & Qt.LeftEdge) || (e & Qt.TopEdge))) {
                var nx = (e & Qt.LeftEdge) ? ox + (width - nw) : ox;
                var ny = (e & Qt.TopEdge) ? oy + (height - nh) : oy;
                Hyprland.dispatch('hl.dsp.window.move({ x = ' + nx + ', y = ' + ny + ', ' + sel + ' })');
            }
        }

        function applyScaledSize() {
            minimumWidth = Math.round(560 * root.uiS); minimumHeight = Math.round(380 * root.uiS);
            width = preferredWidth; height = preferredHeight;
        }
        Component.onCompleted: applyScaledSize()
        Connections {
            target: root
            function onUiSChanged() { prefsWindow.applyScaledSize(); if (prefsWindow.visible) { prefsWindow.floatTries = 0; floatTimer.restart(); } }
        }
        Timer {
            id: floatTimer
            interval: 60
            repeat: true
            onTriggered: {
                // the compositor maps the window a moment after it becomes visible: send the dispatches a few times
                var sel = 'window = "title:^(' + prefsWindow.title + ')$"';
                Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", ' + sel + ' })');
                // the window draws its own macOS-style edge: no Hyprland border, and Hyprland's rounding (used for its
                // shadow and the blur behind the sidebar) matches the window's own corner radius
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "border_size", value = "0", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "rounding", value = "' + Math.round(frame.radius * root.uiS) + '", ' + sel + ' })');
                // Hyprland can remember an older floating size; reapply the compact size after mapping.
                if (prefsWindow.floatTries >= 2) {
                    Hyprland.dispatch('hl.dsp.window.resize({ x = ' + prefsWindow.preferredWidth + ', y = ' + prefsWindow.preferredHeight + ', "exact", ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.center({ ' + sel + ' })');
                }
                if (++prefsWindow.floatTries >= 12) stop();
            }
        }

        // ── palette ──
        QtObject {
            id: pal
            readonly property bool dark: root.darkMode
            readonly property string fam: root.fontFamily
            readonly property color accent: root.accent
            readonly property bool glass: root.liquidActive
            readonly property color content: glass ? (dark ? Qt.rgba(0.09, 0.09, 0.10, 0.58) : Qt.rgba(0.97, 0.97, 0.98, 0.62))
                                                   : (dark ? "#1E1E1E" : "#F5F5F7")
            readonly property color sidebar: dark ? "#292929" : "#E9E9EC"
            // the pages are opaque (only the sidebar is translucent), so the cards are solid too
            readonly property color contentSolid: dark ? "#1E1E1E" : "#F5F5F7"
            readonly property color sidebarGlass: dark ? Qt.rgba(0.17, 0.17, 0.18, 0.55) : Qt.rgba(0.94, 0.94, 0.96, 0.60)
            readonly property color card: dark ? "#2B2B2D" : "#FFFFFF"
            readonly property color cardBorder: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.12)
            readonly property color windowBorder: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.22)
            // two-tone macOS window edge: a thin dark line outside, a soft highlight just inside it
            readonly property color edgeOuter: Qt.rgba(1, 1, 1, 0.50)
            readonly property color edgeInner: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.65)
            readonly property color sep: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.12)
            readonly property color text: dark ? "#F5F5F7" : "#1D1D1F"
            readonly property color text2: dark ? Qt.rgba(1, 1, 1, 0.56) : Qt.rgba(0, 0, 0, 0.52)
            readonly property color text3: dark ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(0, 0, 0, 0.30)
            readonly property color track: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.13)
            readonly property color switchOff: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
            readonly property color ctrl: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
            readonly property color ctrlSel: dark ? "#636366" : "#FFFFFF"
            readonly property color button: dark ? Qt.rgba(1, 1, 1, 0.13) : "#FFFFFF"
            readonly property color buttonPressed: dark ? Qt.rgba(1, 1, 1, 0.24) : "#E4E4E7"
            readonly property color buttonBorder: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.20)
            readonly property color field: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
            readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
            readonly property color selInactive: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
            function lightBorder(active, c) { return active ? Qt.darker(c, dark ? 1.12 : 1.22) : "transparent"; }
            readonly property color lightOff: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.15)
            readonly property color danger: "#FF453A"
        }

        NumberAnimation { id: fadeIn; target: paneLoader; property: "opacity"; from: 0; to: 1; duration: 160 }

        // ── frame ──
        Rectangle {
            id: frame
            // drawn at a scaled size: the whole window content shrinks with the UI scale, the window itself shrinks to match
            width: parent.width / root.uiS; height: parent.height / root.uiS
            scale: root.uiS; transformOrigin: Item.TopLeft
            radius: 12
            color: "transparent"        // the sidebar is translucent (blur of what is behind the window), the pages are opaque
            border.width: 1
            border.color: pal.edgeOuter

            // inner highlight (on top of everything, never takes the mouse)
            Rectangle {
                anchors.fill: parent; anchors.margins: 1
                radius: frame.radius - 1
                color: "transparent"
                border.width: 1; border.color: pal.edgeInner
                z: 900
            }

            // "New update x.x.x": shown by itself when Settings opens and a newer version exists. Nothing is downloaded.
            Item {
                id: updateOverlay
                anchors.fill: parent
                z: 1000
                visible: root.bar && root.bar.updateDialogOpen
                MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons }     // modal: blocks the page underneath
                Rectangle { anchors.fill: parent; radius: frame.radius; color: Qt.rgba(0, 0, 0, pal.dark ? 0.45 : 0.25) }
                Rectangle {
                    anchors.centerIn: parent
                    width: 300; height: 176
                    radius: 14
                    color: pal.contentSolid
                    border.width: 1; border.color: pal.buttonBorder
                    Text {
                        x: 0; y: 28; width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("New update ") + (root.bar ? root.bar.updateVersion : "")
                        color: pal.text
                        font.family: root.fontForWeight(Font.DemiBold, pal.fam); font.weight: Font.DemiBold
                        font.pixelSize: 17
                    }
                    Text {
                        x: 20; y: 62; width: parent.width - 40
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: I18n.tr("A new version of MacShell is available.")
                        color: pal.text2
                        font.family: root.fontForWeight(Font.Normal, pal.fam)
                        font.pixelSize: 13
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 20
                        spacing: 10
                        SButton {
                            t: pal
                            text: I18n.tr("Update")
                            onClicked: { if (root.bar) root.bar.openUpdateLink(); }
                        }
                        SButton {
                            t: pal
                            text: I18n.tr("Close")
                            onClicked: { if (root.bar) root.bar.updateDialogOpen = false; }
                        }
                    }
                }
            }

            // opaque page area: from the sidebar's right edge to the window edge (rounded on the right only)
            Rectangle {
                x: sidebar.x + sidebar.width; y: 1
                width: parent.width - x - 1; height: parent.height - 2
                radius: 11
                color: pal.contentSolid
                Rectangle { anchors.left: parent.left; width: 12; height: parent.height; color: parent.color }
            }

            // Native Wayland resize handles for this frameless window.
            MouseArea { x: 12; y: 0; width: parent.width - 24; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; onPressed: m => { prefsWindow.rsBegin(Qt.TopEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: 12; y: parent.height - 6; width: parent.width - 24; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; onPressed: m => { prefsWindow.rsBegin(Qt.BottomEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: 0; y: 12; width: 6; height: parent.height - 24; z: 1000; cursorShape: Qt.SizeHorCursor; onPressed: m => { prefsWindow.rsBegin(Qt.LeftEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: parent.width - 6; y: 12; width: 6; height: parent.height - 24; z: 1000; cursorShape: Qt.SizeHorCursor; onPressed: m => { prefsWindow.rsBegin(Qt.RightEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: 0; y: 0; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeFDiagCursor; onPressed: m => { prefsWindow.rsBegin(Qt.TopEdge | Qt.LeftEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: parent.width - 12; y: 0; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeBDiagCursor; onPressed: m => { prefsWindow.rsBegin(Qt.TopEdge | Qt.RightEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: 0; y: parent.height - 12; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeBDiagCursor; onPressed: m => { prefsWindow.rsBegin(Qt.BottomEdge | Qt.LeftEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: parent.width - 12; y: parent.height - 12; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeFDiagCursor; onPressed: m => { prefsWindow.rsBegin(Qt.BottomEdge | Qt.RightEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }

            // drag the window by its top strip
            Item {
                z: 3        // above the page scroller (which now reaches the top), below the sidebar with the traffic lights
                width: parent.width
                height: 52
                DragHandler {
                    target: null
                    onActiveChanged: if (active) prefsWindow.startSystemMove()
                }
            }

            // ───────── sidebar ─────────
            Rectangle {
                id: sidebar
                z: 4
                // the sidebar is the normal flat one, attached to the window edge (set floating to true for the inset glass card)
                readonly property bool floating: false
                x: sidebar.floating ? 8 : 1; y: sidebar.floating ? 8 : 1
                width: sidebar.floating ? 224 : 232
                height: parent.height - (sidebar.floating ? 16 : 2)
                radius: sidebar.floating ? 18 : 11
                // frosted: a translucent pane over Hyprland's blur of what's behind the window (no Liquid Glass shader)
                color: sidebar.floating ? (pal.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.35)) : "transparent"
                border.width: sidebar.floating ? 1 : 0
                border.color: pal.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                // translucent fill, drawn as ONE layer so the rounded body and the square right edge don't add up to a darker band:
                // both shapes are opaque inside the layer, and the layer carries the translucency
                Item {
                    visible: !sidebar.floating
                    anchors.fill: parent
                    z: -1
                    layer.enabled: true
                    opacity: pal.sidebarGlass.a
                    Rectangle { anchors.fill: parent; radius: sidebar.radius; color: Qt.rgba(pal.sidebarGlass.r, pal.sidebarGlass.g, pal.sidebarGlass.b, 1) }
                    Rectangle { anchors.right: parent.right; width: 14; height: parent.height; color: Qt.rgba(pal.sidebarGlass.r, pal.sidebarGlass.g, pal.sidebarGlass.b, 1) }
                }
                Rectangle { visible: !sidebar.floating; anchors.right: parent.right; width: 1; height: parent.height; color: pal.sep }

                // Hidden Liquid Glass capture: the wallpaper exactly where the window sits, grabbed as ONE picture.
                // Nothing is drawn fullscreen — only the back / forward pill refracts this picture (via pillSrc).
                Loader {
                    id: sbLd
                    parent: frame
                    z: -60
                    active: false      // the < > pill no longer refracts the wallpaper: // settingsGlass && the window's position on its monitor is known
                    readonly property real pillM: 64                    // backdrop margin around the window (refraction reach)
                    sourceComponent: Item {
                        id: sbg
                        readonly property real m: sbLd.pillM
                        readonly property var pillSrc: pillSes          // exposed for the back / forward pill (ids inside don't escape)
                        Item {
                            id: prefsBackdrop
                            parent: frame
                            x: -sbg.m; y: -sbg.m
                            z: -100
                            width: frame.width + 2 * sbg.m
                            height: frame.height + 2 * sbg.m
                            Rectangle { anchors.fill: parent; color: "#141418" }
                            Image {
                                x: sbg.m - prefsGlassGeo.x
                                y: sbg.m - prefsGlassGeo.y
                                width: prefsGlassGeo.mw; height: prefsGlassGeo.mh
                                source: root.fileUrl(root.wallpaperFor(prefsGlassGeo.mon))
                                sourceSize.width: prefsGlassGeo.mw
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true; smooth: true
                            }
                            LiveWall {
                                x: sbg.m - prefsGlassGeo.x
                                y: sbg.m - prefsGlassGeo.y
                                width: prefsGlassGeo.mw; height: prefsGlassGeo.mh
                                video: root.bar ? root.bar.glassVideo : ""
                                live: root.glassLive && prefsWindow.visible
                                paused: !!root.bar && root.bar.gaming
                            }
                        }
                        ShaderEffectSource {
                            id: pillSes
                            sourceItem: prefsBackdrop
                            hideSource: true
                            live: true
                            mipmap: true
                            visible: false
                            textureSize: Qt.size(Math.round(prefsBackdrop.width / 2), Math.round(prefsBackdrop.height / 2))
                        }
                    }
                }

                // traffic lights
                Item {
                    id: lights
                    x: 17; y: 14
                    width: 58; height: 14
                    Row {
                        scale: 0.93; transformOrigin: Item.TopLeft      // a touch smaller
                        spacing: 8
                        Repeater {
                            model: [
                                { c: "#FF5F57", g: "\u00D7", on: true },
                                { c: "#FEBC2E", g: "\u2212", on: true },
                                { c: "#28C840", g: "↗", on: true }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: 14; height: 14; radius: 7
                                color: (modelData.on && (prefsWindow.active || lightsMa.containsMouse))
                                       ? modelData.c : pal.lightOff
                                border.width: 1
                                border.color: pal.lightBorder(modelData.on && (prefsWindow.active || lightsMa.containsMouse), modelData.c)
                                Canvas {
                                    anchors.fill: parent
                                    visible: lightsMa.containsMouse && parent.modelData.on
                                    onVisibleChanged: if (visible) requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        if (parent.modelData.g === "\u00D7") {
                                            ctx.strokeStyle = "rgba(0,0,0,0.58)";
                                            ctx.lineWidth = 1.1;
                                            ctx.lineCap = "round";
                                            ctx.beginPath();
                                            ctx.moveTo(4.9, 4.9); ctx.lineTo(9.1, 9.1);
                                            ctx.moveTo(9.1, 4.9); ctx.lineTo(4.9, 9.1);
                                            ctx.stroke();
                                        } else if (parent.modelData.g === "\u2212") {
                                            ctx.strokeStyle = "rgba(0,0,0,0.58)";
                                            ctx.lineWidth = 1.2;
                                            ctx.lineCap = "round";
                                            ctx.beginPath();
                                            ctx.moveTo(3.5, 7.0); ctx.lineTo(10.5, 7.0);
                                            ctx.stroke();
                                        } else if (parent.modelData.g === "↗") {
                                            ctx.fillStyle = "rgba(0,0,0,0.58)";
                                            ctx.beginPath();
                                            ctx.moveTo(6, 4); ctx.lineTo(10, 4); ctx.lineTo(10, 8);
                                            ctx.closePath();
                                            ctx.fill();
                                            ctx.beginPath();
                                            ctx.moveTo(8, 10); ctx.lineTo(4, 10); ctx.lineTo(4, 6);
                                            ctx.closePath();
                                            ctx.fill();
                                        }
                                    }
                                }
                            }
                        }
                    }
                    MouseArea {
                        id: lightsMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: mouse => {
                            if (mouse.x < 22) prefsWindow.visible = false;
                            else if (mouse.x < 44) root.minimizeActive();
                            else if (mouse.x < 58) {
                                if (prefsWindow.visibility === Window.FullScreen) prefsWindow.showNormal();
                                else prefsWindow.showFullScreen();
                            }
                        }
                    }
                }

                // search field
                Rectangle {
                    id: search
                    x: 12; y: 50
                    width: parent.width - 24
                    height: 28
                    radius: 7
                    color: pal.field

                    Rectangle {   // focus ring
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: 9
                        color: "transparent"
                        border.width: 3
                        border.color: Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.5)
                        visible: searchInput.activeFocus
                    }
                    Item {   // magnifier
                        x: 9
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14
                        Rectangle {
                            width: 9; height: 9; radius: 4.5
                            color: "transparent"
                            border.width: 2
                            border.color: pal.text3
                        }
                        Rectangle {
                            x: 8; y: 9
                            width: 5; height: 1.6; radius: 0.8
                            color: pal.text3
                            rotation: 45
                            transformOrigin: Item.Left
                        }
                    }
                    TextInput {
                        id: searchInput
                        x: 30
                        width: parent.width - 54
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        selectByMouse: true
                        color: pal.text
                        selectionColor: pal.accent
                        font.family: root.fontForWeight(Font.Normal, pal.fam)
                        font.pixelSize: 13
                        onTextChanged: prefsWindow.query = text
                    }
                    Text {
                        x: 30
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text === ""
                        text: I18n.tr("Search")
                        color: pal.text3
                        font.family: root.fontForWeight(Font.Normal, pal.fam)
                        font.pixelSize: 13
                    }
                    Rectangle {   // clear button
                        visible: searchInput.text !== ""
                        anchors.right: parent.right
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14; radius: 7
                        color: pal.text3
                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -0.5
                            text: "\u00D7"
                            color: pal.sidebar
                            font.family: Fonts.forWeight(Font.Bold, pal.fam); font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: searchInput.text = "" }
                    }
                }

                // account card (macOS: your name + picture at the top of the sidebar) → Users & Groups
                Rectangle {
                    id: acct
                    x: 10; y: 90; width: parent.width - 20; height: 52; radius: 10
                    visible: prefsWindow.query === ""
                    readonly property int idx: { for (var i = 0; i < prefsWindow.panes.length; i++) if (prefsWindow.panes[i].id === "users") return i; return 0; }
                    color: prefsWindow.cur === idx ? (prefsWindow.active ? pal.accent : pal.selInactive) : (acctMa.containsMouse ? pal.hover : "transparent")
                    Item {
                        id: acctPic
                        x: 6; anchors.verticalCenter: parent.verticalCenter; width: 38; height: 38
                        Item { id: acctMask; anchors.fill: parent; visible: false; layer.enabled: true; Rectangle { anchors.fill: parent; radius: width / 2; color: "black" } }
                        Rectangle { anchors.fill: parent; radius: width / 2; color: pal.ctrl }
                        Image {
                            anchors.fill: parent; source: "file://" + Quickshell.env("HOME") + "/.face"; sourceSize: Qt.size(96, 96)
                            fillMode: Image.PreserveAspectCrop; cache: false
                            layer.enabled: true; layer.effect: MultiEffect { maskEnabled: true; maskSource: acctMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                        }
                    }
                    Column {
                        x: 52; anchors.verticalCenter: parent.verticalCenter
                        Text { text: root.userName; color: prefsWindow.cur === acct.idx && prefsWindow.active ? "white" : pal.text; font.family: root.fontForWeight(Font.DemiBold, pal.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { text: I18n.tr("Local Account"); color: prefsWindow.cur === acct.idx && prefsWindow.active ? Qt.rgba(1, 1, 1, 0.8) : pal.text2; font.family: root.fontForWeight(Font.Normal, pal.fam); font.pixelSize: 11 }
                    }
                    MouseArea { id: acctMa; anchors.fill: parent; hoverEnabled: true; onClicked: prefsWindow.go(acct.idx) }
                }

                // pane list (scrolls; sections separated by a gap, like System Settings)
                // feather: the list dissolves at the top / bottom edge wherever more rows are hidden beyond it
                Item {
                    id: navFeather
                    visible: false; layer.enabled: true
                    width: navFlick.width; height: navFlick.height
                    readonly property real size: 26
                    readonly property real topFade: Math.max(0, Math.min(1, navFlick.contentY / 18))
                    readonly property real bottomFade: Math.max(0, Math.min(1, (navFlick.contentHeight - navFlick.height - navFlick.contentY) / 18))
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 1 - navFeather.topFade) }
                            GradientStop { position: Math.min(0.49, navFeather.size / Math.max(1, navFeather.height)); color: "black" }
                            GradientStop { position: Math.max(0.51, 1 - navFeather.size / Math.max(1, navFeather.height)); color: "black" }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 1 - navFeather.bottomFade) }
                        }
                    }
                }
                Flickable {
                    id: navFlick
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: navFeather }
                    x: 10; y: acct.visible ? 150 : 92
                    width: parent.width - 20
                    height: parent.height - y - 8
                    contentHeight: navCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: navCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: prefsWindow.filtered
                        delegate: Item {
                            id: navItem
                            required property int modelData
                            required property int index
                            readonly property bool gap: index > 0 && prefsWindow.panes[prefsWindow.filtered[index - 1]].sec !== prefsWindow.panes[modelData].sec
                            width: parent.width
                            height: 34 + (gap ? 12 : 0)
                        Rectangle {
                            id: navRow
                            readonly property int modelData: navItem.modelData
                            readonly property var p: prefsWindow.panes[modelData]
                            readonly property bool sel: prefsWindow.cur === modelData
                            y: navItem.gap ? 12 : 0
                            width: parent.width
                            height: 34
                            radius: 8
                            color: sel ? (prefsWindow.active ? pal.accent : pal.selInactive)
                                       : (navMa.containsMouse ? pal.hover : "transparent")

                            SGlyph {

                                fam: pal.fam
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                kind: navRow.p.glyph || ""
                                wg: navRow.p.wg || ""
                                c1: navRow.p.c1
                                c2: navRow.p.c2
                            }
                            Text {
                                x: 42
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr(navRow.p.name)
                                color: (navRow.sel && prefsWindow.active) ? "white" : pal.text
                                font.family: root.fontForWeight(Font.Normal, pal.fam)
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: navMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: prefsWindow.go(navRow.modelData)
                            }
                        }
                        }
                    }

                    Text {
                        visible: prefsWindow.filtered.length === 0
                        width: parent.width
                        topPadding: 14
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("No Results")
                        color: pal.text2
                        font.family: root.fontForWeight(Font.Normal, pal.fam)
                        font.pixelSize: 12
                    }
                }
                }
            }

            // Backdrop for the < > pill: the Settings window itself (page colour, the sidebar edge and the page scrolling under the
            // toolbar), grabbed as one picture. The pill refracts this, never the wallpaper.
            Item {
                id: pillBack
                parent: frame
                z: -100
                readonly property real m: 64
                x: header.x + navPill.x - m; y: header.y + navPill.y - m
                width: navPill.width + 2 * m; height: navPill.height + 2 * m
                Rectangle { anchors.fill: parent; color: pal.contentSolid }
                Rectangle { x: 0; y: 0; width: Math.max(0, sidebar.x + sidebar.width - pillBack.x); height: parent.height; color: pal.sidebar }
                Rectangle { x: Math.max(0, sidebar.x + sidebar.width - pillBack.x); y: 0; width: 1; height: parent.height; color: pal.sep }
                ShaderEffectSource {
                    x: flick.x - pillBack.x; y: flick.y - pillBack.y
                    width: Math.max(1, parent.width - x); height: Math.max(1, parent.height - y)
                    sourceItem: flick
                    sourceRect: Qt.rect(0, 0, width, height)
                    live: true
                }
            }
            ShaderEffectSource { id: pillSes; sourceItem: pillBack; hideSource: true; live: true; mipmap: true; visible: false }

            // ───────── toolbar ─────────
            Item {
                id: header
                z: 6
                x: sidebar.x + sidebar.width + 1
                width: parent.width - sidebar.x - sidebar.width - 2
                height: 52
                GlassSlab {                         // Liquid Glass pill behind the back / forward buttons
                    id: navPill
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 66; height: 36
                    cornerR: 18
                    glass: root.settingsGlass
                    shaderUrl: root.glassShaderUrl
                    dark: pal.dark
                    // refracts the Settings window itself (pillBack below), never the wallpaper
                    src: pillSes
                    srcSize: Qt.size(pillBack.width, pillBack.height)
                    origin: Qt.point(pillBack.m, pillBack.m)
                    baseColor: pal.dark ? "#3C3C40" : "#FBFBFD"
                    blurPx: 6                              // more blur behind the < > pill (was 1.5)
                    thickness: 14; strengthMul: 0.6        // same glass as the Control Center buttons
                    liquid: root.glassLiquid
                    rim: root.glassRim * 0.25
                    grain: root.glassGrain
                    tint: root.glassOpacity
                    shadowAmt: 0; flatInner: 1
                    onFailed: root.glassState = "failed"
                    // Control Center border: thin, brighter shade of the wallpaper colour, fading at top-right / bottom-left
                    CornerBorder {
                        z: 2; anchors.fill: parent
                        cornerR: 18; dark: pal.dark
                        tint: root.bar ? root.bar.menuBorderColor : "#8A9AB5"
                        amount: 1; lineW: 0.8
                    }
                }

                Row {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: [ { g: "\u2039", dir: -1 }, { g: "\u203A", dir: 1 } ]
                        delegate: Item {
                            id: navBtn
                            required property var modelData
                            readonly property bool ok: modelData.dir < 0 ? prefsWindow.backStack.length > 0
                                                                           : prefsWindow.fwdStack.length > 0
                            width: 26; height: 28
                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -2
                                text: navBtn.modelData.g
                                font.family: Fonts.forWeight(Font.Normal, pal.fam); font.pixelSize: 28
                                color: navBtn.ok ? pal.text : pal.text3
                                opacity: navBtn.ok ? 1 : 0.5
                                scale: (navBtn.ok && navMa.pressed) ? 0.86 : 1
                                Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 3.2 } }
                            }
                            MouseArea {
                                id: navMa
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: navBtn.ok
                                onClicked: {
                                    if (navBtn.modelData.dir < 0) prefsWindow.back();
                                    else prefsWindow.forward();
                                }
                            }
                        }
                    }
                }
                Text {
                    x: 90
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr(prefsWindow.panes[prefsWindow.cur].name)
                    color: pal.text
                    font.family: root.fontForWeight(Font.DemiBold, pal.fam)
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }

            // ───────── scrolling content ─────────
            Flickable {
                id: flick
                x: sidebar.x + sidebar.width + 1
                y: 1
                width: parent.width - sidebar.x - sidebar.width - 2
                height: parent.height - 2
                contentWidth: width
                contentHeight: paneLoader.height + 36 + 52
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                Loader {
                    id: paneLoader
                    // nothing of Settings stays built while the window is closed
                    active: prefsWindow.visible
                    x: 22
                    y: 58
                    width: flick.width - 44
                    sourceComponent: ({
                        wifi: paneWifi, bluetooth: paneBt, network: paneNetwork, battery: paneBattery,
                        general: paneGeneral, appearance: paneAppearance, siri: paneSiri, controlcenter: paneCC, dock: paneDesktopDock,
                        displays: paneDisplays, menubar: paneMenuBar, wallpaper: paneWallpaper,
                        notifications: paneNotif, sound: paneSound, focus: paneFocus,
                        widgets: paneWidgets, lockscreen: paneLock, users: paneUsers, keyboard: paneKeyboard, mouse: paneMouse, trackpad: paneTrackpad,
                        apps: paneApps, about: paneAbout
                    })[prefsWindow.panes[prefsWindow.cur].id]
                    onLoaded: fadeIn.restart()
                }
            }
            // Tahoe-style scroll-under blur: what slides up under the toolbar is blurred, and the blur melts away below it
            // (FeatherBlur.qml). It re-draws the page; the page itself keeps scrolling and clicking as before.
            FeatherBlur {
                z: 1
                x: flick.x; y: flick.y; width: flick.width; height: flick.height
                target: flick
                topHold: 36                  // height of the fully blurred band
                topDepth: 22                 // short, soft fade-out
                radiusScale: 1.4
                blurMax: 32
                topAmount: Math.max(0, Math.min(1, flick.contentY / 18))
            }
            Rectangle {   // thin overlay scrollbar
                visible: flick.contentHeight > flick.height + 1
                x: frame.width - 8
                y: 52 + flick.visibleArea.yPosition * (flick.height - 52)
                width: 4
                height: Math.max(28, flick.visibleArea.heightRatio * (flick.height - 52))
                radius: 2
                color: pal.text3
                opacity: flick.moving ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
        }

        // ═════════════ PANES ═════════════

        // ── Apple Intelligence & Siri ──
        Component {
            id: paneSiri
            AppleIntelligenceSettings {
                t: pal
                hub: root.hub
            }
        }

        // ── General ──
        Component {
            id: paneGeneral
            Column {
                spacing: 10

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Language")
                        subtitle: I18n.tr("Automatic follows the system language")
                        SSegmented {
                            t: pal
                            readonly property var codes: ["auto", "en", "ru", "es"]
                            model: ["Automatic", "English", "Русский", "Español"]
                            segWidth: 88
                            current: codes.indexOf(root.bar ? root.bar.language : "auto")
                            onPicked: i => { if (root.bar) root.bar.language = codes[i]; }
                        }
                    }
                }

                SLabel { t: pal; header: true; text: I18n.tr("Shell") }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Dock")
                        subtitle: I18n.tr("Show the Dock at the bottom of the screen")
                        SSwitch { t: pal; checked: root.dockEnabled; onToggled: v => root.dockEnabled = v }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Menu Bar")
                        subtitle: I18n.tr("Show the panel at the top of the screen. Spotlight, Control Center and the calendar belong to it.")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.barEnabled : true
                            onToggled: v => { if (root.bar) root.bar.barEnabled = v; }
                        }
                    }
                }
                SLabel {
                    t: pal
                    text: I18n.tr("If you turn both off, reopen this window with:  qs -c MacShell ipc call settings open")
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Software Update")
                        subtitle: !root.bar ? ""
                                  : root.bar.updateChecking ? I18n.tr("Checking for updates…")
                                  : root.bar.updateState === "available" ? I18n.tr("New update ") + root.bar.updateVersion
                                  : root.bar.updateState === "uptodate" ? I18n.tr("MacShell is up to date")
                                  : root.bar.updateState === "error" ? I18n.tr("Couldn't check for updates")
                                  : ""
                        Row {
                            spacing: 8
                            SButton {
                                t: pal
                                visible: root.bar && root.bar.updateState === "available"
                                text: I18n.tr("Update")
                                onClicked: { if (root.bar) root.bar.openUpdateLink(); }
                            }
                            SButton {
                                t: pal
                                opacity: root.bar && root.bar.updateChecking ? 0.5 : 1
                                text: I18n.tr("Check for updates")
                                onClicked: { if (root.bar && !root.bar.updateChecking) root.bar.checkForUpdates(false); }

                            }
                        }
                    }
                }

                            // The backdrop is captured over a FIXED rectangle: the Dock at its widest (fully magnified), in 128 px steps, centred on the
                            // Dock. It used to follow dock.width, and the Dock gets wider and narrower with every pointer move while icons magnify, so
                            // 3-5 GPU textures (this capture, both blur passes, the blur's own buffers) were re-allocated on EVERY pointer move, and
                            // the more icons were pinned the bigger they were. That was the stutter / lag of the magnification. Now the textures keep
                            // their size and only the shader's offset moves.
                            readonly property real magExtra: root.iconSize * (root.effMag - 1) * (root.magRadius / (root.iconSize + root.spacing) + 1)
                            readonly property real capInner: Math.min(Math.ceil(Math.max(dock.width, root.totalW0 + 2 * root.hPad + magExtra) / 128) * 128,
                                                                      win.modelData.width + 320 - 2 * (padPx + margin))   // the mirrored edge padding is 160 px each side
                            readonly property real capW: capInner + 2 * (padPx + margin)
                            readonly property real capH: dock.height + 2 * (padPx + margin)
                            readonly property real capX: (ui.width - capW) / 2                                   // the Dock is centred in the window
                            readonly property real capY: ui.height - root.margin - dock.height + (win.modelData.height - ui.height) - padPx - margin   // untucked position
                            ShaderEffectSource {
                                id: bsrc
                                sourceItem: glassBackdrop.item
                                hideSource: true
                                live: !ui.tucked && !ui.menuOpen
                                visible: false
                                sourceRect: Qt.rect(dg.capX, dg.capY, dg.capW, dg.capH)
                                textureSize: Qt.size(Math.max(1, Math.round(dg.capW * dg.ds)), Math.max(1, Math.round(dg.capH * dg.ds)))
                            }
                            MultiEffect {
                                id: bblurFx
                                source: bsrc
                                width: bsrc.sourceRect.width * dg.ds; height: bsrc.sourceRect.height * dg.ds
                                blurEnabled: true
                                blurMax: 64
                                blur: Math.min(1.0, dg.bn)
                                autoPaddingEnabled: false
                                visible: false
                            }
                            // real Gaussian pre-blur of the backdrop (Qt MultiEffect): the glass shader refracts THIS texture,
                            // so there are no sampled copies of the background any more
                            ShaderEffectSource {
                                id: bblur
                                sourceItem: bblurFx
                                live: !ui.tucked && !ui.menuOpen
                                visible: false
                            }
                            MultiEffect {
                                id: bblur2Fx
                                source: bblur
                                width: bsrc.sourceRect.width * dg.ds; height: bsrc.sourceRect.height * dg.ds
                                blurEnabled: dg.bn > 1.0
                                blurMax: 64
                                blur: Math.max(0.0, Math.min(1.0, dg.bn - 1.0))
                                autoPaddingEnabled: false
                                visible: false
                            }
                            // second Gaussian pass: only active when the slider goes past a single pass's 64 px limit
                            ShaderEffectSource {
                                id: bblur2
                                // the 2nd pass is a pure copy unless the blur radius exceeds one pass: skip it then (same pixels, one GPU pass less)
                                sourceItem: dg.bn > 1.0 ? bblur2Fx : null
                                live: !ui.tucked && !ui.menuOpen
                                visible: false
                            }
                            ShaderEffect {
                                id: glassFx
                                x: -padPx; y: -padPx
                                width: dock.width + 2 * padPx
                                height: dock.height + 2 * padPx
                                fragmentShader: root.dockGlassUrl
                                onStatusChanged: {
                                    console.log("[macdock-glass] shader status:", status, "(0 = compiled, 1 = uncompiled, 2 = error)", log);
                                    if (status === ShaderEffect.Error) {
                                        // the Dock's own shader failed to load: drop back to the shared one; only if THAT fails too, give up on Liquid Glass
                                        if (root.dockGlassNew) root.dockGlassState = "failed";
                                        else root.glassState = "failed";
                                    }
                                }
                                // dockglass.frag only (ignored by liquidglass.frag): rgb = wallpaper colour, a = how strongly the edge light follows it
                                property vector4d edgeTint: Qt.vector4d(dg.edgeCol.r, dg.edgeCol.g, dg.edgeCol.b, root.dockGlassNew ? 0.5 : 0)

                                property variant src: dg.bn > 1.0 ? bblur2 : bblur
                                property real padPx: parent.padPx
                                property vector2d itemSize: Qt.vector2d(width, height)
                                property vector2d glassSize: Qt.vector2d(dock.width, dock.height)
                                property vector2d srcSize: Qt.vector2d(dg.capW, dg.capH)
                                // where this item's top-left sits inside the (fixed) capture; follows the Dock as it widens / tucks
                                property vector2d srcOffset: Qt.vector2d(dock.x - padPx - dg.capX,
                                                                         dock.y + (win.modelData.height - ui.height) - padPx - dg.capY)
                                property real pad: padPx
                                property real radius: root.cornerRadius
                                property real bezel: Math.min(dock.height * 0.36, 26)
                                property real thickness: 30 * root.glassLiquid
                                property real dispersion: 0.06 * root.glassLiquid
                                property real magnify: 0.08 * root.glassLiquid
                                property real rim: root.glassRim * 0.20
                                property real grain: root.glassGrain * 0.3     // quieter noise on the Dock glass
                                property real blurPx: 1.5            // tiny residual smoothing; the real blur is the MultiEffect pre-pass
                                property real tintMix: root.glassOpacity * 0.55
                                property real saturation: 1.25
                                property real dark: root.dockDark ? 1 : 0
                                property real debug: root.glassDebug ? 1 : 0
                                // Keep the Dock glass clean: no drop shadow.
                                property real shadowAmt: 0
                                property real rimTint: 0
                                property real ringW: 0
                            }
                        }
                    }

                    Rectangle {
                        visible: !root.liquidActive
                        anchors.fill: parent
                        radius: root.cornerRadius
                        color: root.dockDark ? Qt.rgba(0.10, 0.10, 0.11, root.glassOpacity)
                                             : Qt.rgba(1, 1, 1, root.glassOpacity * 0.55)
                        border.width: 0      // dark outer border removed

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 0
                            radius: parent.radius - 0.35
                            color: "transparent"
                            border.width: 0.25
                            border.color: root.dockDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.12)
                        }
                    }

                    // same extra edge detail as the top-bar menus: faint dominant-colour edge (no dark hairline)
                    MenuBorder {
                        anchors.fill: parent      // no z: stays below the icon row, so magnified icons are drawn over the border
                        cornerR: root.cornerRadius
                        dark: root.dockDark
                        tint: root.bar ? root.bar.menuBorderColor : "#8A9AB5"
                        outline: false      // no dark hairline / shade around the dock
                    }

                    // The dark hairline of the real macOS Dock: ~1.5 px wide, centred ON the edge of the glass (half outside, half inside),
                    // about 12% dark along the straight left and right sides, easing out around the corners until it is gone where the
                    // top and bottom edges start (those carry the bright line from the glass shader instead). Plain black with alpha, so it
                    // darkens whatever is behind it and follows the wallpaper. The canvas is 3 px larger than the Dock on every side so
                    // the outer half of the line can be drawn; it only repaints when the Dock's size, corner radius or mode changes.
                    // Drawn as two small end caps (left, right = mirrored) instead of one Canvas over the whole Dock. The hairline fades out
                    // within one corner radius of each end and the Dock's HEIGHT never changes, so a cap looks the same whatever the width. The old
                    // full-width Canvas repainted (a CPU raster + texture upload) on every pointer move while the Dock widened under magnification,
                    // and the wider the Dock (more pinned apps) the slower that got. The caps are painted once (again on size / radius change).
                    Repeater {
                        model: 2
                        delegate: Canvas {
                            id: cap
                            required property int index
                            readonly property real fadeW: Math.min(root.cornerRadius, root.bgHeight / 2) * 1.05
                            anchors.top: parent.top;       anchors.topMargin: -3
                            anchors.bottom: parent.bottom; anchors.bottomMargin: -3
                            width: Math.ceil(3 + fadeW) + 3
                            antialiasing: true
                            // index 0 hugs the left edge; index 1 is the same picture mirrored on the right edge
                            x: index === 0 ? -3 : parent.width + 3 - width
                            transform: Scale { origin.x: cap.width / 2; xScale: cap.index === 0 ? 1 : -1 }
                            readonly property real strength: root.dockDark ? 0.14 : 0.12
                            onStrengthChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            Connections { target: root; function onCornerRadiusChanged() { cap.requestPaint(); } }
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                var m = 3, H = height;
                                var h = H - 2 * m;                         // the Dock's height
                                if (h < 4) return;
                                var r = Math.max(2, Math.min(root.cornerRadius, h / 2));
                                var fade = r * 1.05;
                                // paint as if the Dock were wide: only its near end shows inside this narrow canvas
                                var w = 2 * (fade + r) + 8;
                                var g = ctx.createLinearGradient(m, 0, m + w, 0);
                                var N = 24;
                                for (var k = 0; k <= N; k++) {
                                    var u = k / N, sm = u * u * u * (u * (u * 6 - 15) + 10), al = (strength * (1 - sm)).toFixed(4);
                                    g.addColorStop(u * fade / w, "rgba(0,0,0," + al + ")");
                                    g.addColorStop(1 - u * fade / w, "rgba(0,0,0," + al + ")");
                                }
                                ctx.strokeStyle = g;
                                ctx.lineWidth = 1.6;
                                ctx.beginPath();
                                ctx.moveTo(m + r, m);
                                ctx.lineTo(m + w - r, m);
                                ctx.arc(m + w - r, m + r, r, 1.5 * Math.PI, 2 * Math.PI, false);
                                ctx.lineTo(m + w, m + h - r);
                                ctx.arc(m + w - r, m + h - r, r, 0, 0.5 * Math.PI, false);
                                ctx.lineTo(m + r, m + h);
                                ctx.arc(m + r, m + h - r, r, 0.5 * Math.PI, Math.PI, false);
                                ctx.lineTo(m, m + r);
                                ctx.arc(m + r, m + r, r, Math.PI, 1.5 * Math.PI, false);
                                ctx.closePath();
                                ctx.stroke();
                            }
                        }
                    }

                    // Natural edge: with Liquid Glass (dockglass.frag) the edge light is drawn by the shader, so this Canvas is not even created.
                    // It stays for Normal Blur and as the fallback when the Dock's own shader is unavailable (a faint line in the wallpaper colour).
                    Loader {
                        anchors.fill: parent
                        active: !(root.liquidActive && root.dockGlassNew)
                        sourceComponent: CornerBorder {
                            anchors.fill: parent
                            cornerR: root.cornerRadius
                            dark: root.dockDark
                            tint: root.bar ? root.bar.menuBorderColor : "#8A9AB5"
                            amount: 0.12
                            lineW: 0.35
                            fade: false
                        }
                    }

                    Row {
                        id: row
                        spacing: root.spacing
                        height: root.iconSize
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: root.bottomPad

                        Repeater {
                            id: rep
                            model: dockModel

                            delegate: Item {
                                id: cell
                                required property string key
                                required property int index
                                readonly property var modelData: root.itemMap[key] || ({ kind: "sep", key: key, nA: 0, nS: 0 })
                                readonly property bool isSep: modelData.kind === "sep"
                                readonly property bool canDrag: !isSep && modelData.pinned === true && !modelData.special
                                readonly property bool torn: ui.tearing && ui.tearItem && !isSep && ui.tearItem.key === modelData.key
                                opacity: (torn ? 0.3 : (isDragged ? 0.92 : 1)) * (leavingCell ? appear : 1)
                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                readonly property bool isDragged: ui.dragging && modelData.key === ui.dragKey

                                // app cells always show their plain icon; only window cells show a live preview
                                // (with the app's icon as a badge), grouped next to the Trash
                                readonly property var thumbWin: (!isSep && modelData.kind === "win") ? modelData.tl : null
                                // the capture only restarts when the window itself changes — refreshed Dock data hands the cell
                                // the same window again, and re-binding it used to blank the live preview for ~2 s
                                property var heldTl: null
                                readonly property string winAddr: { if (!thumbWin) return ""; var h = ui.hyprOf(thumbWin); return h ? String(h.address).replace(/^0x/, "") : ""; }
                                readonly property bool closingWin: winAddr !== "" && root.hub && root.hub.closingWins[winAddr] === true
                                onThumbWinChanged: if (thumbWin !== heldTl) heldTl = thumbWin
                                readonly property bool useThumb: thumbWin !== null
                                readonly property bool thumbReady: useThumb && (sv.hasContent === undefined || sv.hasContent === true)

                                property real dx: {
                                    if (!ui.dragging || isSep) return 0;
                                    if (isDragged) return ui.dragDelta;
                                    return ui.shiftFor(index);
                                }
                                Behavior on dx {
                                    enabled: !cell.isDragged
                                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                }
                                transform: Translate { x: cell.dx }
                                z: isDragged ? 100 : 0

                                readonly property Item iconImg: img
                                readonly property bool leavingCell: modelData.leaving === true
                                property real appear: modelData.fresh ? 0 : 1
                                Behavior on appear { NumberAnimation { duration: cell.leavingCell ? root.leaveMs : 320; easing.type: cell.leavingCell ? Easing.InOutCubic : Easing.OutCubic } }
                                Component.onCompleted: { heldTl = thumbWin; Qt.callLater(function () { cell.appear = cell.leavingCell ? 0 : 1; cell.bounceStep(); }); }
                                onLeavingCellChanged: appear = leavingCell ? 0 : 1
                                enabled: !leavingCell

                                readonly property real c0: modelData.nA * (root.iconSize + root.spacing)
                                                           + modelData.nS * (root.sepWidth + root.spacing)
                                                           + (isSep ? root.sepWidth : root.iconSize) / 2
                                readonly property real s: {
                                    if (isSep) return 1;
                                    var dist = Math.abs(ui.mx - ui.refLeft - cell.c0);
                                    var R = root.magRadius;
                                    var f = dist < R ? 0.5 * (1 + Math.cos(Math.PI * dist / R)) : 0;
                                    return 1 + (root.effMag - 1) * f * ui.strength;
                                }

                                width: isSep ? root.sepWidth * appear : root.iconSize * s * appear
                                height: root.iconSize

                                Rectangle {
                                    visible: cell.isSep
                                    width: 1
                                    height: root.iconSize * 0.85
                                    anchors.centerIn: parent
                                    color: root.dockDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.22)
                                }

                                Image {
                                    id: img
                                    visible: false
                                    property real lift: 0
                                    // icon art drawn at ~99%: the dock and the cells keep their size. Whole pixels only: at rest this was
                                    // 51.48 px wide and centred on a fractional x, so the GPU re-sampled the icon texture (blurry) until the
                                    // magnification made it big enough that the blur was no longer noticeable
                                    width: Math.max(1, Math.round(root.iconSize * 0.99 * cell.s * cell.appear))
                                    height: width
                                    x: Math.round((parent.width - width) / 2)
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: Math.round(lift)
                                    source: cell.isSep ? "" : root.cellIconSrc(cell.modelData)
                                    sourceSize: Qt.size(Math.ceil(root.iconSize * root.magnification * 1.25),
                                                        Math.ceil(root.iconSize * root.magnification * 1.25))
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    asynchronous: true
                                }
                                MultiEffect {
                                    visible: !cell.isSep && !cell.thumbReady
                                    source: img
                                    anchors.fill: img
                                    shadowEnabled: true
                                    shadowColor: "black"
                                    shadowOpacity: 0.32
                                    shadowBlur: 0.55
                                    shadowVerticalOffset: 3
                                    // icon tint: desaturate, then colourise (no shader build needed)
                                    saturation: root.iconTint ? -0.75 * root.iconTintStrength : 0.0
                                    colorization: root.iconTint ? 1.0 * root.iconTintStrength : 0.0
                                    brightness: (ma.pressed ? -0.3 : 0.0) + (root.iconTint ? 0.14 * root.iconTintStrength : 0.0)
                                    contrast: root.iconTint ? 0.04 * root.iconTintStrength : 0.0
                                    colorizationColor: root.iconTintColor
                                }

                                // ── window thumbnail (same box as the icon, so magnification just works) ──
                                Item {
                                    id: th
                                    anchors.fill: img
                                    // kept (almost) opaque while loading so the capture isn't paused by the renderer
                                    visible: cell.useThumb
                                    opacity: cell.thumbReady ? 1 : 0.01

                                    Rectangle {      // soft drop shadow
                                        x: sv.x
                                        y: sv.y + 3
                                        width: sv.width
                                        height: sv.height
                                        radius: 5
                                        color: Qt.rgba(0, 0, 0, 0.32)
                                    }
                                    SafeCapture {
                                        id: sv
                                        anchors.centerIn: parent
                                        want: (root.hub && !root.hub.windowCapture) ? null : cell.heldTl
                                        graceMs: 400        // longer than the cell's leave animation: the preview stays until the cell is gone, and nothing is in flight by then
                                        // live only while the pointer is on the Dock (where you look at them); otherwise one fresh
                                        // frame every 2 s — live previews of every window were ~8% CPU at idle
                                        wantLive: !ui.tucked && !root.previewHold && !cell.closingWin && hh.hovered
                                        Timer {
                                            interval: 2000; repeat: true; triggeredOnStart: true
                                            running: !sv.wantLive && !ui.tucked && !root.previewHold && !cell.closingWin && sv.armed
                                            onTriggered: sv.snap()
                                        }
                                        readonly property real ar: (implicitWidth > 0 && implicitHeight > 0)
                                                                   ? implicitWidth / implicitHeight : 4 / 3
                                        width: Math.min(th.width, th.height * ar)
                                        height: width / ar
                                    }
                                    Rectangle {      // thin frame + pressed dimming
                                        anchors.fill: sv
                                        radius: 3
                                        color: ma.pressed ? Qt.rgba(0, 0, 0, 0.3) : "transparent"
                                        border.width: 1
                                        border.color: root.dockDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.28)
                                    }
                                }
                                // small app icon in the corner, so you can tell which app the window belongs to
                                Image {
                                    id: badge
                                    visible: cell.thumbReady
                                    width: img.width * 0.46
                                    height: width
                                    x: img.x + img.width - width + 3
                                    y: img.y + img.height - height + 3
                                    source: img.source
                                    sourceSize: Qt.size(Math.ceil(root.iconSize * root.magnification * 0.6),
                                                        Math.ceil(root.iconSize * root.magnification * 0.6))
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }

                                Rectangle {
                                    visible: !cell.isSep && cell.modelData.running && root.showIndicators
                                    width: 4; height: 4; radius: 2
                                    color: root.dockDark ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(0, 0, 0, 0.6)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: cell.height + 3
                                }

                                // ── launch bounce ──
                                // Bounces while the app launches. When the app opens, the bounce in progress finishes its landing, then a
                                // couple of smaller bounces settle it back onto the Dock. Nothing plays while the Dock is tucked away.
                                readonly property bool wantBounce: !cell.isSep && root.bounceOnLaunch && root.launching[cell.modelData.key] !== undefined
                                property bool bounceShown: false          // a bounce was actually visible, so it deserves a settle
                                function bounceStep() {
                                    if (ui.tucked) return;
                                    if (cell.wantBounce) { cell.bounceShown = true; if (!bounceAnim.running && !settleAnim.running) bounceAnim.start(); }
                                    else if (cell.bounceShown && !bounceAnim.running && !settleAnim.running) { cell.bounceShown = false; settleAnim.start(); }
                                }
                                onWantBounceChanged: bounceStep()
                                Connections {
                                    target: ui
                                    function onTuckedChanged() {
                                        if (ui.tucked) {                       // dock slid away: drop the bounce, it must not poke out
                                            bounceAnim.stop(); settleAnim.stop(); img.lift = 0; cell.bounceShown = false;
                                        } else cell.bounceStep();
                                    }
                                }
                                SequentialAnimation {
                                    id: bounceAnim
                                    NumberAnimation { target: img; property: "lift"; to: root.iconSize * 0.42
                                                      duration: 280; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: img; property: "lift"; to: 0
                                                      duration: 280; easing.type: Easing.InCubic }
                                    onFinished: cell.bounceStep()              // goes again while still launching, otherwise settles
                                }
                                SequentialAnimation {
                                    id: settleAnim
                                    NumberAnimation { target: img; property: "lift"; to: root.iconSize * 0.16
                                                      duration: 170; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: img; property: "lift"; to: 0
                                                      duration: 170; easing.type: Easing.InQuad }
                                    NumberAnimation { target: img; property: "lift"; to: root.iconSize * 0.06
                                                      duration: 120; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: img; property: "lift"; to: 0
                                                      duration: 120; easing.type: Easing.InQuad }
                                    onFinished: cell.bounceStep()              // relaunched while settling: bounce again
                                }

                                // ── hover label ──
                                // macOS Tahoe style: a heavily blurred Liquid Glass bubble with a pointer tail, light / dark with the system
                                // appearance, sized from the Dock (see DockGlassPanel.qml). It is only built while it is shown.
                                // The label is a whole glass bubble (3 canvases, a masked blur capture, a shadow). It used to be built for EVERY icon the
                                // pointer crossed, so a fast sweep over many pinned apps built and tore down a bubble per icon (a hitch each): that was the
                                // "laggy when the mouse moves a bit fast, worse with many apps". It now appears once the pointer rests on an icon for a moment.
                                property bool hoverSettled: false
                                Timer { id: tipDwell; interval: 90; running: ma.containsMouse && !cell.isSep; onTriggered: cell.hoverSettled = true }
                                Connections { target: ma; function onContainsMouseChanged() { if (!ma.containsMouse) cell.hoverSettled = false; } }
                                readonly property bool tipOn: root.showLabels && !cell.isSep && cell.hoverSettled && ma.containsMouse && !ma.pressed && !ui.menuOpen && !ui.dragging
                                Loader {
                                    id: tip
                                    z: 10
                                    opacity: cell.tipOn ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    active: cell.tipOn || opacity > 0
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    // (no explicit width / height: the Loader takes the bubble's size from it)
                                    // the tail's tip sits just above the icon (above the magnified / bouncing icon, too)
                                    y: cell.height - img.height - img.lift - height - Math.round(9 * root.labelK)
                                    sourceComponent: DockGlassPanel {
                                        id: lp
                                        readonly property string title: cell.isSep ? "" : ((cell.modelData.kind === "win" && cell.modelData.tl && cell.modelData.tl.title) ? cell.modelData.tl.title : cell.modelData.name)
                                        // a window cell names its window and, underneath, the app it belongs to
                                        readonly property string sub: (!cell.isSep && cell.modelData.kind === "win" && cell.modelData.name && cell.modelData.name !== title) ? cell.modelData.name : ""
                                        readonly property real fs: Math.max(9, Math.round(13 * k))
                                        backdrop: glassBackdrop.item
                                        live: root.liquidActive && glassBackdrop.item !== null
                                        dark: root.darkMode
                                        k: root.labelK
                                        radius: Math.min(11.7 * k, bodyH / 2)
                                        tailW: 21 * k
                                        tailH: 5.8 * k
                                        tailTipR: 2.4 * k
                                        bodyH: sub !== "" ? 32 * k : 26 * k
                                        width: Math.ceil(Math.max(tt.width, st.visible ? st.width : 0)) + 2 * Math.round(12 * k)

                                        Text {
                                            id: tt
                                            text: lp.title
                                            width: Math.min(implicitWidth, Math.round(320 * lp.k))
                                            elide: Text.ElideRight
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.verticalCenter: parent.top
                                            anchors.verticalCenterOffset: lp.sub !== "" ? 9.2 * lp.k : lp.bodyH / 2 + 0.5 * lp.k
                                            color: lp.dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.86)
                                            font.pixelSize: lp.fs
                                            font.family: root.fontForWeight(Font.Normal, root.fontFamily)
                                        }
                                        Text {
                                            id: st
                                            visible: lp.sub !== ""
                                            text: lp.sub
                                            width: Math.min(implicitWidth, Math.round(320 * lp.k))
                                            elide: Text.ElideRight
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.verticalCenter: parent.top
                                            anchors.verticalCenterOffset: 22.4 * lp.k
                                            color: lp.dark ? Qt.rgba(1, 1, 1, 0.60) : Qt.rgba(0, 0, 0, 0.58)
                                            font.pixelSize: Math.max(8, Math.round(10.2 * lp.k))
                                            font.family: root.fontForWeight(Font.Normal, root.fontFamily)
                                        }
                                    }
                                }

                                MouseArea {
                                    id: ma
                                    visible: !cell.isSep
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: -root.bottomPad
                                    width: cell.width
                                    height: img.height + root.bottomPad
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                    property real pressX: 0

                                    property real pressY: 0
                                    onPressed: mouse => {
                                        if (mouse.button === Qt.LeftButton) {
                                            var pp = ma.mapToItem(ui, mouse.x, mouse.y);
                                            pressX = pp.x; pressY = pp.y;
                                        }
                                    }
                                    onPositionChanged: mouse => {
                                        if (!(pressedButtons & Qt.LeftButton) || cell.isSep) return;
                                        var ap = ma.mapToItem(ui, mouse.x, mouse.y);
                                        // pulled up out of the Dock → tear the icon off (any app icon, pinned or running)
                                        if (ui.tearing) { ui.tearX = ap.x; ui.tearY = ap.y; return; }
                                        if (pressY - ap.y > 56 && (cell.modelData.kind === "app" || cell.modelData.kind === "win") && !cell.modelData.special) {
                                            var home = img.mapToItem(ui, img.width / 2, img.height / 2);
                                            ui.tearX = ap.x; ui.tearY = ap.y;
                                            ui.beginTear(cell.modelData, root.cellIconSrc(cell.modelData), home.x, home.y);
                                            return;
                                        }
                                        if (!cell.canDrag) return;
                                        var ax = ap.x;
                                        if (!ui.dragging) {
                                            if (Math.abs(ax - pressX) < 8) return;
                                            ui.beginDrag(cell.index, cell.modelData.key, pressX, cell.width + root.spacing);
                                        }
                                        if (cell.isDragged) ui.dragUpdate(ax);
                                    }
                                    onReleased: mouse => {
                                        if (ui.tearing) { ui.endTear(); return; }
                                        if (ui.dragging && cell.isDragged) ui.endDrag();
                                    }
                                    onClicked: mouse => {
                                        if (ui.justDragged) return;
                                        if (mouse.button === Qt.RightButton) {
                                            ui.menuCx = cell.mapToItem(ui, cell.width / 2, 0).x;
                                            ui.menuModel = root.menuFor(cell.modelData);
                                            ui.menuCell = cell;
                                            ui.menuItem = cell.modelData;
                                            ui.syncMenu();
                                        } else {
                                            root.activate(cell.modelData, mouse.button === Qt.MiddleButton);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: 50
                    visible: ui.menuOpen
                    enabled: ui.menuOpen
                    acceptedButtons: Qt.AllButtons
                    onPressed: ui.menuItem = null
                }

                // ── right-click menu ──
                // Same Tahoe Liquid Glass bubble as the hover label: blurred, light / dark, pointer tail towards the icon, scaled with the
                // Dock. Rows are 22 pt with capsule highlights, as in macOS 26.
                DockGlassPanel {
                    id: menu
                    z: 60
                    visible: opacity > 0
                    opacity: ui.menuOpen ? 1 : 0
                    scale: ui.menuOpen ? 1 : 0.96
                    transformOrigin: Item.Bottom
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    backdrop: glassBackdrop.item
                    live: root.liquidActive && glassBackdrop.item !== null
                    frozen: ui.menuOpen      // the menu's glass stops updating while it is open
                    dark: root.darkMode
                    k: root.labelK
                    radius: 16 * k
                    tailW: 24 * k
                    tailH: 9 * k
                    tailTipR: 3.6 * k
                    readonly property real pad: Math.round(5 * k)

                    width: ui.menuW
                    bodyH: menuCol.height + 2 * pad
                    x: Math.max(8, Math.min(ui.width - width - 8, ui.menuCx - width / 2))
                    y: ui.menuIconTop >= 0 ? ui.menuIconTop - Math.round(10 * k) - height
                                           : ui.height - root.margin - root.bgHeight - root.iconSize * (root.effMag - 1) - Math.round(10 * k) - height
                    // The tail points at the icon the menu belongs to. Its position along the bubble is locked when the menu opens:
                    // re-evaluating tailX while the menu follows its icon during magnification changed shapeKey on every frame,
                    // repainting all of the bubble's canvases (blurred shadow included) on the CPU and causing severe magnification lag.
                    tailX: ui.menuTailX >= 0 ? ui.menuTailX : width / 2

                    Column {
                        id: menuCol
                        x: menu.pad
                        y: menu.pad
                        width: menu.width - 2 * menu.pad

                        Repeater {
                            model: ui.menuModel

                            delegate: Item {
                                id: mi
                                required property var modelData
                                readonly property bool isSep: modelData.kind === "sep"
                                readonly property bool off: !isSep && modelData.disabled === true
                                readonly property bool armedNow: !isSep && modelData.confirm === true && ui.armed === modelData.label
                                width: menuCol.width
                                height: isSep ? Math.round(11 * menu.k) : Math.round(22 * menu.k)

                                Rectangle {
                                    visible: mi.isSep
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 1
                                    color: menu.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
                                }
                                Rectangle {
                                    visible: !mi.isSep && !mi.off && mia.containsMouse
                                    anchors.fill: parent
                                    radius: Math.round(8 * menu.k)          // softly rounded selection
                                    color: mi.armedNow ? "#FF453A" : root.accent
                                }
                                Text {
                                    visible: !mi.isSep
                                    x: Math.round(11 * menu.k)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 2 * Math.round(11 * menu.k)
                                    elide: Text.ElideRight
                                    text: mi.isSep ? "" : (mi.armedNow ? I18n.tr("Click again to confirm") : I18n.tr(mi.modelData.label))
                                    color: (!mi.isSep && !mi.off && mia.containsMouse) ? "white"
                                         : (mi.off ? (menu.dark ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(0, 0, 0, 0.28))
                                                   : (menu.dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.86)))
                                    font.pixelSize: Math.max(9, Math.round(13 * menu.k))
                                    font.family: root.fontForWeight(Font.Normal, root.fontFamily)
                                }
                                MouseArea {
                                    id: mia
                                    anchors.fill: parent
                                    enabled: !mi.isSep && !mi.off
                                    hoverEnabled: true
                                    onContainsMouseChanged: if (!containsMouse && ui.armed === mi.modelData.label) ui.armed = ""
                                    onClicked: {
                                        if (mi.modelData.confirm === true && ui.armed !== mi.modelData.label) { ui.armed = mi.modelData.label; return; }
                                        var run = mi.modelData.run;
                                        ui.menuItem = null;
                                        if (run) run();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
