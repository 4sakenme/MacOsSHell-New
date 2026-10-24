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
    property bool darkMode: hub && hub.bar ? hub.bar.darkMode : true
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

    // Macro Extreme Close-Up Zoom (Active ONLY for the first word: "hello")
    readonly property bool isFirstHello: (root.helloWordIndex === 0)
    readonly property real macroProgress: isFirstHello ? Math.min(root.strokeDrawProgress / 0.88, 1.0) : 1.0
    // Starts at 2.45x macro close-up, smoothly glides out to 1.0x as 'hello' is written
    readonly property real macroZoomScale: isFirstHello ? (1.0 + 1.45 * Math.pow(1.0 - macroProgress, 2.2)) : 1.0

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

    readonly property real cameraPanX: isFirstHello ? (targetPanX * Math.pow(1.0 - macroProgress, 1.8)) : 0.0
    readonly property real cameraPanY: isFirstHello ? (targetPanY * Math.pow(1.0 - macroProgress, 1.8)) : 0.0

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

    function saveAppearance() {
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

        // 1. Draw strokes continuously from left to right
        NumberAnimation {
            target: root
            property: "strokeDrawProgress"
            from: 0.0
            to: 1.0
            duration: root.isFirstHello ? 3000 : 2400
            easing.type: Easing.InOutSine
        }

        // 2. Pause / Hold for reading (1500ms)
        PauseAnimation { duration: 1500 }

        // 3. Smooth Dissolve / Cross-fade Out (450ms)
        NumberAnimation {
            target: root
            property: "helloOpacity"
            to: 0.0
            duration: 450
            easing.type: Easing.InOutCubic
        }

        PauseAnimation { duration: 150 }

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
            duration: 320
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: root
            property: "helloOpacity"
            to: 0.0
            duration: 300
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
                // Background: Dynamic Pastel Mesh Gradient
                // ─────────────────────────────────────────────────────────────
                Rectangle {
                    anchors.fill: parent
                    color: "#0a0b12"

                    Item {
                        id: meshContainer
                        anchors.fill: parent

                        // Blob 1: Vibrant Sky Blue
                        Rectangle {
                            id: blob1
                            width: 720; height: 720; radius: 360
                            color: "#4a80f0"
                            opacity: 0.68
                            property real t: 0
                            x: (parent.width * 0.15) + Math.sin(t * 0.7) * 130
                            y: (parent.height * 0.12) + Math.cos(t * 0.5) * 100
                        }

                        // Blob 2: Luminous Lavender Violet
                        Rectangle {
                            id: blob2
                            width: 780; height: 780; radius: 390
                            color: "#8a5cd0"
                            opacity: 0.62
                            property real t: 1.5
                            x: (parent.width * 0.55) + Math.cos(t * 0.6) * 150
                            y: (parent.height * 0.22) + Math.sin(t * 0.8) * 120
                        }

                        // Blob 3: Warm Golden Amber
                        Rectangle {
                            id: blob3
                            width: 640; height: 640; radius: 320
                            color: "#ffd166"
                            opacity: 0.52
                            property real t: 3.0
                            x: (parent.width * 0.40) + Math.sin(t * 0.5) * 120
                            y: (parent.height * 0.60) + Math.cos(t * 0.7) * 110
                        }

                        // Blob 4: Pastel Coral Rose
                        Rectangle {
                            id: blob4
                            width: 680; height: 680; radius: 340
                            color: "#ff6b8b"
                            opacity: 0.56
                            property real t: 4.5
                            x: (parent.width * 0.10) + Math.cos(t * 0.8) * 110
                            y: (parent.height * 0.55) + Math.sin(t * 0.6) * 130
                        }

                        // Blob 5: Deep Royal Indigo Anchor
                        Rectangle {
                            id: blob5
                            width: 860; height: 860; radius: 430
                            color: "#352068"
                            opacity: 0.75
                            property real t: 2.2
                            x: (parent.width * 0.65) + Math.sin(t * 0.4) * 90
                            y: (parent.height * 0.50) + Math.cos(t * 0.5) * 90
                        }

                        FrameAnimation {
                            running: root.active
                            onTriggered: {
                                blob1.t += 0.012;
                                blob2.t += 0.010;
                                blob3.t += 0.011;
                                blob4.t += 0.009;
                                blob5.t += 0.008;
                            }
                        }

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blurMax: 96
                            blur: 1.0
                        }
                    }

                    // Ambient subtle vignette
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0.04, 0.05, 0.08, 0.18) }
                            GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.03, 0.06, 0.45) }
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

                        Repeater {
                            model: (root.currentHelloWord && root.currentHelloWord.strokes) ? root.currentHelloWord.strokes : []

                            delegate: Shape {
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

                                // 1. Ambient Glass Refraction Glow
                                ShapePath {
                                    strokeColor: Qt.rgba(1, 1, 1, 0.16)
                                    strokeWidth: 9.5
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    joinStyle: ShapePath.RoundJoin
                                    trim.start: 0.0
                                    trim.end: drawEnd
                                    PathSvg { path: modelData.d }
                                }

                                // 2. Liquid Glass Translucent Body (#50ffffff)
                                ShapePath {
                                    strokeColor: "#50ffffff"
                                    strokeWidth: 5.4
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    joinStyle: ShapePath.RoundJoin
                                    trim.start: 0.0
                                    trim.end: drawEnd
                                    PathSvg { path: modelData.d }
                                }

                                // 3. Prismatic Glass Edge Refraction (subtle sky tint)
                                ShapePath {
                                    strokeColor: Qt.rgba(0.85, 0.95, 1.0, 0.35)
                                    strokeWidth: 3.2
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    joinStyle: ShapePath.RoundJoin
                                    trim.start: 0.0
                                    trim.end: drawEnd
                                    PathSvg { path: modelData.d }
                                }

                                // 4. Glistening Specular Highlight Ridge
                                ShapePath {
                                    strokeColor: Qt.rgba(1, 1, 1, 0.95)
                                    strokeWidth: 1.6
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    joinStyle: ShapePath.RoundJoin
                                    trim.start: 0.0
                                    trim.end: drawEnd
                                    PathSvg { path: modelData.d }
                                }
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
                            width: 24
                            height: 24
                            opacity: (tipInfo.visible && root.helloOpacity > 0.05 && root.currentStep === 0 && !root.isTransitioningToCard) ? 1.0 : 0.0
                            visible: opacity > 0.001

                            Behavior on opacity {
                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }

                            // Outer soft luminous bloom
                            Rectangle {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                radius: 9
                                color: Qt.rgba(1, 1, 1, 0.35)
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    blurEnabled: true
                                    blurMax: 8
                                    blur: 0.9
                                }
                            }

                            // Secondary bright halo
                            Rectangle {
                                anchors.centerIn: parent
                                width: 10
                                height: 10
                                radius: 5
                                color: Qt.rgba(1, 1, 1, 0.65)
                            }

                            // Core pen tip point: diameter 6px, solid white
                            Rectangle {
                                anchors.centerIn: parent
                                width: 6.0
                                height: 6.0
                                radius: 3.0
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
                    // Card Content Layout: Left Column (35%) + Right Column (65%)
                    // ═════════════════════════════════════════════════════════
                    Item {
                        id: cardBody
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: cardBottomNav.top
                        anchors.bottomMargin: 8
                        anchors.margins: 28

                        // ── Left Column: Step Indicators & Hero Branding ──
                        Item {
                            id: leftCol
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            width: 290

                            Column {
                                anchors.fill: parent
                                spacing: 18

                                // Breadcrumb Dots: 5 steps
                                Row {
                                    spacing: 8
                                    Repeater {
                                        model: 5
                                        delegate: Rectangle {
                                            required property int index
                                            readonly property int stepNum: index + 1
                                            width: 8; height: 8; radius: 4
                                            color: root.currentStep === stepNum ? "#007aff" : Qt.rgba(1, 1, 1, 0.25)
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                    }
                                }

                                Item { width: 1; height: 10 }

                                // Hero Icon (64x64) per step
                                Item {
                                    width: 64; height: 64

                                    // Step 1: Apple Globe on Frosted Glass Disc
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 32
                                        visible: root.currentStep === 1
                                        color: Qt.rgba(0, 122, 255, 0.22)
                                        border.width: 1
                                        border.color: "#35ffffff"

                                        Canvas {
                                            anchors.centerIn: parent
                                            width: 36; height: 36
                                            onPaint: {
                                                var ctx = getContext("2d");
                                                ctx.reset();
                                                var cx = width / 2;
                                                var cy = height / 2;
                                                var r = 16;
                                                ctx.strokeStyle = "#ffffff";
                                                ctx.lineWidth = 2.0;

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

                                                // Longitude Curvature
                                                ctx.lineWidth = 1.6;
                                                ctx.beginPath();
                                                ctx.ellipse(cx - 8, cy - r, 16, r * 2);
                                                ctx.stroke();

                                                // Latitude Arcs
                                                ctx.lineWidth = 1.3;
                                                ctx.beginPath();
                                                ctx.arc(cx, cy - 20, 22, Math.PI * 0.35, Math.PI * 0.65, false);
                                                ctx.stroke();
                                                ctx.beginPath();
                                                ctx.arc(cx, cy + 20, 22, -Math.PI * 0.65, -Math.PI * 0.35, false);
                                                ctx.stroke();
                                            }
                                        }
                                    }

                                    // Step 2: Apple Wi-Fi Glyph on Frosted Glass Disc
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 32
                                        visible: root.currentStep === 2
                                        color: Qt.rgba(0, 122, 255, 0.22)
                                        border.width: 1
                                        border.color: "#35ffffff"

                                        Canvas {
                                            anchors.centerIn: parent
                                            width: 36; height: 36
                                            onPaint: {
                                                var ctx = getContext("2d");
                                                ctx.reset();
                                                var cx = width / 2;
                                                var cy = height * 0.88;
                                                ctx.strokeStyle = "#ffffff";
                                                ctx.lineCap = "round";

                                                // Arc 3 (Outer)
                                                ctx.beginPath();
                                                ctx.arc(cx, cy, 22, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                ctx.lineWidth = 3.2;
                                                ctx.stroke();

                                                // Arc 2 (Middle)
                                                ctx.beginPath();
                                                ctx.arc(cx, cy, 14.5, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                ctx.lineWidth = 3.0;
                                                ctx.stroke();

                                                // Arc 1 (Inner)
                                                ctx.beginPath();
                                                ctx.arc(cx, cy, 7.5, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                ctx.lineWidth = 2.8;
                                                ctx.stroke();

                                                // Dot
                                                ctx.beginPath();
                                                ctx.arc(cx, cy - 0.5, 2.5, 0, Math.PI * 2);
                                                ctx.fillStyle = "#ffffff";
                                                ctx.fill();
                                            }
                                        }
                                    }

                                    // Step 3: Apple Siri Glowing Wave Orb
                                    Item {
                                        anchors.fill: parent
                                        visible: root.currentStep === 3
                                        SiriOrb {
                                            anchors.fill: parent
                                            active: root.currentStep === 3
                                            isProcessing: true
                                        }
                                    }

                                    // Step 4: Package Check / Sync on Frosted Glass Disc
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 32
                                        visible: root.currentStep === 4
                                        color: Qt.rgba(175, 82, 222, 0.25)
                                        border.width: 1
                                        border.color: "#35ffffff"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "⚡"
                                            font.pixelSize: 28
                                        }
                                    }

                                    // Step 5: Pure Apple White Logo on Frosted Glass Disc
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 32
                                        visible: root.currentStep === 5
                                        color: Qt.rgba(255, 255, 255, 0.16)
                                        border.width: 1
                                        border.color: "#35ffffff"

                                        Image {
                                            anchors.centerIn: parent
                                            width: 38; height: 38
                                            sourceSize: Qt.size(64, 64)
                                            source: "apple-logo-white.svg"
                                        }
                                    }
                                }

                                // Large Bold Step Title
                                Text {
                                    width: parent.width - 10
                                    wrapMode: Text.WordWrap
                                    color: "#ffffff"
                                    font.family: "Open Runde"
                                    font.pixelSize: 22
                                    font.weight: Font.Bold
                                    lineHeight: 1.15
                                    text: {
                                        switch (root.currentStep) {
                                            case 1: return "Country & Appearance";
                                            case 2: return "Connect to Wi-Fi";
                                            case 3: return "Apple Intelligence";
                                            case 4: return "System Check";
                                            case 5: return "Welcome to MacShell!";
                                            default: return "MacShell Setup";
                                        }
                                    }
                                }

                                // Concise Step Description
                                Text {
                                    width: parent.width - 10
                                    wrapMode: Text.WordWrap
                                    color: Qt.rgba(1, 1, 1, 0.65)
                                    font.family: "Open Runde"
                                    font.pixelSize: 13
                                    lineHeight: 1.35
                                    text: {
                                        switch (root.currentStep) {
                                            case 1: return "Select your country or region to configure language and regional formats, and personalize your system appearance.";
                                            case 2: return "Connect to your wireless network to browse the web, sync widgets, and download resources.";
                                            case 3: return "Intelligent AI assistant powered by Gemini for conversational voice interaction and system commands.";
                                            case 4: return "Automatically verify and retrieve required dependencies, typography fonts, and UI sounds on Arch Linux.";
                                            case 5: return "Your system is ready with an authentic macOS desktop experience built on Arch Linux & Hyprland.";
                                            default: return "";
                                        }
                                    }
                                }

                                // Set Up Later button for Siri step
                                Rectangle {
                                    visible: root.currentStep === 3
                                    width: 175; height: 32; radius: 16
                                    color: laterHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.20)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Set Up Later / Skip"
                                        color: Qt.rgba(1, 1, 1, 0.85)
                                        font.family: "Open Runde"
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                    }

                                    HoverHandler { id: laterHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            root.siriEnabled = false;
                                            root.currentStep = 4;
                                            root.runDepsCheck();
                                        }
                                    }
                                }
                            }
                        }

                        // ── Right Column: Interactive Content (Seamless layout, no vertical split) ──
                        Item {
                            id: rightCol
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.left: leftCol.right
                            anchors.leftMargin: 24
                            anchors.right: parent.right

                            // ─────────────────────────────────────────────────
                            // STEP 1: Appearance & Feature Modules Checklist
                            // ─────────────────────────────────────────────────
                            Flickable {
                                anchors.fill: parent
                                visible: root.currentStep === 1
                                contentHeight: step1Col.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: step1Col
                                    width: parent.width
                                    spacing: 12

                                    // Country / Region Selection (macOS OOBE style)
                                    Text {
                                        text: "SELECT YOUR COUNTRY OR REGION"
                                        color: Qt.rgba(1, 1, 1, 0.50)
                                        font.family: "Open Runde"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 140
                                        radius: 16
                                        color: Qt.rgba(1, 1, 1, 0.05)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.12)
                                        clip: true

                                        ListView {
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            model: root.countriesList
                                            spacing: 3
                                            boundsBehavior: Flickable.StopAtBounds

                                            delegate: Rectangle {
                                                id: countryItem
                                                required property var modelData
                                                required property int index
                                                readonly property bool isSelected: root.selectedCountry === modelData.name

                                                width: parent.width
                                                height: 38
                                                radius: 12
                                                color: isSelected ? Qt.rgba(0, 122, 255, 0.28) : (cHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                                                border.width: isSelected ? 1.5 : (cHover.hovered ? 1 : 0)
                                                border.color: isSelected ? "#007aff" : Qt.rgba(1, 1, 1, 0.12)

                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                                // Top specular highlight on selected item
                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    height: 1
                                                    radius: parent.radius
                                                    visible: countryItem.isSelected
                                                    color: Qt.rgba(1, 1, 1, 0.35)
                                                }

                                                Row {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    spacing: 10

                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: countryItem.modelData.flag
                                                        font.pixelSize: 18
                                                    }

                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: countryItem.modelData.name
                                                        color: "#ffffff"
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 13
                                                        font.weight: countryItem.isSelected ? Font.DemiBold : Font.Normal
                                                    }

                                                    Item { width: Math.max(parent.width - 250, 10); height: 1 }

                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: countryItem.modelData.lang
                                                        color: countryItem.isSelected ? Qt.rgba(1, 1, 1, 0.90) : Qt.rgba(1, 1, 1, 0.45)
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 12
                                                    }

                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: "✓"
                                                        color: "#007aff"
                                                        font.pixelSize: 13
                                                        font.weight: Font.Bold
                                                        visible: countryItem.isSelected
                                                    }
                                                }

                                                HoverHandler { id: cHover; cursorShape: Qt.PointingHandCursor }
                                                TapHandler {
                                                    onTapped: {
                                                        root.selectedCountry = countryItem.modelData.name;
                                                        root.selectedLanguage = countryItem.modelData.code;
                                                        root.selectedVoice = countryItem.modelData.voice;
                                                        root.playSound("tink");
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Item { width: 1; height: 2 }

                                    // Theme Selector Cards (Light & Dark)
                                    Text {
                                        text: "SYSTEM APPEARANCE"
                                        color: Qt.rgba(1, 1, 1, 0.50)
                                        font.family: "Open Runde"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }

                                    Row {
                                        spacing: 12
                                        width: parent.width

                                        // Light Theme Card with Apple Display Icon
                                        Rectangle {
                                            width: (parent.width - 12) / 2
                                            height: 64; radius: 12
                                            color: !root.darkMode ? Qt.rgba(0, 122, 255, 0.22) : Qt.rgba(1, 1, 1, 0.06)
                                            border.width: !root.darkMode ? 1.5 : 1
                                            border.color: !root.darkMode ? "#007aff" : Qt.rgba(1, 1, 1, 0.14)

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 12

                                                // Apple Display Icon (Light)
                                                Item {
                                                    width: 28; height: 26
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    Rectangle {
                                                        width: 28; height: 18; radius: 3
                                                        color: "#dbeafe"
                                                        border.width: 1.2
                                                        border.color: "#3b82f6"

                                                        Rectangle {
                                                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                                            height: 3; radius: 1
                                                            color: Qt.rgba(0, 0, 0, 0.20)
                                                        }
                                                        Rectangle {
                                                            anchors.centerIn: parent
                                                            width: 14; height: 8; radius: 1.5
                                                            color: "#ffffff"
                                                        }
                                                    }
                                                    Rectangle {
                                                        anchors.top: parent.top; anchors.topMargin: 18
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        width: 4; height: 5; color: "#9ca3af"
                                                    }
                                                    Rectangle {
                                                        anchors.top: parent.top; anchors.topMargin: 23
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        width: 14; height: 2.5; radius: 1; color: "#9ca3af"
                                                    }
                                                }

                                                Text {
                                                    text: "Light"
                                                    color: "#ffffff"
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 13
                                                    font.weight: !root.darkMode ? Font.DemiBold : Font.Medium
                                                }
                                            }
                                            TapHandler { onTapped: root.darkMode = false }
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        }

                                        // Dark Theme Card with Apple Display Icon
                                        Rectangle {
                                            width: (parent.width - 12) / 2
                                            height: 64; radius: 12
                                            color: root.darkMode ? Qt.rgba(0, 122, 255, 0.22) : Qt.rgba(1, 1, 1, 0.06)
                                            border.width: root.darkMode ? 1.5 : 1
                                            border.color: root.darkMode ? "#007aff" : Qt.rgba(1, 1, 1, 0.14)

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 12

                                                // Apple Display Icon (Dark)
                                                Item {
                                                    width: 28; height: 26
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    Rectangle {
                                                        width: 28; height: 18; radius: 3
                                                        color: "#181a24"
                                                        border.width: 1.2
                                                        border.color: "#4b5563"

                                                        Rectangle {
                                                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                                            height: 3; radius: 1
                                                            color: Qt.rgba(255, 255, 255, 0.25)
                                                        }
                                                        Rectangle {
                                                            anchors.centerIn: parent
                                                            width: 14; height: 8; radius: 1.5
                                                            color: "#2a2e3d"
                                                        }
                                                    }
                                                    Rectangle {
                                                        anchors.top: parent.top; anchors.topMargin: 18
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        width: 4; height: 5; color: "#6b7280"
                                                    }
                                                    Rectangle {
                                                        anchors.top: parent.top; anchors.topMargin: 23
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        width: 14; height: 2.5; radius: 1; color: "#6b7280"
                                                    }
                                                }

                                                Text {
                                                    text: "Dark"
                                                    color: "#ffffff"
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 13
                                                    font.weight: root.darkMode ? Font.DemiBold : Font.Medium
                                                }
                                            }
                                            TapHandler { onTapped: root.darkMode = true }
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        }
                                    }

                                    Item { width: 1; height: 4 }

                                    // Feature Modules Title
                                    Text {
                                        text: "FEATURE MODULES"
                                        color: Qt.rgba(1, 1, 1, 0.50)
                                        font.family: "Open Runde"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }

                                    // Module 1: Core MacShell UI (Required & Locked)
                                    Rectangle {
                                        width: parent.width; height: 50; radius: 10
                                        color: Qt.rgba(1, 1, 1, 0.06)
                                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14; anchors.rightMargin: 14
                                            spacing: 10

                                            Text { anchors.verticalCenter: parent.verticalCenter; text: ""; font.pixelSize: 18; color: "#ffffff" }

                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 120
                                                Text { text: "Core MacShell UI"; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.DemiBold }
                                                Text { text: "Menu Bar, Dock, Control Center"; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 11 }
                                            }

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 72; height: 24; radius: 12
                                                color: Qt.rgba(0, 122, 255, 0.20)
                                                border.width: 1; border.color: "#007aff"
                                                Text { anchors.centerIn: parent; text: "Required"; color: "#38bdf8"; font.pixelSize: 10; font.weight: Font.DemiBold }
                                            }
                                        }
                                    }

                                    // Module 2: macOS Wi-Fi Manager
                                    Rectangle {
                                        width: parent.width; height: 50; radius: 10
                                        color: Qt.rgba(1, 1, 1, 0.06)
                                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14; anchors.rightMargin: 14
                                            spacing: 10

                                            Item {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 22; height: 22

                                                Canvas {
                                                    anchors.centerIn: parent
                                                    width: 20; height: 20
                                                    onPaint: {
                                                        var ctx = getContext("2d");
                                                        ctx.reset();
                                                        var cx = width / 2;
                                                        var cy = height * 0.88;
                                                        ctx.strokeStyle = "#ffffff";
                                                        ctx.lineCap = "round";

                                                        // Arc 3 (Outer)
                                                        ctx.beginPath();
                                                        ctx.arc(cx, cy, 14, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                        ctx.lineWidth = 2.0;
                                                        ctx.stroke();

                                                        // Arc 2 (Middle)
                                                        ctx.beginPath();
                                                        ctx.arc(cx, cy, 9, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                        ctx.lineWidth = 1.9;
                                                        ctx.stroke();

                                                        // Arc 1 (Inner)
                                                        ctx.beginPath();
                                                        ctx.arc(cx, cy, 4.5, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                        ctx.lineWidth = 1.8;
                                                        ctx.stroke();

                                                        // Dot
                                                        ctx.beginPath();
                                                        ctx.arc(cx, cy - 0.5, 1.6, 0, Math.PI * 2);
                                                        ctx.fillStyle = "#ffffff";
                                                        ctx.fill();
                                                    }
                                                }
                                            }

                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 80
                                                Text { text: "macOS Wi-Fi Manager"; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.DemiBold }
                                                Text { text: "Wi-Fi scanner and Apple-style connection popup"; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 11 }
                                            }

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 44; height: 26; radius: 13
                                                color: root.wifiManagerEnabled ? "#34c759" : Qt.rgba(1, 1, 1, 0.20)
                                                Behavior on color { ColorAnimation { duration: 180 } }

                                                Rectangle {
                                                    x: root.wifiManagerEnabled ? 20 : 2
                                                    y: 2; width: 22; height: 22; radius: 11
                                                    color: "#ffffff"
                                                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                }
                                                TapHandler { onTapped: root.wifiManagerEnabled = !root.wifiManagerEnabled }
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            }
                                        }
                                    }

                                    // Module 3: Sound & Theme Pack
                                    Rectangle {
                                        width: parent.width; height: 50; radius: 10
                                        color: Qt.rgba(1, 1, 1, 0.06)
                                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14; anchors.rightMargin: 14
                                            spacing: 10

                                            Text { anchors.verticalCenter: parent.verticalCenter; text: "🔔"; font.pixelSize: 18 }

                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 80
                                                Text { text: "Sound & Theme Pack"; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.DemiBold }
                                                Text { text: "Startup Chime, click, pop sounds & typography"; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 11 }
                                            }

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 44; height: 26; radius: 13
                                                color: root.soundPackEnabled ? "#34c759" : Qt.rgba(1, 1, 1, 0.20)
                                                Behavior on color { ColorAnimation { duration: 180 } }

                                                Rectangle {
                                                    x: root.soundPackEnabled ? 20 : 2
                                                    y: 2; width: 22; height: 22; radius: 11
                                                    color: "#ffffff"
                                                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                }
                                                TapHandler { onTapped: root.soundPackEnabled = !root.soundPackEnabled }
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            }
                                        }
                                    }

                                    // Module 4: Apple Intelligence & Siri (Optional)
                                    Rectangle {
                                        width: parent.width; height: 50; radius: 10
                                        color: Qt.rgba(1, 1, 1, 0.06)
                                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14; anchors.rightMargin: 14
                                            spacing: 10

                                            Item {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 22; height: 22
                                                SiriOrb {
                                                    anchors.fill: parent
                                                    active: root.currentStep === 1
                                                    isProcessing: root.siriEnabled
                                                }
                                            }

                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 80
                                                Row {
                                                    spacing: 6
                                                    Text { text: "Apple Intelligence & Siri"; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.DemiBold }
                                                    Text { text: "(Optional)"; color: "#38bdf8"; font.pixelSize: 11 }
                                                }
                                                Text { text: "Conversational voice assistant (Can be skipped)"; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 11 }
                                            }

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 44; height: 26; radius: 13
                                                color: root.siriEnabled ? "#34c759" : Qt.rgba(1, 1, 1, 0.20)
                                                Behavior on color { ColorAnimation { duration: 180 } }

                                                Rectangle {
                                                    x: root.siriEnabled ? 20 : 2
                                                    y: 2; width: 22; height: 22; radius: 11
                                                    color: "#ffffff"
                                                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                }
                                                TapHandler { onTapped: root.siriEnabled = !root.siriEnabled }
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            }
                                        }
                                    }
                                }
                            }

                            // ─────────────────────────────────────────────────
                            // STEP 2: macOS Wi-Fi Connection
                            // ─────────────────────────────────────────────────
                            Item {
                                anchors.fill: parent
                                visible: root.currentStep === 2

                                Column {
                                    anchors.fill: parent
                                    spacing: 12

                                    // Wi-Fi Header Bar with Toggle & Refresh
                                    Rectangle {
                                        width: parent.width; height: 46; radius: 10
                                        color: Qt.rgba(1, 1, 1, 0.06)
                                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14; anchors.rightMargin: 14
                                            spacing: 10

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Wi-Fi"
                                                color: "#ffffff"
                                                font.family: "Open Runde"
                                                font.pixelSize: 14
                                                font.weight: Font.DemiBold
                                            }

                                            Item { width: parent.width - 150; height: 1 }

                                            // Scan / Refresh Button
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 28; height: 28; radius: 14
                                                color: scanHover.hovered ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.08)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "↻"
                                                    font.pixelSize: 15
                                                    color: root.wifiScanning ? "#007aff" : "#ffffff"
                                                    rotation: root.wifiScanning ? 360 : 0
                                                    Behavior on rotation { NumberAnimation { duration: 800; loops: Animation.Infinite } }
                                                }
                                                HoverHandler { id: scanHover; cursorShape: Qt.PointingHandCursor }
                                                TapHandler { onTapped: root.scanWifiNetworks() }
                                            }

                                            // Wi-Fi Radio Toggle Switch
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 44; height: 26; radius: 13
                                                color: root.wifiRadioOn ? "#34c759" : Qt.rgba(1, 1, 1, 0.20)
                                                Behavior on color { ColorAnimation { duration: 180 } }

                                                Rectangle {
                                                    x: root.wifiRadioOn ? 20 : 2
                                                    y: 2; width: 22; height: 22; radius: 11
                                                    color: "#ffffff"
                                                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                }
                                                TapHandler { onTapped: root.toggleWifiRadio(!root.wifiRadioOn) }
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            }
                                        }
                                    }

                                    // Wi-Fi Networks List Container
                                    Rectangle {
                                        width: parent.width
                                        height: parent.height - 58
                                        radius: 12
                                        color: Qt.rgba(1, 1, 1, 0.04)
                                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                                        clip: true

                                        // When Wi-Fi is disabled
                                        Item {
                                            anchors.centerIn: parent
                                            visible: !root.wifiRadioOn
                                            Column {
                                                anchors.centerIn: parent
                                                spacing: 8
                                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Wi-Fi is Turned Off"; color: Qt.rgba(1, 1, 1, 0.60); font.pixelSize: 14; font.weight: Font.Medium }
                                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Turn on the switch above to search for available networks"; color: Qt.rgba(1, 1, 1, 0.40); font.pixelSize: 12 }
                                            }
                                        }

                                        // Network items list
                                        ListView {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            visible: root.wifiRadioOn
                                            model: root.wifiNetworks
                                            spacing: 4
                                            boundsBehavior: Flickable.StopAtBounds

                                            delegate: Rectangle {
                                                id: wifiItemCard
                                                required property var modelData
                                                required property int index

                                                width: parent.width
                                                height: 42
                                                radius: 8
                                                color: wifiItemHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : (modelData.inUse ? Qt.rgba(0, 122, 255, 0.15) : Qt.rgba(1, 1, 1, 0.04))

                                                Row {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12; anchors.rightMargin: 12
                                                    spacing: 12

                                                    // Apple 3-Tier Curved Wi-Fi Signal Arc Icon
                                                    Item {
                                                        id: signalIcon
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 22; height: 18

                                                        Canvas {
                                                            anchors.fill: parent
                                                            onPaint: {
                                                                var ctx = getContext("2d");
                                                                ctx.reset();
                                                                var cx = width / 2;
                                                                var cy = height - 1;
                                                                var sig = wifiItemCard.modelData.signal || 50;
                                                                var activeCol = wifiItemCard.modelData.inUse ? "#007aff" : "#ffffff";
                                                                var dimCol = Qt.rgba(1, 1, 1, 0.22);

                                                                // Outer Arc 3 (>= 70%)
                                                                ctx.beginPath();
                                                                ctx.arc(cx, cy, 14, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                                ctx.lineWidth = 2.0;
                                                                ctx.strokeStyle = sig >= 70 ? activeCol : dimCol;
                                                                ctx.lineCap = "round";
                                                                ctx.stroke();

                                                                // Middle Arc 2 (>= 40%)
                                                                ctx.beginPath();
                                                                ctx.arc(cx, cy, 9.5, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                                ctx.lineWidth = 2.0;
                                                                ctx.strokeStyle = sig >= 40 ? activeCol : dimCol;
                                                                ctx.lineCap = "round";
                                                                ctx.stroke();

                                                                // Inner Arc 1 (>= 15%)
                                                                ctx.beginPath();
                                                                ctx.arc(cx, cy, 5.0, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                                ctx.lineWidth = 2.0;
                                                                ctx.strokeStyle = sig >= 15 ? activeCol : dimCol;
                                                                ctx.lineCap = "round";
                                                                ctx.stroke();

                                                                // Base dot
                                                                ctx.beginPath();
                                                                ctx.arc(cx, cy - 1, 1.6, 0, Math.PI * 2);
                                                                ctx.fillStyle = sig > 0 ? activeCol : dimCol;
                                                                ctx.fill();
                                                            }
                                                        }
                                                    }

                                                    // SSID Name
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: parent.width - 150
                                                        text: wifiItemCard.modelData.ssid || "Wi-Fi"
                                                        color: "#ffffff"
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 13
                                                        font.weight: wifiItemCard.modelData.inUse ? Font.DemiBold : Font.Normal
                                                        elide: Text.ElideRight
                                                    }

                                                    // Padlock icon if encrypted
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: "🔒"
                                                        font.pixelSize: 11
                                                        color: Qt.rgba(1, 1, 1, 0.60)
                                                        visible: wifiItemCard.modelData.secure
                                                    }

                                                    // Connected badge
                                                    Row {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        spacing: 4
                                                        visible: wifiItemCard.modelData.inUse
                                                        Text { text: "✓"; color: "#34c759"; font.pixelSize: 12; font.weight: Font.Bold }
                                                        Text { text: "Connected"; color: "#34c759"; font.pixelSize: 11; font.weight: Font.DemiBold }
                                                    }
                                                }

                                                HoverHandler { id: wifiItemHover; cursorShape: Qt.PointingHandCursor }
                                                TapHandler {
                                                    onTapped: {
                                                        if (wifiItemCard.modelData.inUse) return;
                                                        root.wifiConnectingSsid = wifiItemCard.modelData.ssid;
                                                        if (wifiItemCard.modelData.secure) {
                                                            root.wifiPasswordInput = "";
                                                            root.wifiErrorMsg = "";
                                                            root.wifiShowPasswordDialog = true;
                                                        } else {
                                                            root.connectWifi(wifiItemCard.modelData.ssid, "");
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Wi-Fi Password Sheet Modal
                                        Rectangle {
                                            anchors.fill: parent
                                            visible: root.wifiShowPasswordDialog
                                            color: Qt.rgba(0.08, 0.08, 0.12, 0.88)
                                            radius: 12

                                            Column {
                                                anchors.centerIn: parent
                                                width: parent.width - 60
                                                spacing: 12

                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: "Enter password for network"
                                                    color: Qt.rgba(1, 1, 1, 0.60)
                                                    font.pixelSize: 12
                                                }

                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: "\"" + root.wifiConnectingSsid + "\""
                                                    color: "#ffffff"
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 16
                                                    font.weight: Font.Bold
                                                    elide: Text.ElideRight
                                                    width: parent.width - 20
                                                    horizontalAlignment: Text.AlignHCenter
                                                }

                                                // Password Field
                                                Rectangle {
                                                    width: parent.width; height: 38; radius: 8
                                                    color: Qt.rgba(0.18, 0.18, 0.22, 0.85)
                                                    border.width: 1.5; border.color: "#007aff"

                                                    TextInput {
                                                        id: wifiPwdInput
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 12; anchors.rightMargin: 12
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        color: "#ffffff"
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 13
                                                        echoMode: TextInput.Password
                                                        text: root.wifiPasswordInput
                                                        onTextChanged: root.wifiPasswordInput = text
                                                        onAccepted: {
                                                            if (text.length > 0) root.connectWifi(root.wifiConnectingSsid, text);
                                                        }
                                                    }
                                                }

                                                // Error message if any
                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    visible: root.wifiErrorMsg !== ""
                                                    text: root.wifiErrorMsg
                                                    color: "#ff453a"
                                                    font.pixelSize: 11
                                                }

                                                Row {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    spacing: 12

                                                    // Cancel button
                                                    Rectangle {
                                                        width: 100; height: 32; radius: 16
                                                        color: Qt.rgba(1, 1, 1, 0.12)
                                                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.20)
                                                        Text { anchors.centerIn: parent; text: "Cancel"; color: "#ffffff"; font.pixelSize: 12 }
                                                        TapHandler { onTapped: root.wifiShowPasswordDialog = false }
                                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                    }

                                                    // Connect button
                                                    Rectangle {
                                                        width: 120; height: 32; radius: 16
                                                        color: "#007aff"
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: root.wifiIsConnecting ? "Connecting..." : "Connect"
                                                            color: "#ffffff"
                                                            font.pixelSize: 12
                                                            font.weight: Font.DemiBold
                                                        }
                                                        TapHandler {
                                                            onTapped: {
                                                                if (!root.wifiIsConnecting) {
                                                                    root.connectWifi(root.wifiConnectingSsid, root.wifiPasswordInput);
                                                                }
                                                            }
                                                        }
                                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ─────────────────────────────────────────────────
                            // STEP 3: Apple Intelligence & Siri (Optional)
                            // ─────────────────────────────────────────────────
                            Flickable {
                                anchors.fill: parent
                                visible: root.currentStep === 3
                                contentHeight: step3Col.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: step3Col
                                    width: parent.width
                                    spacing: 14

                                    // Gemini API Key Card
                                    Rectangle {
                                        width: parent.width
                                        height: 120
                                        radius: 12
                                        color: Qt.rgba(1, 1, 1, 0.06)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.12)

                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 8

                                            Row {
                                                width: parent.width
                                                Text {
                                                    text: "Google Gemini API Key"
                                                    color: "#ffffff"
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                }
                                                Item { width: parent.width - 240; height: 1 }
                                                Text {
                                                    text: "Get Free API Key →"
                                                    color: "#007aff"
                                                    font.pixelSize: 11
                                                    TapHandler {
                                                        onTapped: Quickshell.execDetached(["xdg-open", "https://aistudio.google.com/app/apikey"])
                                                    }
                                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                }
                                            }

                                            // Embedded Input & Test Button
                                            Rectangle {
                                                width: parent.width
                                                height: 38
                                                radius: 8
                                                color: Qt.rgba(1, 1, 1, 0.08)
                                                border.width: 1
                                                border.color: root.keyValidationStatus === "valid" ? "#34c759" : (root.keyValidationStatus === "invalid" ? "#ff453a" : Qt.rgba(1, 1, 1, 0.20))

                                                TextInput {
                                                    id: apiKeyInput
                                                    anchors.left: parent.left
                                                    anchors.right: testKeyBtn.left
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 8
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    color: "#ffffff"
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 12
                                                    echoMode: TextInput.PasswordEchoOnEdit
                                                    text: root.geminiApiKey
                                                    onTextChanged: {
                                                        root.geminiApiKey = text;
                                                        root.keyValidationStatus = "idle";
                                                        root.keyValidationMsg = "";
                                                    }
                                                }

                                                Rectangle {
                                                    id: testKeyBtn
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: 4
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 82; height: 30; radius: 6
                                                    color: testKeyHover.hovered ? "#0062cc" : "#007aff"

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: root.keyValidationStatus === "testing" ? "..." : "Verify"
                                                        color: "#ffffff"
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                    }

                                                    HoverHandler { id: testKeyHover; cursorShape: Qt.PointingHandCursor }
                                                    TapHandler { onTapped: root.testKey() }
                                                }
                                            }

                                            // Validation status message
                                            Text {
                                                visible: root.keyValidationMsg !== ""
                                                text: root.keyValidationMsg
                                                color: root.keyValidationStatus === "valid" ? "#34c759" : (root.keyValidationStatus === "invalid" ? "#ff453a" : "#38bdf8")
                                                font.pixelSize: 11
                                            }
                                        }
                                    }

                                    // Voice Streaming Switch
                                    Rectangle {
                                        width: parent.width; height: 50; radius: 10
                                        color: Qt.rgba(1, 1, 1, 0.06)
                                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14; anchors.rightMargin: 14
                                            spacing: 10

                                            Text { anchors.verticalCenter: parent.verticalCenter; text: "🎙️"; font.pixelSize: 18 }

                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 80
                                                Text { text: "Live Voice Streaming"; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.DemiBold }
                                                Text { text: "Stream voice responses in real time from AI"; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 11 }
                                            }

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 44; height: 26; radius: 13
                                                color: root.liveVoiceStreaming ? "#34c759" : Qt.rgba(1, 1, 1, 0.20)
                                                Behavior on color { ColorAnimation { duration: 180 } }

                                                Rectangle {
                                                    x: root.liveVoiceStreaming ? 20 : 2
                                                    y: 2; width: 22; height: 22; radius: 11
                                                    color: "#ffffff"
                                                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                }
                                                TapHandler { onTapped: root.liveVoiceStreaming = !root.liveVoiceStreaming }
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            }
                                        }
                                    }

                                    // TTS Voice Cards
                                    Text {
                                        text: "SIRI VOICE (TTS)"
                                        color: Qt.rgba(1, 1, 1, 0.50)
                                        font.family: "Open Runde"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }

                                    Row {
                                        spacing: 12
                                        width: parent.width

                                        // Vietnamese Voice
                                        Rectangle {
                                            width: (parent.width - 12) / 2
                                            height: 52; radius: 10
                                            color: root.selectedVoice === "vi-VN-NamMinhNeural" ? Qt.rgba(0.2, 0.5, 0.9, 0.25) : Qt.rgba(0.18, 0.18, 0.22, 0.50)
                                            border.width: root.selectedVoice === "vi-VN-NamMinhNeural" ? 2 : 1
                                            border.color: root.selectedVoice === "vi-VN-NamMinhNeural" ? "#007aff" : Qt.rgba(1, 1, 1, 0.15)

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 8
                                                Text { text: "🇻🇳"; font.pixelSize: 18 }
                                                Text { text: "Vietnamese (Nam Minh)"; color: "#ffffff"; font.pixelSize: 12; font.weight: Font.Medium }
                                            }
                                            TapHandler {
                                                onTapped: {
                                                    root.selectedVoice = "vi-VN-NamMinhNeural";
                                                    root.selectedLanguage = "vi-VN";
                                                }
                                            }
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        }

                                        // English Voice
                                        Rectangle {
                                            width: (parent.width - 12) / 2
                                            height: 52; radius: 10
                                            color: root.selectedVoice === "en-US-JennyNeural" ? Qt.rgba(0.2, 0.5, 0.9, 0.25) : Qt.rgba(0.18, 0.18, 0.22, 0.50)
                                            border.width: root.selectedVoice === "en-US-JennyNeural" ? 2 : 1
                                            border.color: root.selectedVoice === "en-US-JennyNeural" ? "#007aff" : Qt.rgba(1, 1, 1, 0.15)

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 8
                                                Text { text: "🇺🇸"; font.pixelSize: 18 }
                                                Text { text: "English (US Jenny)"; color: "#ffffff"; font.pixelSize: 12; font.weight: Font.Medium }
                                            }
                                            TapHandler {
                                                onTapped: {
                                                    root.selectedVoice = "en-US-JennyNeural";
                                                    root.selectedLanguage = "en-US";
                                                }
                                            }
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        }
                                    }
                                }
                            }

                            // ─────────────────────────────────────────────────
                            // STEP 4: Dependency Check & Asset Installation
                            // ─────────────────────────────────────────────────
                            Item {
                                anchors.fill: parent
                                visible: root.currentStep === 4

                                Column {
                                    anchors.fill: parent
                                    spacing: 12

                                    // Dependency Checklist Cards (Scrollable)
                                    Rectangle {
                                        width: parent.width
                                        height: 220
                                        radius: 12
                                        color: Qt.rgba(1, 1, 1, 0.05)
                                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                                        clip: true

                                        ListView {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            model: root.dependenciesList
                                            spacing: 6
                                            boundsBehavior: Flickable.StopAtBounds

                                            delegate: Rectangle {
                                                id: depRow
                                                required property var modelData
                                                required property int index

                                                width: parent.width; height: 38; radius: 8
                                                color: Qt.rgba(1, 1, 1, 0.04)

                                                Row {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12; anchors.rightMargin: 12
                                                    spacing: 10

                                                    // Status indicator icon
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: {
                                                            if (depRow.modelData.status === "installed") return "✓";
                                                            if (depRow.modelData.status === "ready") return "⚡";
                                                            if (depRow.modelData.status === "skipped") return "—";
                                                            return "!";
                                                        }
                                                        color: {
                                                            if (depRow.modelData.status === "installed") return "#34c759";
                                                            if (depRow.modelData.status === "ready") return "#38bdf8";
                                                            if (depRow.modelData.status === "skipped") return Qt.rgba(1, 1, 1, 0.35);
                                                            return "#ff9f0a";
                                                        }
                                                        font.pixelSize: 13
                                                        font.weight: Font.Bold
                                                    }

                                                    // Dependency Name
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: parent.width - 150
                                                        text: depRow.modelData.name || "Auxiliary Package"
                                                        color: "#ffffff"
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 12
                                                        font.weight: Font.Medium
                                                        elide: Text.ElideRight
                                                    }

                                                    // Status Badge
                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 90; height: 22; radius: 11
                                                        color: {
                                                            if (depRow.modelData.status === "installed") return Qt.rgba(52, 199, 89, 0.15);
                                                            if (depRow.modelData.status === "ready") return Qt.rgba(56, 189, 248, 0.15);
                                                            if (depRow.modelData.status === "skipped") return Qt.rgba(1, 1, 0.08);
                                                            return Qt.rgba(255, 159, 10, 0.18);
                                                        }
                                                        border.width: 1
                                                        border.color: {
                                                            if (depRow.modelData.status === "installed") return "#34c759";
                                                            if (depRow.modelData.status === "ready") return "#38bdf8";
                                                            if (depRow.modelData.status === "skipped") return Qt.rgba(1, 1, 1, 0.20);
                                                            return "#ff9f0a";
                                                        }

                                                        Text {
                                                            anchors.centerIn: parent
                                                            font.family: "Open Runde"
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                            color: {
                                                                if (depRow.modelData.status === "installed") return "#34c759";
                                                                if (depRow.modelData.status === "ready") return "#38bdf8";
                                                                if (depRow.modelData.status === "skipped") return Qt.rgba(1, 1, 1, 0.40);
                                                                return "#ff9f0a";
                                                            }
                                                            text: {
                                                                if (depRow.modelData.status === "installed") return "Installed";
                                                                if (depRow.modelData.status === "ready") return "Ready";
                                                                if (depRow.modelData.status === "skipped") return "Skipped";
                                                                return "Download " + (depRow.modelData.size_mb || "") + " MB";
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Real-Time Progress Bar Card
                                    Rectangle {
                                        width: parent.width
                                        height: 105
                                        radius: 12
                                        color: Qt.rgba(0.16, 0.16, 0.20, 0.60)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.15)

                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 10

                                            Row {
                                                width: parent.width
                                                Text {
                                                    text: root.downloadTaskName || "Setup Progress"
                                                    color: "#ffffff"
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                }
                                                Item { width: parent.width - 220; height: 1 }
                                                Text {
                                                    text: root.downloadProgress + "% (" + root.downloadSpeed + ")"
                                                    color: "#38bdf8"
                                                    font.pixelSize: 11
                                                    font.weight: Font.DemiBold
                                                }
                                            }

                                            // Progress Bar Track
                                            Rectangle {
                                                width: parent.width; height: 8; radius: 4
                                                color: Qt.rgba(0.10, 0.10, 0.14, 0.85)

                                                Rectangle {
                                                    height: parent.height; radius: parent.radius
                                                    width: parent.width * (root.downloadProgress / 100.0)
                                                    gradient: Gradient {
                                                        GradientStop { position: 0.0; color: "#007aff" }
                                                        GradientStop { position: 1.0; color: "#38bdf8" }
                                                    }
                                                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                                }
                                            }

                                            // Status text line
                                            Text {
                                                text: root.downloadStatusText
                                                color: Qt.rgba(1, 1, 1, 0.60)
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                                width: parent.width
                                            }
                                        }
                                    }
                                }
                            }

                            // ─────────────────────────────────────────────────
                            // STEP 5: Welcome Finish & Summary
                            // ─────────────────────────────────────────────────
                            Item {
                                anchors.fill: parent
                                visible: root.currentStep === 5

                                Column {
                                    anchors.fill: parent
                                    spacing: 14

                                    Text {
                                        text: "SYSTEM CONFIGURATION SUMMARY"
                                        color: Qt.rgba(1, 1, 1, 0.50)
                                        font.family: "Open Runde"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }

                                    // Summary Cards (2x2 Grid)
                                    Grid {
                                        columns: 2
                                        spacing: 12
                                        width: parent.width

                                        // 1. Theme (Appearance) with Apple Display Icon
                                        Rectangle {
                                            width: (parent.width - 12) / 2; height: 64; radius: 12
                                            color: Qt.rgba(1, 1, 1, 0.06)
                                            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 16; anchors.rightMargin: 16
                                                spacing: 12
                                                anchors.verticalCenter: parent.verticalCenter

                                                // Apple Display Icon
                                                Item {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 28; height: 26

                                                    Rectangle {
                                                        width: 26; height: 17; radius: 3
                                                        color: root.darkMode ? "#181a24" : "#dbeafe"
                                                        border.width: 1.2
                                                        border.color: root.darkMode ? "#4b5563" : "#3b82f6"

                                                        Rectangle {
                                                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                                            height: 3; radius: 1
                                                            color: root.darkMode ? Qt.rgba(255, 255, 255, 0.25) : Qt.rgba(0, 0, 0, 0.20)
                                                        }
                                                        Rectangle {
                                                            anchors.centerIn: parent
                                                            width: 12; height: 7; radius: 1.5
                                                            color: root.darkMode ? "#2a2e3d" : "#ffffff"
                                                        }
                                                    }
                                                    Rectangle {
                                                        anchors.top: parent.top; anchors.topMargin: 17
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        width: 4; height: 5; color: "#9ca3af"
                                                    }
                                                    Rectangle {
                                                        anchors.top: parent.top; anchors.topMargin: 22
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        width: 14; height: 2.5; radius: 1; color: "#9ca3af"
                                                    }
                                                }

                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 44
                                                    spacing: 2

                                                    Text {
                                                        text: "Appearance"
                                                        color: Qt.rgba(1, 1, 1, 0.50)
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 11
                                                    }
                                                    Text {
                                                        text: root.darkMode ? "Dark Mode" : "Light Mode"
                                                        color: "#ffffff"
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 13
                                                        font.weight: Font.DemiBold
                                                    }
                                                }
                                            }
                                        }

                                        // 2. Region & Language with Apple Globe Icon
                                        Rectangle {
                                            width: (parent.width - 12) / 2; height: 64; radius: 12
                                            color: Qt.rgba(1, 1, 1, 0.06)
                                            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 16; anchors.rightMargin: 16
                                                spacing: 12
                                                anchors.verticalCenter: parent.verticalCenter

                                                // Apple Globe Icon
                                                Item {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 28; height: 28

                                                    Canvas {
                                                        anchors.centerIn: parent
                                                        width: 24; height: 24
                                                        onPaint: {
                                                            var ctx = getContext("2d");
                                                            ctx.reset();
                                                            var cx = width / 2;
                                                            var cy = height / 2;
                                                            var r = 10.5;
                                                            ctx.strokeStyle = "#38bdf8";
                                                            ctx.lineWidth = 1.6;

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

                                                            // Longitude Curve
                                                            ctx.lineWidth = 1.3;
                                                            ctx.beginPath();
                                                            ctx.ellipse(cx - 5.5, cy - r, 11, r * 2);
                                                            ctx.stroke();
                                                        }
                                                    }
                                                }

                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 44
                                                    spacing: 2

                                                    Text {
                                                        text: "Region & Language"
                                                        color: Qt.rgba(1, 1, 1, 0.50)
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 11
                                                    }
                                                    Text {
                                                        text: root.selectedCountry
                                                        color: "#ffffff"
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 13
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                        width: parent.width
                                                    }
                                                }
                                            }
                                        }

                                        // 3. Apple Wi-Fi Network
                                        Rectangle {
                                            width: (parent.width - 12) / 2; height: 64; radius: 12
                                            color: Qt.rgba(1, 1, 1, 0.06)
                                            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 16; anchors.rightMargin: 16
                                                spacing: 12
                                                anchors.verticalCenter: parent.verticalCenter

                                                Item {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 28; height: 28

                                                    Canvas {
                                                        anchors.centerIn: parent
                                                        width: 24; height: 24
                                                        onPaint: {
                                                            var ctx = getContext("2d");
                                                            ctx.reset();
                                                            var cx = width / 2;
                                                            var cy = height * 0.88;
                                                            ctx.strokeStyle = "#38bdf8";
                                                            ctx.lineCap = "round";

                                                            // Arc 3 (Outer)
                                                            ctx.beginPath();
                                                            ctx.arc(cx, cy, 16, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                            ctx.lineWidth = 2.2;
                                                            ctx.stroke();

                                                            // Arc 2 (Middle)
                                                            ctx.beginPath();
                                                            ctx.arc(cx, cy, 10.5, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                            ctx.lineWidth = 2.0;
                                                            ctx.stroke();

                                                            // Arc 1 (Inner)
                                                            ctx.beginPath();
                                                            ctx.arc(cx, cy, 5.5, -Math.PI * 0.75, -Math.PI * 0.25, false);
                                                            ctx.lineWidth = 1.9;
                                                            ctx.stroke();

                                                            // Dot
                                                            ctx.beginPath();
                                                            ctx.arc(cx, cy - 0.5, 1.8, 0, Math.PI * 2);
                                                            ctx.fillStyle = "#38bdf8";
                                                            ctx.fill();
                                                        }
                                                    }
                                                }

                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 44
                                                    spacing: 2

                                                    Text {
                                                        text: "Wi-Fi Network"
                                                        color: Qt.rgba(1, 1, 1, 0.50)
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 11
                                                    }
                                                    Text {
                                                        text: root.wifiConnectedSsid ? root.wifiConnectedSsid : (root.wifiManagerEnabled ? "Ready to connect" : "Disabled")
                                                        color: root.wifiConnectedSsid ? "#34c759" : "#ffffff"
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 13
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                        width: parent.width
                                                    }
                                                }
                                            }
                                        }

                                        // 4. Apple Intelligence & Siri with Animated Orb
                                        Rectangle {
                                            width: (parent.width - 12) / 2; height: 64; radius: 12
                                            color: Qt.rgba(1, 1, 1, 0.06)
                                            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 16; anchors.rightMargin: 16
                                                spacing: 12
                                                anchors.verticalCenter: parent.verticalCenter

                                                Item {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 28; height: 28
                                                    SiriOrb {
                                                        anchors.fill: parent
                                                        active: root.currentStep === 5
                                                        isProcessing: root.siriEnabled
                                                    }
                                                }

                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 44
                                                    spacing: 2

                                                    Text {
                                                        text: "Apple Intelligence"
                                                        color: Qt.rgba(1, 1, 1, 0.50)
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 11
                                                    }
                                                    Text {
                                                        text: root.siriEnabled ? "Active & Ready" : "Disabled"
                                                        color: root.siriEnabled ? "#34c759" : Qt.rgba(1, 1, 1, 0.50)
                                                        font.family: "Open Runde"
                                                        font.pixelSize: 13
                                                        font.weight: Font.DemiBold
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Item { width: 1; height: 8 }

                                    // Completion banner
                                    Rectangle {
                                        width: parent.width
                                        height: 68
                                        radius: 12
                                        color: Qt.rgba(0, 122, 255, 0.10)
                                        border.width: 1
                                        border.color: Qt.rgba(0, 122, 255, 0.28)

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 16; anchors.rightMargin: 16
                                            spacing: 14

                                            Item {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 28; height: 28
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✨"
                                                    font.pixelSize: 20
                                                }
                                            }

                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 46
                                                spacing: 3

                                                Text {
                                                    text: "Setup Completed"
                                                    color: "#ffffff"
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                }
                                                Text {
                                                    text: "Your macOS desktop environment is ready. Click \"Get Started\" below to launch."
                                                    color: Qt.rgba(1, 1, 1, 0.65)
                                                    font.family: "Open Runde"
                                                    font.pixelSize: 11
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ═════════════════════════════════════════════════════════
                    // Seamless Floating Bottom Navigation Bar (No dark slabs)
                    // ═════════════════════════════════════════════════════════
                    Item {
                        id: cardBottomNav
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 56
                        anchors.leftMargin: 28
                        anchors.rightMargin: 28
                        anchors.bottomMargin: 14

                        // Left: Back button
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.currentStep > 1
                            width: 100; height: 36; radius: 18
                            color: backBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.20)

                            Text {
                                anchors.centerIn: parent
                                text: "← Back"
                                color: "#ffffff"
                                font.family: "Open Runde"
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }

                            HoverHandler { id: backBtnHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.goBack() }
                        }

                        // Right: Continue / Install / Get Started Pill Button
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: (root.currentStep === 4 && !root.downloadCompleted) ? 165 : (root.currentStep === 5 ? 135 : 125)
                            height: 36
                            radius: 18
                            color: nextBtnHover.hovered ? "#0062cc" : "#007aff"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.25)

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    font.family: "Open Runde"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: "#ffffff"
                                    text: {
                                        if (root.currentStep === 4 && !root.downloadCompleted) return "Install & Continue";
                                        if (root.currentStep === 5) return "Get Started";
                                        return "Continue";
                                    }
                                }

                                Text {
                                    text: "→"
                                    color: "#ffffff"
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                    visible: root.currentStep < 5
                                }
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
