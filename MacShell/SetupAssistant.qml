import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "modules"
import "HelloData.js" as HelloData

Scope {
    id: root

    property var hub: null
    property bool active: hub ? (hub.setupChecked && !hub.setupCompleted) : true

    // Step state:
    // 0 = Hello screen
    // 1 = Appearance & Feature Modules Checklist
    // 2 = macOS Wi-Fi Connection
    // 3 = Apple Intelligence & Siri (Optional)
    // 4 = Dependency Check & Asset Installation
    // 5 = Welcome Finish
    property int currentStep: 0
    property real exitScale: 1.0
    property real exitOpacity: 1.0

    // Feature Modules Checklist choices
    property bool darkMode: hub && hub.bar ? hub.bar.darkMode : false
    onDarkModeChanged: root.applyThemeToSystem()
    property bool liquidGlassEnabled: hub && hub.dock ? hub.dock.dockStyle === "liquid" : true
    readonly property bool stageManagerEnabled: true
    property bool wifiManagerEnabled: true
    property bool soundPackEnabled: true
    property bool siriEnabled: false   // Default optional: user can toggle or skip

    // Siri & AI settings
    property string geminiApiKey: ""
    property string keyValidationStatus: "idle" // "idle", "testing", "valid", "invalid"
    property string keyValidationMsg: ""
    property bool liveVoiceStreaming: true
    property string selectedLanguage: "vi-VN"
    property string selectedVoice: "vi-VN-NamMinhNeural"

    // Wi-Fi State
    property bool wifiRadioOn: true
    property string wifiConnectedSsid: ""
    property var wifiNetworks: []
    property bool wifiScanning: false
    property string wifiConnectingSsid: ""
    property string wifiPasswordInput: ""
    property bool wifiShowPasswordDialog: false
    property string wifiErrorMsg: ""
    property bool wifiIsConnecting: false

    // Dependency check state
    property var dependenciesList: [
        { id: "core", name: "Core MacShell UI (Menu Bar, Dock)", category: "core", status: "installed", detail: "Installed", size_mb: 0 },
        { id: "network", name: "macOS Wi-Fi Manager (nmcli)", category: "network", status: "installed", detail: "Installed", size_mb: 0 },
        { id: "audio", name: "Audio Engine & Device Routing", category: "audio", status: "installed", detail: "Installed", size_mb: 0 },
        { id: "sounds", name: "macOS UI Sounds & Chime", category: "sounds", status: "ready", detail: "Ready", size_mb: 2 },
        { id: "fonts", name: "Apple Typography (SF Pro & Open Runde)", category: "fonts", status: "installed", detail: "Synced", size_mb: 0 },
        { id: "python_ai", name: "Apple Intelligence & Siri Engine", category: "ai", status: "skipped", detail: "Skipped", size_mb: 0 }
    ]
    property int totalDownloadMb: 0
    property bool depsChecking: false

    // Download / Setup progress
    property int downloadProgress: 0
    property string downloadTaskName: "Initializing"
    property string downloadSpeed: "Local"
    property string downloadStatusText: "Ready to configure system resources..."
    property bool downloadCompleted: false

    // Apple Hello handwriting animation state
    property int helloWordIndex: 0
    readonly property var helloWords: HelloData.words
    readonly property var currentHelloWord: (helloWords && helloWords.length > 0) ? helloWords[helloWordIndex] : null
    property real strokeDrawProgress: 0.0
    property real helloOpacity: 1.0
    property real helloZoomScale: 1.0
    property bool isTransitioningToCard: false

    // Camera Drift & Breathing
    property real cameraScale: 1.0
    property real cameraAngle: 0.0

    // Macro Tracking Shot (Active ONLY for the first word: "hello")
    readonly property bool isFirstHello: (root.helloWordIndex === 0)
    // Macro progress advances along the stroke drawing up to 90%
    readonly property real macroProgress: isFirstHello ? Math.min(root.strokeDrawProgress / 0.90, 1.0) : 1.0
    // Starts at scale 2.50x close-up, smoothly glides out to 1.0x using InOutCubic curve
    readonly property real macroZoomScale: {
        if (!isFirstHello) return 1.0;
        var t = 1.0 - macroProgress;
        var ease = t < 0.5 ? 4.0 * t * t * t : 1.0 - Math.pow(-2.0 * t + 2.0, 3) / 2.0;
        return 1.0 + 1.50 * ease; // 2.5x at start -> 1.0x at end
    }

    // Focus center on the initial touch point of the pen
    readonly property real targetPanX: {
        var w = currentHelloWord;
        if (!w || !w.start_point) return 0.0;
        var halfW = (w.width || 540) / 2.0;
        return -(w.start_point[0] - halfW);
    }
    readonly property real targetPanY: {
        var w = currentHelloWord;
        if (!w || !w.start_point) return 0.0;
        var halfH = (w.height || 180) / 2.0;
        return -(w.start_point[1] - halfH);
    }

    readonly property real cameraPanX: isFirstHello ? (targetPanX * Math.pow(1.0 - macroProgress, 2.0)) : 0.0
    readonly property real cameraPanY: isFirstHello ? (targetPanY * Math.pow(1.0 - macroProgress, 2.0)) : 0.0

    // Region & Language
    property string selectedCountry: "United States"
    property var countriesList: [
        { name: "United States", flag: "🇺🇸", lang: "English", code: "en-US", voice: "en-US-JennyNeural" },
        { name: "Vietnam", flag: "🇻🇳", lang: "Tiếng Việt", code: "vi-VN", voice: "vi-VN-NamMinhNeural" },
        { name: "United Kingdom", flag: "🇬🇧", lang: "English", code: "en-GB", voice: "en-US-JennyNeural" },
        { name: "Japan", flag: "🇯🇵", lang: "日本語", code: "ja-JP", voice: "ja-JP-NanamiNeural" },
        { name: "France", flag: "🇫🇷", lang: "Français", code: "fr-FR", voice: "fr-FR-DeniseNeural" },
        { name: "Germany", flag: "🇩🇪", lang: "Deutsch", code: "de-DE", voice: "de-DE-KatjaNeural" },
        { name: "Spain", flag: "🇪🇸", lang: "Español", code: "es-ES", voice: "es-ES-ElviraNeural" }
    ]

    function proceedFromHello() {
        if (root.currentStep !== 0 || root.isTransitioningToCard) return;
        root.isTransitioningToCard = true;
        root.playSound("pop");
        transitionToCardAnim.restart();
    }

    // Python executable & worker script resolver (handles standalone bootstrap or normal shell)
    readonly property string workerScript: {
        var u = Qt.resolvedUrl("scripts/setup_assistant_worker.py").toString().replace(/^file:\/\//, "");
        return u;
    }

    // Load initial Gemini Key if already configured
    FileView {
        id: geminiConfigInit
        path: Quickshell.env("HOME") + "/.config/macshell/gemini_config.json"
        printErrors: false
        onLoaded: {
            try {
                var o = JSON.parse(text());
                if (o.api_key && o.api_key !== "" && o.api_key.indexOf("YOUR_") === -1) {
                    root.geminiApiKey = o.api_key;
                }
            } catch (e) {}
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Background Processes
    // ═════════════════════════════════════════════════════════════════════════

    // 1. Gemini Key Validation
    Process {
        id: keyTestProc
        stdout: StdioCollector {
            onStreamFinished: {
                var line = text.trim();
                if (line.indexOf("RESULT:VALID") !== -1) {
                    var parts = line.split(":");
                    var model = parts.length > 2 ? parts[2] : "gemini-2.5-flash";
                    root.keyValidationStatus = "valid";
                    root.keyValidationMsg = "✓ Valid API Key (" + model + ")";
                    root.playSound("tink");
                } else if (line.indexOf("RESULT:INVALID") !== -1) {
                    var msg = line.substring("RESULT:INVALID:".length);
                    root.keyValidationStatus = "invalid";
                    root.keyValidationMsg = "✕ " + msg;
                    root.playSound("pop");
                } else {
                    root.keyValidationStatus = "invalid";
                    root.keyValidationMsg = "✕ Unable to verify API Key";
                }
            }
        }
    }

    function testKey() {
        if (!root.geminiApiKey || root.geminiApiKey.trim() === "") {
            root.keyValidationStatus = "invalid";
            root.keyValidationMsg = "✕ Please enter a Gemini API Key";
            return;
        }
        root.keyValidationStatus = "testing";
        root.keyValidationMsg = "Testing API connection...";
        keyTestProc.command = ["python3", root.workerScript, "test_gemini_key", root.geminiApiKey.trim()];
        keyTestProc.running = true;
    }

    // 2. Wi-Fi Status & Scanner Processes
    Process {
        id: wifiStatusProc
        command: ["python3", root.workerScript, "wifi_status"]
        stdout: StdioCollector {
            onStreamFinished: {
                var line = text.trim();
                if (line.indexOf("WIFI_STATUS:") === 0) {
                    try {
                        var o = JSON.parse(line.substring("WIFI_STATUS:".length));
                        root.wifiRadioOn = o.enabled;
                        root.wifiConnectedSsid = o.connected_ssid || "";
                    } catch (e) {}
                }
            }
        }
    }

    Process {
        id: wifiScanProc
        command: ["python3", root.workerScript, "wifi_scan"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiScanning = false;
                var line = text.trim();
                if (line.indexOf("WIFI_LIST:") === 0) {
                    try {
                        var arr = JSON.parse(line.substring("WIFI_LIST:".length));
                        root.wifiNetworks = arr;
                    } catch (e) {}
                }
            }
        }
        onExited: { root.wifiScanning = false; }
    }

    Process {
        id: wifiToggleProc
        stdout: StdioCollector {
            onStreamFinished: {
                wifiStatusProc.running = true;
                if (root.wifiRadioOn) scanWifiNetworks();
            }
        }
    }

    Process {
        id: wifiConnectProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiIsConnecting = false;
                var line = text.trim();
                if (line.indexOf("WIFI_CONNECT:SUCCESS") === 0) {
                    root.wifiConnectedSsid = root.wifiConnectingSsid;
                    root.wifiShowPasswordDialog = false;
                    root.wifiPasswordInput = "";
                    root.wifiErrorMsg = "";
                    root.playSound("tink");
                    scanWifiNetworks();
                } else if (line.indexOf("WIFI_CONNECT:ERROR:") === 0) {
                    root.wifiErrorMsg = line.substring("WIFI_CONNECT:ERROR:".length);
                    root.playSound("pop");
                }
            }
        }
        onExited: { root.wifiIsConnecting = false; }
    }

    function scanWifiNetworks() {
        if (!root.wifiScanning && root.wifiRadioOn) {
            root.wifiScanning = true;
            wifiScanProc.running = true;
            wifiStatusProc.running = true;
        }
    }

    function toggleWifiRadio(on) {
        root.wifiRadioOn = on;
        wifiToggleProc.command = ["python3", root.workerScript, "wifi_toggle", on ? "on" : "off"];
        wifiToggleProc.running = true;
    }

    function connectWifi(ssid, password) {
        root.wifiIsConnecting = true;
        root.wifiErrorMsg = "";
        wifiConnectProc.command = ["python3", root.workerScript, "wifi_connect", ssid, password || ""];
        wifiConnectProc.running = true;
    }

    // 3. Dependency Check Process
    Process {
        id: depsCheckProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.depsChecking = false;
                var line = text.trim();
                if (line.indexOf("DEPS_CHECK:") === 0) {
                    try {
                        var o = JSON.parse(line.substring("DEPS_CHECK:".length));
                        root.dependenciesList = o.dependencies || [];
                        root.totalDownloadMb = o.total_download_mb || 0;
                    } catch (e) {}
                }
            }
        }
        onExited: { root.depsChecking = false; }
    }

    function runDepsCheck() {
        root.depsChecking = true;
        var opts = {
            siri: root.siriEnabled,
            sound_pack: root.soundPackEnabled,
            wifi_manager: root.wifiManagerEnabled,
            stage_manager: root.stageManagerEnabled
        };
        depsCheckProc.command = ["python3", root.workerScript, "check_dependencies", JSON.stringify(opts)];
        depsCheckProc.running = true;
    }

    // 4. Resource Setup & Installation Process
    Process {
        id: resourceSetupProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                var line = data.trim();
                if (line.indexOf("PROGRESS:") === 0) {
                    var parts = line.split(":");
                    if (parts.length >= 5) {
                        var pct = parseInt(parts[1], 10);
                        root.downloadProgress = isNaN(pct) ? root.downloadProgress : pct;
                        root.downloadTaskName = parts[2];
                        root.downloadSpeed = parts[3];
                        root.downloadStatusText = parts.slice(4).join(":");
                    } else if (parts.length >= 3) {
                        var pct2 = parseInt(parts[1], 10);
                        root.downloadProgress = isNaN(pct2) ? root.downloadProgress : pct2;
                        root.downloadStatusText = parts.slice(2).join(":");
                    }
                } else if (line.indexOf("STATUS:SUCCESS") !== -1) {
                    root.downloadProgress = 100;
                    root.downloadCompleted = true;
                    root.downloadStatusText = "System resources configured successfully!";
                    root.playSound("tink");
                }
            }
        }
        onExited: {
            if (!root.downloadCompleted) {
                root.downloadProgress = 100;
                root.downloadCompleted = true;
                root.downloadStatusText = "Resources are ready!";
            }
        }
    }

    function startResourceSetup() {
        if (!resourceSetupProc.running && !root.downloadCompleted) {
            root.downloadProgress = 5;
            root.downloadStatusText = "Initializing resource installation...";
            var opts = {
                siri: root.siriEnabled,
                sound_pack: root.soundPackEnabled,
                wifi_manager: root.wifiManagerEnabled,
                stage_manager: root.stageManagerEnabled,
                dark_mode: root.darkMode,
                liquid_glass: root.liquidGlassEnabled,
                gemini_api_key: root.geminiApiKey,
                live_voice_streaming: root.liveVoiceStreaming,
                tts_voice: root.selectedVoice,
                tts_language: root.selectedLanguage
            };
            resourceSetupProc.command = ["python3", root.workerScript, "run_setup", JSON.stringify(opts)];
            resourceSetupProc.running = true;
        }
    }

    // 5. Completion Process
    Process {
        id: completeProc
        command: ["python3", root.workerScript, "complete_setup"]
        onExited: {
            if (root.hub) root.hub.setupCompleted = true;
        }
    }

    function applyThemeToSystem() {
        var wpPath = root.darkMode ? (Quickshell.env("HOME") + "/.config/quickshell/MacShell/assets/wallpapers/tahoe_dark.jpg")
                                   : (Quickshell.env("HOME") + "/.config/quickshell/MacShell/assets/wallpapers/tahoe_light.jpg");
        var iconTheme = root.darkMode ? "MacOS-Like-Dark" : "MacOS-Like-Light";

        // 1. Immediately apply to the desktop background via awww / swww
        Quickshell.execDetached(["sh", "-c", "if command -v awww >/dev/null 2>&1; then awww img '" + wpPath + "' --transition-type fade --transition-duration 0.7; elif command -v swww >/dev/null 2>&1; then swww img '" + wpPath + "' --transition-type fade --transition-duration 0.7; fi"]);

        // 2. Set GTK/GNOME appearance
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", root.darkMode ? "prefer-dark" : "prefer-light"]);
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", iconTheme]);

        // 3. Update MacBar / MacDock if running live
        if (root.hub && root.hub.bar) {
            root.hub.bar.darkMode = root.darkMode;
            root.hub.bar.wpPairLight = Quickshell.env("HOME") + "/.config/quickshell/MacShell/assets/wallpapers/tahoe_light.jpg";
            root.hub.bar.wpPairDark = Quickshell.env("HOME") + "/.config/quickshell/MacShell/assets/wallpapers/tahoe_dark.jpg";
            root.hub.bar.wallpaperAppearance = "auto";
            root.hub.bar.wpApplyAppearance();
        }
        if (root.hub && root.hub.dock) {
            root.hub.dock.darkMode = root.darkMode;
        }

        // 4. Update settings.json files on disk
        var pyCmd = "import json, os\n" +
                    "p = os.path.expanduser('~/.config/macbar/settings.json')\n" +
                    "if os.path.exists(p):\n" +
                    "    with open(p) as f: d = json.load(f)\n" +
                    "    d['darkMode'] = " + (root.darkMode ? "True" : "False") + "\n" +
                    "    d['appearanceMode'] = '" + (root.darkMode ? "dark" : "light") + "'\n" +
                    "    d['wallpaperPath'] = '" + wpPath + "'\n" +
                    "    d['wpRestorePath'] = '" + wpPath + "'\n" +
                    "    d['wpPairLight'] = os.path.expanduser('~/.config/quickshell/MacShell/assets/wallpapers/tahoe_light.jpg')\n" +
                    "    d['wpPairDark'] = os.path.expanduser('~/.config/quickshell/MacShell/assets/wallpapers/tahoe_dark.jpg')\n" +
                    "    d['wallpaperAppearance'] = 'auto'\n" +
                    "    with open(p, 'w') as f: json.dump(d, f, indent=2)\n";
        Quickshell.execDetached(["python3", "-c", pyCmd]);
    }

    function saveAppearance() {
        applyThemeToSystem();
        if (root.hub && root.hub.bar) {
            root.hub.bar.darkMode = root.darkMode;
            root.hub.bar.stageManager = root.stageManagerEnabled;
        }
        if (root.hub && root.hub.dock) {
            root.hub.dock.darkMode = root.darkMode;
            root.hub.dock.dockStyle = root.liquidGlassEnabled ? "liquid" : "blur";
        }
    }

    function playSound(name) {
        if (!root.soundPackEnabled) return;
        if (root.hub && root.hub.bar && typeof root.hub.bar.playSound === "function") {
            root.hub.bar.playSound(name);
            return;
        }
        var path = Quickshell.env("HOME") + "/.local/share/sounds/macshell/" + name + ".wav";
        Quickshell.execDetached(["pw-play", path]);
    }

    function playStartupChime() {
        if (!root.soundPackEnabled) return;
        var chime = Quickshell.env("HOME") + "/.local/share/sounds/macshell/chime.wav";
        Quickshell.execDetached(["pw-play", chime]);
    }

    function finishSetup() {
        saveAppearance();
        playStartupChime();
        completeProc.running = true;

        // If running standalone in bootstrap mode (!root.hub), launch MacShell and clean up
        if (!root.hub) {
            Quickshell.execDetached(["sh", "-c", "sleep 0.8; qs -c MacShell &"]);
            Quickshell.execDetached(["sh", "-c", "sleep 3.0; rm -rf ~/.cache/macshell-bootstrap"]);
            Qt.callLater(function() {
                Qt.quit();
            });
            return;
        }

        exitAnim.restart();
    }

    // Navigation logic with dynamic step skipping
    function goNext() {
        root.playSound("pop");
        if (currentStep === 0) {
            proceedFromHello();
            return;
        } else if (currentStep === 1) {
            if (root.wifiManagerEnabled) {
                currentStep = 2;
                scanWifiNetworks();
            } else if (root.siriEnabled) {
                currentStep = 3;
            } else {
                currentStep = 4;
                runDepsCheck();
            }
        } else if (currentStep === 2) {
            if (root.siriEnabled) {
                currentStep = 3;
            } else {
                currentStep = 4;
                runDepsCheck();
            }
        } else if (currentStep === 3) {
            currentStep = 4;
            runDepsCheck();
        } else if (currentStep === 4) {
            if (!root.downloadCompleted) {
                startResourceSetup();
            } else {
                currentStep = 5;
            }
        } else if (currentStep === 5) {
            finishSetup();
        }
    }

    function goBack() {
        root.playSound("pop");
        if (currentStep === 2) {
            currentStep = 1;
        } else if (currentStep === 3) {
            if (root.wifiManagerEnabled) currentStep = 2;
            else currentStep = 1;
        } else if (currentStep === 4) {
            if (root.siriEnabled) currentStep = 3;
            else if (root.wifiManagerEnabled) currentStep = 2;
            else currentStep = 1;
        } else if (currentStep === 5) {
            currentStep = 4;
        }
    }

    // Exit zoom-out and fade animation
    ParallelAnimation {
        id: exitAnim
        running: false

        NumberAnimation {
            target: root
            property: "exitScale"
            to: 1.08
            duration: 550
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root
            property: "exitOpacity"
            to: 0.0
            duration: 500
            easing.type: Easing.OutCubic
        }
        onFinished: {
            root.active = false;
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Apple Single-Stroke Handwriting Animation Loop
    // Draw: 2800ms · Hold: 1400ms · Dissolve: 500ms
    // ═════════════════════════════════════════════════════════════════════════
    SequentialAnimation {
        id: handwritingAnim
        running: root.active && root.currentStep === 0 && !root.isTransitioningToCard
        loops: Animation.Infinite

        PropertyAction { target: root; property: "strokeDrawProgress"; value: 0.0 }
        PropertyAction { target: root; property: "helloOpacity"; value: 1.0 }
        PropertyAction { target: root; property: "helloZoomScale"; value: 1.0 }

        // 1. Draw strokes continuously from left to right (2800ms)
        NumberAnimation {
            target: root
            property: "strokeDrawProgress"
            from: 0.0
            to: 1.0
            duration: root.isFirstHello ? 2800 : 2200
            easing.type: Easing.InOutSine
        }

        // 2. Pause / Hold for reading (1400ms)
        PauseAnimation { duration: 1400 }

        // 3. Smooth Dissolve / Cross-fade Out (500ms)
        NumberAnimation {
            target: root
            property: "helloOpacity"
            to: 0.0
            duration: 500
            easing.type: Easing.InOutCubic
        }

        PauseAnimation { duration: 120 }

        ScriptAction {
            script: {
                if (root.helloWords && root.helloWords.length > 0) {
                    root.helloWordIndex = (root.helloWordIndex + 1) % root.helloWords.length;
                }
            }
        }
    }

    // ── Camera Drift & Breathing (Scale 1.0 -> 1.045, Rotation -0.8° -> 0.8°) ──
    SequentialAnimation {
        id: cameraBreathingAnim
        running: root.active && root.currentStep === 0 && !root.isTransitioningToCard
        loops: Animation.Infinite

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "cameraScale"
                from: 1.0
                to: 1.045
                duration: 5500
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: root
                property: "cameraAngle"
                from: -0.7
                to: 0.7
                duration: 5500
                easing.type: Easing.InOutSine
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "cameraScale"
                from: 1.045
                to: 1.0
                duration: 5500
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: root
                property: "cameraAngle"
                from: 0.7
                to: -0.7
                duration: 5500
                easing.type: Easing.InOutSine
            }
        }
    }

    // ── Transition: Zoom handwriting out & Glide Setup Card from bottom ──
    ParallelAnimation {
        id: transitionToCardAnim

        NumberAnimation {
            target: root
            property: "helloZoomScale"
            from: 1.0
            to: 1.15
            duration: 500
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: root
            property: "helloOpacity"
            to: 0.0
            duration: 500
            easing.type: Easing.OutCubic
        }

        onFinished: {
            root.currentStep = 1;
            root.isTransitioningToCard = false;
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // IPC Interface
    // ═════════════════════════════════════════════════════════════════════════
    IpcHandler {
        target: "setup"
        function start(): void {
            root.currentStep = 0;
            root.exitScale = 1.0;
            root.exitOpacity = 1.0;
            root.active = true;
        }
        function step(n: int): void {
            root.currentStep = n;
            root.active = true;
            if (n === 2) scanWifiNetworks();
            else if (n === 4) runDepsCheck();
        }
        function next(): void { root.goNext(); }
        function back(): void { root.goBack(); }
        function word(n: int): void {
            root.helloWordIndex = n;
            root.strokeDrawProgress = 0.0;
            root.helloOpacity = 1.0;
        }
        function dark(enable: bool): void {
            root.darkMode = enable;
        }
        function close(): void { root.active = false; }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // UI Layout: Layer-Shell Window
    // ═════════════════════════════════════════════════════════════════════════
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: setupWin
            required property var modelData
            screen: modelData

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "macsetup"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            visible: root.active && root.exitOpacity > 0.0

            Item {
                id: mainContainer
                anchors.fill: parent
                scale: root.exitScale
                opacity: root.exitOpacity
                focus: true

                Keys.onSpacePressed: root.proceedFromHello()
                Keys.onReturnPressed: root.proceedFromHello()
                Keys.onEnterPressed: root.proceedFromHello()

                // ─────────────────────────────────────────────────────────────
                // Background: Official macOS Tahoe 26 Blue Ribbon Wallpaper
                // ─────────────────────────────────────────────────────────────
                Item {
                    id: wallpaperContainer
                    anchors.fill: parent
                    clip: true

                    Item {
                        id: wallpaperDrifter
                        anchors.fill: parent
                        scale: 1.08 // Slightly enlarged for seamless subtle parallax drifting

                        property real driftT: 0.0

                        transform: Translate {
                            x: Math.sin(wallpaperDrifter.driftT * 0.35) * 22
                            y: Math.cos(wallpaperDrifter.driftT * 0.28) * 14
                        }

                        FrameAnimation {
                            running: root.active
                            onTriggered: {
                                wallpaperDrifter.driftT += 0.005;
                            }
                        }

                        // Light mode wallpaper
                        Image {
                            id: tahoeLightImg
                            anchors.fill: parent
                            source: Qt.resolvedUrl("assets/wallpapers/tahoe_light.jpg")
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            mipmap: true
                            opacity: root.darkMode ? 0.0 : 1.0
                            Behavior on opacity {
                                NumberAnimation { duration: 500; easing.type: Easing.InOutCubic }
                            }
                        }

                        // Dark mode wallpaper
                        Image {
                            id: tahoeDarkImg
                            anchors.fill: parent
                            source: Qt.resolvedUrl("assets/wallpapers/tahoe_dark.jpg")
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            mipmap: true
                            opacity: root.darkMode ? 1.0 : 0.0
                            Behavior on opacity {
                                NumberAnimation { duration: 500; easing.type: Easing.InOutCubic }
                            }
                        }
                    }

                    // Delicate ambient lighting vignette for authentic depth
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0.0, 0.04, 0.12, 0.08) }
                            GradientStop { position: 0.5; color: Qt.rgba(0.0, 0.0, 0.0, 0.0) }
                            GradientStop { position: 1.0; color: Qt.rgba(0.0, 0.03, 0.10, 0.22) }
                        }
                    }
                }


                // ─────────────────────────────────────────────────────────────
                // SCREEN 0: Apple Single-Stroke Handwriting Screen
                // ─────────────────────────────────────────────────────────────
                Item {
                    id: screen0
                    anchors.fill: parent
                    visible: root.currentStep === 0 || root.isTransitioningToCard

                    // Click anywhere to proceed
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.proceedFromHello()
                    }

                    Item {
                        id: helloContainer
                        anchors.centerIn: parent
                        width: (root.currentHelloWord && root.currentHelloWord.width) ? root.currentHelloWord.width : 540
                        height: (root.currentHelloWord && root.currentHelloWord.height) ? root.currentHelloWord.height : 180
                        opacity: root.helloOpacity
                        scale: root.helloZoomScale * root.macroZoomScale * root.cameraScale
                        rotation: root.cameraAngle
                        transform: Translate {
                            x: root.cameraPanX
                            y: root.cameraPanY
                        }

                        // ── Apple Iconic White Handwriting Script ──
                        Item {
                            id: whiteStrokeBox
                            anchors.fill: parent

                            Repeater {
                                model: (root.currentHelloWord && root.currentHelloWord.strokes) ? root.currentHelloWord.strokes : []

                                delegate: Shape {
                                    id: strokeShape
                                    required property var modelData
                                    required property int index

                                    anchors.fill: parent
                                    preferredRendererType: Shape.CurveRenderer

                                    readonly property real startPct: (modelData && modelData.start_pct !== undefined) ? modelData.start_pct : 0.0
                                    readonly property real endPct: (modelData && modelData.end_pct !== undefined) ? modelData.end_pct : 1.0
                                    readonly property bool isDot: (modelData && modelData.length !== undefined && modelData.length < 2.0)

                                    readonly property real localProgress: {
                                        var g = root.strokeDrawProgress;
                                        if (g <= startPct) return 0.0;
                                        if (g >= endPct) return 1.0;
                                        return (g - startPct) / Math.max(endPct - startPct, 0.0001);
                                    }

                                    readonly property real drawEnd: isDot ? (localProgress >= 0.5 ? 1.0 : 0.0) : localProgress

                                    ShapePath {
                                        strokeColor: "#ffffff"
                                        strokeWidth: 18.0
                                        fillColor: "transparent"
                                        capStyle: ShapePath.RoundCap
                                        joinStyle: ShapePath.RoundJoin
                                        trim.start: 0.0
                                        trim.end: strokeShape.drawEnd
                                        PathSvg { path: strokeShape.modelData.d }
                                    }
                                }
                            }

                            // Subtle depth lift to make white strokes pop over both light and dark ribbons
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: "#35000000"
                                shadowBlur: 0.40
                                shadowVerticalOffset: 4
                            }
                        }

                        // ── Glowing Pen Tip Point ──
                        Item {
                            id: penTip
                            readonly property var tipInfo: {
                                var w = root.currentHelloWord;
                                var g = root.strokeDrawProgress;
                                if (!w || !w.tip_samples || w.tip_samples.length === 0) return { x: 0, y: 0, visible: false };
                                if (g <= 0.001 || g >= 0.990) return { x: 0, y: 0, visible: false };
                                var samples = w.tip_samples;
                                var idx = g * (samples.length - 1);
                                var i0 = Math.floor(idx);
                                var i1 = Math.min(i0 + 1, samples.length - 1);
                                var f = idx - i0;

                                // If pen is lifted in the air between strokes, hide the tip immediately
                                if (samples[i0].length >= 3 && samples[i0][2] === 0) {
                                    return { x: 0, y: 0, visible: false };
                                }

                                return {
                                    x: samples[i0][0] * (1.0 - f) + samples[i1][0] * f,
                                    y: samples[i0][1] * (1.0 - f) + samples[i1][1] * f,
                                    visible: true
                                };
                            }

                            x: tipInfo.x - width / 2
                            y: tipInfo.y - height / 2
                            width: 32
                            height: 32
                            opacity: (tipInfo.visible && root.helloOpacity > 0.05 && root.currentStep === 0 && !root.isTransitioningToCard) ? 1.0 : 0.0
                            visible: opacity > 0.001

                            Behavior on opacity {
                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }

                            // Outer soft luminous bloom
                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: 13
                                color: Qt.rgba(0.55, 0.85, 1.0, 0.45)
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    blurEnabled: true
                                    blurMax: 10
                                    blur: 0.95
                                }
                            }

                            // Liquid glass spherical bead body
                            Rectangle {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                radius: 8
                                color: Qt.rgba(0.85, 0.95, 1.0, 0.70)
                                border.width: 1
                                border.color: "#ffffff"
                            }

                            // Core specular gloss bead point
                            Rectangle {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: -1.5
                                anchors.verticalCenterOffset: -1.5
                                width: 7.0
                                height: 7.0
                                radius: 3.5
                                color: "#ffffff"
                            }
                        }
                    }

                    // Pulsating subtle hint at screen bottom
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 60
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Click anywhere or press Space to set up"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.family: "Open Runde"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        opacity: 0.5 + 0.3 * Math.sin(root.cameraAngle * 5.0)
                    }
                }

                // ─────────────────────────────────────────────────────────────
                // SCREENS 1 - 5: Authentic Two-Column macOS Setup Card
                // ─────────────────────────────────────────────────────────────
                Rectangle {
                    id: setupCard
                    anchors.centerIn: parent
                    width: Math.min(Math.max(parent.width * 0.55, 920), 1060)
                    height: 580
                    radius: 28

                    property real cardScale: (root.currentStep === 0) ? 0.92 : 1.0
                    property real cardYOffset: (root.currentStep === 0) ? 120 : 0

                    scale: cardScale
                    transform: Translate { y: setupCard.cardYOffset }
                    opacity: (root.currentStep === 0) ? 0.0 : 1.0
                    visible: opacity > 0.001

                    Behavior on cardScale {
                        NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
                    }
                    Behavior on cardYOffset {
                        NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.08 }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                    }

                    // Pure Full Liquid Glass Material - Single Unified Sheet
                    color: "#25181824"
                    border.width: 1
                    border.color: "#35ffffff"

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#70000000"
                        shadowBlur: 0.95
                        shadowVerticalOffset: 24
                    }

                    // All-around specular highlight rim
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.width: 1
                        border.color: "#35ffffff"
                    }

                    // Soft specular sheen across the whole top rim (100% width)
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 100
                        radius: parent.radius
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                            GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.02) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    // ═════════════════════════════════════════════════════════
                                        // ═════════════════════════════════════════════════════════
                    // Authentic Apple Single-Column Setup Layout
                    // ═════════════════════════════════════════════════════════

                    // ── 1. Top Center Hero Section ──
                    Item {
                        id: heroSection
                        anchors.top: parent.top
                        anchors.topMargin: 36
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 72
                        height: 72

                        // Step 1: Apple Globe on Solid Blue Circle (Image 1 & 2)
                        Rectangle {
                            anchors.fill: parent
                            radius: 36
                            visible: root.currentStep === 1
                            color: "#007aff"

                            Canvas {
                                anchors.centerIn: parent
                                width: 44; height: 44
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.reset();
                                    var cx = width / 2;
                                    var cy = height / 2;
                                    var r = 19;
                                    ctx.strokeStyle = "#ffffff";
                                    ctx.lineWidth = 2.2;

                                    // Outer Sphere
                                    ctx.beginPath();
                                    ctx.arc(cx, cy, r, 0, Math.PI * 2);
                                    ctx.stroke();

                                    // Equator
                                    ctx.beginPath();
                                    ctx.moveTo(cx - r, cy);
                                    ctx.lineTo(cx + r, cy);
                                    ctx.stroke();

                                    // Prime Meridian
                                    ctx.beginPath();
                                    ctx.moveTo(cx, cy - r);
                                    ctx.lineTo(cx, cy + r);
                                    ctx.stroke();

                                    // Longitude Curvatures
                                    ctx.lineWidth = 1.8;
                                    ctx.beginPath();
                                    ctx.ellipse(cx - 9.5, cy - r, 19, r * 2);
                                    ctx.stroke();

                                    // Latitude Arcs
                                    ctx.lineWidth = 1.4;
                                    ctx.beginPath();
                                    ctx.arc(cx, cy - 24, 26, Math.PI * 0.35, Math.PI * 0.65, false);
                                    ctx.stroke();
                                    ctx.beginPath();
                                    ctx.arc(cx, cy + 24, 26, -Math.PI * 0.65, -Math.PI * 0.35, false);
                                    ctx.stroke();
                                }
                            }
                        }

                        // Step 2: Apple Wi-Fi Glyph with Animated Radar Waves (User Request!)
                        Item {
                            anchors.fill: parent
                            visible: root.currentStep === 2

                            // Concentric Radar Wave 1 (Expanding & Fading)
                            Rectangle {
                                anchors.centerIn: parent
                                width: 68; height: 68; radius: 34
                                color: "transparent"
                                border.width: 1.8
                                border.color: "#38bdf8"
                                opacity: 0.0
                                scale: 1.0

                                SequentialAnimation on scale {
                                    loops: Animation.Infinite
                                    running: root.currentStep === 2
                                    NumberAnimation { from: 1.0; to: 2.4; duration: 2000; easing.type: Easing.OutCubic }
                                    PauseAnimation { duration: 150 }
                                }
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    running: root.currentStep === 2
                                    NumberAnimation { from: 0.75; to: 0.0; duration: 2000; easing.type: Easing.OutCubic }
                                    PauseAnimation { duration: 150 }
                                }
                            }

                            // Concentric Radar Wave 2 (Delayed by 900ms)
                            Rectangle {
                                anchors.centerIn: parent
                                width: 68; height: 68; radius: 34
                                color: "transparent"
                                border.width: 1.8
                                border.color: "#60a5fa"
                                opacity: 0.0
                                scale: 1.0

                                SequentialAnimation on scale {
                                    loops: Animation.Infinite
                                    running: root.currentStep === 2
                                    PauseAnimation { duration: 900 }
                                    NumberAnimation { from: 1.0; to: 2.4; duration: 2000; easing.type: Easing.OutCubic }
                                }
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    running: root.currentStep === 2
                                    PauseAnimation { duration: 900 }
                                    NumberAnimation { from: 0.75; to: 0.0; duration: 2000; easing.type: Easing.OutCubic }
                                }
                            }

                            // Main Wi-Fi Frosted Disc
                            Rectangle {
                                anchors.fill: parent
                                radius: 36
                                color: "#007aff"
                                border.width: 1
                                border.color: "#40ffffff"

                                Canvas {
                                    anchors.centerIn: parent
                                    width: 42; height: 42
                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.reset();
                                        var cx = width / 2;
                                        var cy = height * 0.88;
                                        ctx.strokeStyle = "#ffffff";
                                        ctx.lineCap = "round";

                                        // Arc 3 (Outer)
                                        ctx.beginPath();
                                        ctx.arc(cx, cy, 25, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                        ctx.lineWidth = 3.6;
                                        ctx.stroke();

                                        // Arc 2 (Middle)
                                        ctx.beginPath();
                                        ctx.arc(cx, cy, 16.5, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                        ctx.lineWidth = 3.2;
                                        ctx.stroke();

                                        // Arc 1 (Inner)
                                        ctx.beginPath();
                                        ctx.arc(cx, cy, 8.5, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                        ctx.lineWidth = 2.8;
                                        ctx.stroke();

                                        // Dot
                                        ctx.beginPath();
                                        ctx.arc(cx, cy - 0.5, 2.8, 0, Math.PI * 2);
                                        ctx.fillStyle = "#ffffff";
                                        ctx.fill();
                                    }
                                }
                            }
                        }

                        // Step 3: Apple Siri Glowing Orb (Image 4 & 5)
                        Item {
                            anchors.fill: parent
                            visible: root.currentStep === 3
                            SiriOrb {
                                anchors.fill: parent
                                active: root.currentStep === 3
                                isProcessing: true
                            }
                        }

                        // Step 4: System Setup / Display Disc
                        Rectangle {
                            anchors.fill: parent
                            radius: 36
                            visible: root.currentStep === 4
                            color: Qt.rgba(0, 122, 255, 0.20)
                            border.width: 1
                            border.color: "#35ffffff"

                            Text {
                                anchors.centerIn: parent
                                text: "⚙️"
                                font.pixelSize: 32
                            }
                        }

                        // Step 5: Pure Apple White Logo on Frosted Disc
                        Rectangle {
                            anchors.fill: parent
                            radius: 36
                            visible: root.currentStep === 5
                            color: Qt.rgba(255, 255, 255, 0.16)
                            border.width: 1
                            border.color: "#35ffffff"

                            Image {
                                anchors.centerIn: parent
                                width: 40; height: 40
                                sourceSize: Qt.size(64, 64)
                                source: "apple-logo-white.svg"
                            }
                        }
                    }

                    // ── 2. Centered Bold Title ──
                    Text {
                        id: stepTitle
                        anchors.top: heroSection.bottom
                        anchors.topMargin: 16
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.family: "Open Runde"
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                        color: "#ffffff"
                        text: {
                            switch (root.currentStep) {
                                case 1: return "Select Your Country or Region";
                                case 2: return "Select a Wi-Fi Network";
                                case 3: return "Siri";
                                case 4: return "Setting Up Your Mac";
                                case 5: return "Welcome to MacShell";
                                default: return "MacShell Setup";
                            }
                        }
                    }

                    // ── 3. Centered Subtitle / Description ──
                    Text {
                        id: stepSubtitle
                        anchors.top: stepTitle.bottom
                        anchors.topMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width - 80, 520)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        font.family: "Open Runde"
                        font.pixelSize: 13
                        lineHeight: 1.35
                        color: Qt.rgba(1, 1, 1, 0.70)
                        text: {
                            switch (root.currentStep) {
                                case 1: return "Select your country or region to configure language and regional formats.";
                                case 2: return "Choose a wireless network to connect to the internet, sync widgets, and download resources.";
                                case 3: return "Siri helps you get things done just by asking. Siri can also make suggestions before you ask in apps, search, and keyboards.";
                                case 4: return "Configuring system resources, typography fonts, audio engine, and macOS Tahoe theme...";
                                case 5: return "Your macOS desktop environment is ready.";
                                default: return "";
                            }
                        }
                    }

                    // ── 4. Main Centered Interactive Content Area ──
                    Item {
                        id: stepContentArea
                        anchors.top: stepSubtitle.bottom
                        anchors.topMargin: 18
                        anchors.bottom: cardBottomNav.top
                        anchors.bottomMargin: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 440

                        // ─────────────────────────────────────────────────────
                        // STEP 1: Country & Region (Image 1 & 2)
                        // ─────────────────────────────────────────────────────
                        Item {
                            anchors.fill: parent
                            visible: root.currentStep === 1

                            Column {
                                anchors.fill: parent
                                spacing: 14

                                // Centered Rounded List Box (Image 1 & 2)
                                Rectangle {
                                    width: parent.width
                                    height: 180
                                    radius: 10
                                    color: Qt.rgba(1, 1, 1, 0.05)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.14)
                                    clip: true

                                    ListView {
                                        id: countryListView
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        model: root.countriesList
                                        spacing: 2
                                        boundsBehavior: Flickable.StopAtBounds

                                        delegate: Rectangle {
                                            id: countryRow
                                            required property var modelData
                                            required property int index
                                            readonly property bool isSelected: root.selectedCountry === modelData.name

                                            width: parent.width
                                            height: 32
                                            radius: 6
                                            color: isSelected ? "#007aff" : (cHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 10

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: countryRow.modelData.flag
                                                    font.pixelSize: 15
                                                }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 120
                                                    text: countryRow.modelData.name
                                                    color: "#ffffff"
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 13
                                                    font.weight: countryRow.isSelected ? Font.DemiBold : Font.Normal
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: countryRow.modelData.lang
                                                    color: countryRow.isSelected ? Qt.rgba(1, 1, 1, 0.90) : Qt.rgba(1, 1, 1, 0.45)
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 12
                                                }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: countryRow.isSelected
                                                    text: "✓"
                                                    color: "#ffffff"
                                                    font.pixelSize: 13
                                                    font.weight: Font.Bold
                                                }
                                            }

                                            HoverHandler { id: cHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                onTapped: {
                                                    root.selectedCountry = countryRow.modelData.name;
                                                    root.selectedLanguage = countryRow.modelData.code;
                                                    root.selectedVoice = countryRow.modelData.voice;
                                                    root.playSound("tink");
                                                }
                                            }
                                        }
                                    }
                                }

                                // Compact System Appearance Segment (Light / Dark)
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 14

                                    // Light Mode
                                    Rectangle {
                                        width: 140; height: 38; radius: 8
                                        color: !root.darkMode ? Qt.rgba(0, 122, 255, 0.22) : Qt.rgba(1, 1, 1, 0.05)
                                        border.width: !root.darkMode ? 1.5 : 1
                                        border.color: !root.darkMode ? "#007aff" : Qt.rgba(1, 1, 1, 0.12)

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 8
                                            Text { text: "☀️"; font.pixelSize: 14 }
                                            Text {
                                                text: "Light"
                                                color: "#ffffff"
                                                font.family: "Open Runde"
                                                font.pixelSize: 12
                                                font.weight: !root.darkMode ? Font.DemiBold : Font.Normal
                                            }
                                        }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: {
                                                root.darkMode = false;
                                                root.playSound("tink");
                                            }
                                        }
                                    }

                                    // Dark Mode
                                    Rectangle {
                                        width: 140; height: 38; radius: 8
                                        color: root.darkMode ? Qt.rgba(0, 122, 255, 0.22) : Qt.rgba(1, 1, 1, 0.05)
                                        border.width: root.darkMode ? 1.5 : 1
                                        border.color: root.darkMode ? "#007aff" : Qt.rgba(1, 1, 1, 0.12)

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 8
                                            Text { text: "🌙"; font.pixelSize: 14 }
                                            Text {
                                                text: "Dark"
                                                color: "#ffffff"
                                                font.family: "Open Runde"
                                                font.pixelSize: 12
                                                font.weight: root.darkMode ? Font.DemiBold : Font.Normal
                                            }
                                        }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: {
                                                root.darkMode = true;
                                                root.playSound("tink");
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ─────────────────────────────────────────────────────
                        // STEP 2: Wi-Fi Networks with Rich Animation (User Request!)
                        // ─────────────────────────────────────────────────────
                        Item {
                            anchors.fill: parent
                            visible: root.currentStep === 2

                            Column {
                                anchors.fill: parent
                                spacing: 10

                                // Top Header Controls: Status + Toggle + Animated Refresh
                                Row {
                                    width: parent.width
                                    height: 28

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.wifiRadioOn ? (root.wifiScanning ? "Scanning nearby networks..." : "Wi-Fi Networks") : "Wi-Fi is turned off"
                                        color: Qt.rgba(1, 1, 1, 0.65)
                                        font.family: "Open Runde"
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }

                                    Item { width: parent.width - 240; height: 1 }

                                    // Refresh Button with Continuous Rotation when Scanning
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 26; height: 26; radius: 13
                                        color: scanHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : "transparent"

                                        Text {
                                            id: refreshIcon
                                            anchors.centerIn: parent
                                            text: "↻"
                                            color: "#ffffff"
                                            font.pixelSize: 16
                                            font.weight: Font.Bold
                                            transformOrigin: Item.Center

                                            RotationAnimation on rotation {
                                                loops: Animation.Infinite
                                                running: root.wifiScanning
                                                from: 0; to: 360
                                                duration: 900
                                            }
                                        }

                                        HoverHandler { id: scanHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.scanWifiNetworks() }
                                    }

                                    Item { width: 8; height: 1 }

                                    // Apple Wi-Fi Power Switch
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 40; height: 22; radius: 11
                                        color: root.wifiRadioOn ? "#34c759" : Qt.rgba(1, 1, 1, 0.20)
                                        Behavior on color { ColorAnimation { duration: 180 } }

                                        Rectangle {
                                            x: root.wifiRadioOn ? 20 : 2
                                            y: 2
                                            width: 18; height: 18; radius: 9
                                            color: "#ffffff"
                                            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                        }

                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.toggleWifiRadio() }
                                    }
                                }

                                // Centered Wi-Fi Network List Box
                                Rectangle {
                                    width: parent.width
                                    height: root.wifiShowPasswordDialog ? 130 : 190
                                    radius: 10
                                    color: Qt.rgba(1, 1, 1, 0.05)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.14)
                                    clip: true
                                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                    // Empty / Scanning Placeholder
                                    Item {
                                        anchors.fill: parent
                                        visible: root.wifiNetworks.length === 0

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 10

                                            // Animated scanning wave dot
                                            Rectangle {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: 14; height: 14; radius: 7
                                                color: "#007aff"
                                                SequentialAnimation on scale {
                                                    loops: Animation.Infinite
                                                    NumberAnimation { from: 0.8; to: 1.4; duration: 800; easing.type: Easing.InOutQuad }
                                                    NumberAnimation { from: 1.4; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                                                }
                                                SequentialAnimation on opacity {
                                                    loops: Animation.Infinite
                                                    NumberAnimation { from: 0.5; to: 1.0; duration: 800 }
                                                    NumberAnimation { from: 1.0; to: 0.5; duration: 800 }
                                                }
                                            }

                                            Text {
                                                text: root.wifiScanning ? "Scanning for nearby Wi-Fi networks..." : "No Wi-Fi networks found."
                                                color: Qt.rgba(1, 1, 1, 0.60)
                                                font.family: "Open Runde"
                                                font.pixelSize: 12
                                            }
                                        }
                                    }

                                    ListView {
                                        id: wifiListView
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        model: root.wifiNetworks
                                        spacing: 2
                                        boundsBehavior: Flickable.StopAtBounds
                                        visible: root.wifiNetworks.length > 0

                                        delegate: Rectangle {
                                            id: wifiRow
                                            required property var modelData
                                            required property int index
                                            readonly property bool isConnected: root.wifiConnectedSsid === modelData.ssid
                                            readonly property bool isConnecting: root.wifiIsConnecting && root.wifiConnectingSsid === modelData.ssid

                                            width: parent.width
                                            height: 34
                                            radius: 6
                                            color: isConnected ? Qt.rgba(0, 122, 255, 0.22) : (wifiRowHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 10

                                                // Animated 3-Arc Fan Wi-Fi Signal Glyph
                                                Canvas {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 18; height: 18
                                                    onPaint: {
                                                        var ctx = getContext("2d");
                                                        ctx.reset();
                                                        var cx = width / 2;
                                                        var cy = height * 0.85;
                                                        var sig = wifiRow.modelData.signal || 50;
                                                        ctx.strokeStyle = wifiRow.isConnected ? "#38bdf8" : "#ffffff";
                                                        ctx.lineCap = "round";

                                                        // Arc 3
                                                        ctx.beginPath();
                                                        ctx.arc(cx, cy, 11, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                        ctx.lineWidth = 1.8;
                                                        ctx.globalAlpha = sig >= 70 ? 1.0 : 0.25;
                                                        ctx.stroke();

                                                        // Arc 2
                                                        ctx.beginPath();
                                                        ctx.arc(cx, cy, 7, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                        ctx.lineWidth = 1.8;
                                                        ctx.globalAlpha = sig >= 40 ? 1.0 : 0.25;
                                                        ctx.stroke();

                                                        // Dot
                                                        ctx.beginPath();
                                                        ctx.arc(cx, cy - 0.5, 1.8, 0, Math.PI * 2);
                                                        ctx.fillStyle = wifiRow.isConnected ? "#38bdf8" : "#ffffff";
                                                        ctx.globalAlpha = 1.0;
                                                        ctx.fill();
                                                    }
                                                }

                                                // SSID
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 150
                                                    text: wifiRow.modelData.ssid
                                                    color: "#ffffff"
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 13
                                                    font.weight: wifiRow.isConnected ? Font.DemiBold : Font.Normal
                                                    elide: Text.ElideRight
                                                }

                                                // Lock icon
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: wifiRow.modelData.secure
                                                    text: "🔒"
                                                    font.pixelSize: 10
                                                    opacity: 0.65
                                                }

                                                // Connecting Spinner
                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: wifiRow.isConnecting
                                                    width: 14; height: 14; radius: 7
                                                    color: "transparent"
                                                    border.width: 2
                                                    border.color: "#007aff"
                                                    RotationAnimation on rotation {
                                                        loops: Animation.Infinite
                                                        running: wifiRow.isConnecting
                                                        from: 0; to: 360; duration: 750
                                                    }
                                                }

                                                // Connected Badge
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: wifiRow.isConnected && !wifiRow.isConnecting
                                                    text: "✓ Connected"
                                                    color: "#34c759"
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 11
                                                    font.weight: Font.DemiBold
                                                }
                                            }

                                            HoverHandler { id: wifiRowHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                onTapped: {
                                                    if (wifiRow.modelData.secure && !wifiRow.isConnected) {
                                                        root.wifiConnectingSsid = wifiRow.modelData.ssid;
                                                        root.wifiShowPasswordDialog = true;
                                                        root.wifiPasswordInput = "";
                                                        root.wifiErrorMsg = "";
                                                    } else {
                                                        root.connectWifi(wifiRow.modelData.ssid);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Inline Password Drawer
                                Rectangle {
                                    width: parent.width
                                    height: root.wifiShowPasswordDialog ? 60 : 0
                                    radius: 10
                                    color: Qt.rgba(0, 0, 0, 0.40)
                                    border.width: root.wifiShowPasswordDialog ? 1 : 0
                                    border.color: "#007aff"
                                    clip: true
                                    visible: height > 0
                                    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 10

                                        Rectangle {
                                            width: 240; height: 32; radius: 6
                                            color: Qt.rgba(1, 1, 1, 0.08)
                                            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.20)

                                            TextInput {
                                                id: passInput
                                                anchors.fill: parent
                                                anchors.margins: 6
                                                color: "#ffffff"
                                                font.pixelSize: 12
                                                echoMode: TextInput.Password
                                                text: root.wifiPasswordInput
                                                onTextChanged: root.wifiPasswordInput = text
                                                onAccepted: root.connectWifi(root.wifiConnectingSsid, text)

                                                Text {
                                                    text: "Enter Wi-Fi password"
                                                    color: Qt.rgba(1, 1, 1, 0.35)
                                                    visible: !passInput.text
                                                    font.pixelSize: 12
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: 75; height: 32; radius: 6
                                            color: "#007aff"
                                            Text { anchors.centerIn: parent; text: "Join"; color: "#ffffff"; font.weight: Font.DemiBold; font.pixelSize: 12 }
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: root.connectWifi(root.wifiConnectingSsid, root.wifiPasswordInput) }
                                        }

                                        Rectangle {
                                            width: 65; height: 32; radius: 6
                                            color: Qt.rgba(1, 1, 1, 0.10)
                                            Text { anchors.centerIn: parent; text: "Cancel"; color: "#ffffff"; font.pixelSize: 12 }
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: root.wifiShowPasswordDialog = false }
                                        }
                                    }
                                }
                            }
                        }

                        // ─────────────────────────────────────────────────────
                        // STEP 3: Siri (Image 4 & 5)
                        // ─────────────────────────────────────────────────────
                        Item {
                            anchors.fill: parent
                            visible: root.currentStep === 3

                            Column {
                                anchors.fill: parent
                                spacing: 14

                                // Centered Apple Checkbox (Image 4)
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 10

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 20; height: 20; radius: 5
                                        color: root.siriEnabled ? "#007aff" : Qt.rgba(1, 1, 1, 0.15)
                                        border.width: 1
                                        border.color: root.siriEnabled ? "#007aff" : Qt.rgba(1, 1, 1, 0.30)

                                        Text {
                                            anchors.centerIn: parent
                                            visible: root.siriEnabled
                                            text: "✓"
                                            color: "#ffffff"
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                        }

                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.siriEnabled = !root.siriEnabled }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Enable Ask Siri"
                                        color: "#ffffff"
                                        font.family: "Open Runde"
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                    }
                                }

                                // Centered Siri Voice List Box (Image 5)
                                Rectangle {
                                    width: 380
                                    height: 120
                                    radius: 10
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    color: Qt.rgba(1, 1, 1, 0.05)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.14)
                                    clip: true
                                    opacity: root.siriEnabled ? 1.0 : 0.4
                                    enabled: root.siriEnabled

                                    ListView {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        spacing: 2
                                        boundsBehavior: Flickable.StopAtBounds
                                        model: [
                                            { id: "en-US-JennyNeural", name: "Voice 1 (English US)" },
                                            { id: "vi-VN-NamMinhNeural", name: "Voice 2 (Tiếng Việt)" },
                                            { id: "ja-JP-NanamiNeural", name: "Voice 3 (Japanese)" },
                                            { id: "fr-FR-DeniseNeural", name: "Voice 4 (French)" },
                                            { id: "de-DE-KatjaNeural", name: "Voice 5 (German)" }
                                        ]

                                        delegate: Rectangle {
                                            id: voiceItem
                                            required property var modelData
                                            required property int index
                                            readonly property bool isSelected: root.selectedVoice === modelData.id

                                            width: parent.width
                                            height: 28
                                            radius: 6
                                            color: isSelected ? "#007aff" : (vHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 8

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: voiceItem.modelData.name
                                                    color: "#ffffff"
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 12
                                                    font.weight: voiceItem.isSelected ? Font.DemiBold : Font.Normal
                                                }

                                                Item { width: 1; height: 1 }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: voiceItem.isSelected
                                                    text: "✓"
                                                    color: "#ffffff"
                                                    font.pixelSize: 12
                                                    font.weight: Font.Bold
                                                }
                                            }

                                            HoverHandler { id: vHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                onTapped: {
                                                    root.selectedVoice = voiceItem.modelData.id;
                                                    root.playSound("tink");
                                                }
                                            }
                                        }
                                    }
                                }

                                // Optional Gemini Key input
                                Rectangle {
                                    width: 380; height: 32; radius: 6
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    color: Qt.rgba(1, 1, 1, 0.05)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.12)
                                    opacity: root.siriEnabled ? 1.0 : 0.4
                                    enabled: root.siriEnabled

                                    TextInput {
                                        id: keyInput
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                        echoMode: TextInput.Password
                                        text: root.geminiApiKey
                                        onTextChanged: root.geminiApiKey = text

                                        Text {
                                            text: "Gemini API Key (Optional for Apple Intelligence)"
                                            color: Qt.rgba(1, 1, 1, 0.35)
                                            visible: !keyInput.text
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }

                        // ─────────────────────────────────────────────────────
                        // STEP 4: Setting Up Your Mac (Installation Progress)
                        // ─────────────────────────────────────────────────────
                        Item {
                            anchors.fill: parent
                            visible: root.currentStep === 4

                            Column {
                                anchors.centerIn: parent
                                spacing: 14

                                // Centered macOS Progress Bar
                                Rectangle {
                                    width: 380
                                    height: 6
                                    radius: 3
                                    color: Qt.rgba(1, 1, 1, 0.15)
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Rectangle {
                                        width: (root.downloadProgress / 100.0) * parent.width
                                        height: parent.height
                                        radius: 3
                                        color: "#007aff"
                                        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.downloadStatusText || "Configuring system resources..."
                                    color: Qt.rgba(1, 1, 1, 0.65)
                                    font.family: "Open Runde"
                                    font.pixelSize: 12
                                }

                                Item { width: 1; height: 10 }

                                // Checklist Cards
                                Rectangle {
                                    width: 380; height: 120; radius: 10
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    color: Qt.rgba(1, 1, 1, 0.05)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.12)
                                    clip: true

                                    ListView {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 4
                                        boundsBehavior: Flickable.StopAtBounds
                                        model: root.dependenciesList

                                        delegate: Row {
                                            required property var modelData
                                            width: parent.width; height: 22
                                            spacing: 8

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "✓"
                                                color: "#34c759"
                                                font.pixelSize: 12
                                                font.weight: Font.Bold
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 30
                                                text: modelData.name || ""
                                                color: "#ffffff"
                                                font.family: "Open Runde"
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ─────────────────────────────────────────────────────
                        // STEP 5: Welcome to MacShell (Image 3 style)
                        // ─────────────────────────────────────────────────────
                        Item {
                            anchors.fill: parent
                            visible: root.currentStep === 5

                            Column {
                                anchors.centerIn: parent
                                spacing: 10

                                // 3 Summary Rows (Like Image 3!)
                                Rectangle {
                                    width: 400; height: 50; radius: 10
                                    color: Qt.rgba(1, 1, 1, 0.05)
                                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 16; anchors.rightMargin: 16
                                        spacing: 12

                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "🌐"; font.pixelSize: 20 }
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2
                                            Text { text: "Preferred Language"; color: Qt.rgba(1, 1, 1, 0.45); font.pixelSize: 11 }
                                            Text { text: root.selectedCountry + " (English)"; color: "#ffffff"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 400; height: 50; radius: 10
                                    color: Qt.rgba(1, 1, 1, 0.05)
                                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 16; anchors.rightMargin: 16
                                        spacing: 12

                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "📶"; font.pixelSize: 20 }
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2
                                            Text { text: "Wi-Fi Network"; color: Qt.rgba(1, 1, 1, 0.45); font.pixelSize: 11 }
                                            Text { text: root.wifiConnectedSsid || "Ready to connect"; color: "#ffffff"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 400; height: 50; radius: 10
                                    color: Qt.rgba(1, 1, 1, 0.05)
                                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 16; anchors.rightMargin: 16
                                        spacing: 12

                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "🎙️"; font.pixelSize: 20 }
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2
                                            Text { text: "Apple Intelligence & Siri"; color: Qt.rgba(1, 1, 1, 0.45); font.pixelSize: 11 }
                                            Text { text: root.siriEnabled ? "Enabled (" + root.selectedVoice.split("-")[2] + ")" : "Disabled"; color: "#ffffff"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ═════════════════════════════════════════════════════════
                    // Bottom Navigation Bar (Image 1, 2, 3, 4, 5)
                    // ═════════════════════════════════════════════════════════
                    Item {
                        id: cardBottomNav
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 52
                        anchors.leftMargin: 28
                        anchors.rightMargin: 28
                        anchors.bottomMargin: 14

                        // Left: Auxiliary / Legal / Options link (Image 1, 3, 4, 5)
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(1, 1, 1, 0.45)
                            font.family: "Open Runde"
                            font.pixelSize: 11
                            text: {
                                switch (root.currentStep) {
                                    case 1: return "By using this software, you agree to the software license terms.";
                                    case 2: return "Other Network Options...";
                                    case 3: return "About Ask Siri, Dictation & Privacy...";
                                    case 4: return "Arch Linux & Hyprland";
                                    default: return "";
                                }
                            }
                        }

                        // Right: Side-by-side classic macOS Back and Continue buttons (Image 2, 3, 4, 5)
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            // Back Button
                            Rectangle {
                                visible: root.currentStep > 1 && root.currentStep < 5
                                width: 76
                                height: 28
                                radius: 6
                                color: backBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.10)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.20)

                                Text {
                                    anchors.centerIn: parent
                                    text: "Back"
                                    color: "#ffffff"
                                    font.family: "Open Runde"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }

                                HoverHandler { id: backBtnHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.goBack() }
                            }

                            // Continue / Get Started Button
                            Rectangle {
                                width: root.currentStep === 5 ? 115 : 86
                                height: root.currentStep === 5 ? 32 : 28
                                radius: root.currentStep === 5 ? 16 : 6
                                color: nextBtnHover.hovered ? "#0062cc" : "#007aff"

                                Text {
                                    anchors.centerIn: parent
                                    font.family: "Open Runde"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: "#ffffff"
                                    text: root.currentStep === 5 ? "Get Started" : "Continue"
                                }

                                HoverHandler { id: nextBtnHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        if (root.currentStep === 5) {
                                            root.finishSetup();
                                        } else {
                                            root.goNext();
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
}
