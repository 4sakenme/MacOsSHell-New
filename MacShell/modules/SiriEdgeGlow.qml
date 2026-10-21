import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../I18n.js" as I18n

Scope {
    id: root

    // Shared Hub reference from shell.qml
    property var hub: null
    property var typeToSiri: null

    // ══════════════════════════════════════════════════════════════════
    // PUBLIC IPC PROPERTIES & STATE
    // ══════════════════════════════════════════════════════════════════
    property bool active: false
    property string siriState: "idle"     // "idle" | "listening" | "thinking" | "speaking"
    property string userPrompt: ""
    property string siriResponse: ""
    property real audioLevel: 0.0         // 0.0 to 1.0 from mic or simulated
    property real smoothAudioLevel: 0.0   // Smoothed audio level to eliminate jitter

    Behavior on smoothAudioLevel {
        NumberAnimation {
            duration: 85
            easing.type: Easing.OutQuad
        }
    }

    onAudioLevelChanged: {
        smoothAudioLevel = audioLevel;
    }

    readonly property bool isListening: siriState === "listening"
    readonly property bool isThinking: siriState === "thinking"
    readonly property bool isSpeaking: siriState === "speaking"

    // Animation progress & state tracking
    property bool isRenderActive: false
    property real smoothProgress: 0.0
    property real bloomProgress: 0.0
    property real introMist: 0.0
    property real shrinkFactor: 1.0

    // ── 1. INTRO ANIMATION: OCEAN WAVE SWELL & SHORELINE REFLECTION (1500ms) ──
    ParallelAnimation {
        id: introAnim

        SequentialAnimation {
            // Wave swell emergence
            NumberAnimation {
                target: root
                property: "introMist"
                from: 0.0
                to: 1.0
                duration: 450
                easing.type: Easing.OutQuad
            }
            // Wave dissipation as ripples bounce and settle into perimeter
            NumberAnimation {
                target: root
                property: "introMist"
                from: 1.0
                to: 0.0
                duration: 1050
                easing.type: Easing.InQuad
            }
        }

        NumberAnimation {
            target: root
            property: "bloomProgress"
            from: 0.0
            to: 1.0
            duration: 1500
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: root
            property: "smoothProgress"
            from: 0.0
            to: 1.0
            duration: 350
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: root
            property: "shrinkFactor"
            from: 0.75
            to: 1.0
            duration: 450
            easing.type: Easing.OutCubic
        }
    }

    // ── 2. OUTRO ANIMATION: BORDER SHRINK + REVERSE RADIAL COLLAPSE (380ms) ──
    ParallelAnimation {
        id: outroAnim

        // Border Shrink: collapse glow width into the bezel
        NumberAnimation {
            target: root
            property: "shrinkFactor"
            to: 0.0
            duration: 380
            easing.type: Easing.InQuad
        }

        // Reverse Radial Collapse: drain wave along 4 edges back to top-right origin
        NumberAnimation {
            target: root
            property: "bloomProgress"
            to: 0.0
            duration: 380
            easing.type: Easing.InQuad
        }

        // Fade Alpha to 0
        NumberAnimation {
            target: root
            property: "smoothProgress"
            to: 0.0
            duration: 380
            easing.type: Easing.InQuad
        }

        NumberAnimation {
            target: root
            property: "introMist"
            to: 0.0
            duration: 120
        }

        onFinished: {
            // Only set render inactive after outro animation has completely finished
            root.isRenderActive = false;
            root.siriState = "idle";
            root.userPrompt = "";
            root.siriResponse = "";
        }
    }

    onActiveChanged: {
        if (active) {
            outroAnim.stop();
            isRenderActive = true;
            shrinkFactor = 1.0;
            introAnim.restart();
            // Start 20-second auto-dismiss countdown (dismisses after 20s or on Esc)
            dismissTimer.restart();
        } else {
            dismissTimer.stop();
            introAnim.stop();
            outroAnim.restart();
        }
    }

    onSiriResponseChanged: {
        // Reset 20-second timer when new response arrives so user has full 20s to read
        if (active && siriResponse !== "") {
            dismissTimer.restart();
        }
    }

    function switchToType() {
        if (typeToSiri) {
            typeToSiri.open();
        }
    }

    Process {
        id: stopSpeechProc
        running: false
        command: [
            "/home/kuro/.config/quickshell/MacShell/venv/bin/python",
            "/home/kuro/.config/quickshell/MacShell/scripts/siri_daemon.py",
            "--stop-speech"
        ]
    }

    function dismiss() {
        if (!active && !isRenderActive) return;
        active = false;
        dismissTimer.stop();
        stopSpeechProc.running = true;
        if (typeToSiri && typeToSiri.isOpen) {
            typeToSiri.close();
        }
    }

    // Auto-dismiss timer: 20 seconds of inactivity before gracefully closing
    Timer {
        id: dismissTimer
        interval: 20000
        repeat: false
        onTriggered: {
            if (root.active) {
                root.dismiss();
            }
        }
    }

    onSiriStateChanged: {
        if (active && (siriState === "speaking" || siriState === "idle")) {
            dismissTimer.restart();
        }
    }

    // Running clock for GLSL wave undulations (Strictly 0% CPU/GPU when idle)
    property real animTime: 0.0
    FrameAnimation {
        running: root.isRenderActive || root.smoothProgress > 0.001
        onTriggered: {
            root.animTime += 0.016;
            if (root.animTime > 10000.0) root.animTime = 0.0;
        }
    }

    // Dynamic voice breathing level
    readonly property real simulatedPulse: isListening
        ? (0.18 + 0.12 * Math.sin(animTime * 5.0))
        : (isSpeaking ? (0.28 + 0.20 * Math.sin(animTime * 6.5)) : (isThinking ? (0.14 + 0.10 * Math.sin(animTime * 3.5)) : 0.0))

    readonly property real effectiveAudioLevel: Math.max(smoothAudioLevel, simulatedPulse)

    // ══════════════════════════════════════════════════════════════════
    // FULLSCREEN OVERLAY ON EVERY SCREEN (100% CLICK-THROUGH)
    // ══════════════════════════════════════════════════════════════════
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "siri-glow"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.active && (!root.typeToSiri || !root.typeToSiri.isOpen)) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            visible: root.isRenderActive || root.smoothProgress > 0.001

            // 100% Click-through: Glow never interferes with desktop mouse clicks
            mask: Region {
                item: emptyMask
            }
            Item { id: emptyMask; width: 0; height: 0 }

            // Voice-First Mode Key Handling (Step 1 -> Press Space to switch to Type Mode, Esc to dismiss)
            FocusScope {
                anchors.fill: parent
                focus: root.active && (!root.typeToSiri || !root.typeToSiri.isOpen)

                Keys.onSpacePressed: event => {
                    event.accepted = true;
                    root.switchToType();
                }

                Keys.onEscapePressed: event => {
                    event.accepted = true;
                    root.dismiss();
                }
            }

            // ── SHADEREFFECT: SCREEN EDGE GLOW WAVE & INTRO/OUTRO DYNAMICS ──
            ShaderEffect {
                id: edgeGlowShader
                anchors.fill: parent

                fragmentShader: Qt.resolvedUrl("siriedgeglow.frag.qsb")

                property vector2d itemSize: Qt.vector2d(width, height)
                property real u_time: root.animTime
                property real screenRadius: 28.0
                property real glowWidth: 32.0
                property real audioLevel: root.effectiveAudioLevel
                property real animProgress: root.smoothProgress
                property vector2d u_origin: Qt.vector2d(0.96, 0.02)
                property real u_bloomProgress: root.bloomProgress
                property real u_introMist: root.introMist
                property real u_shrinkFactor: root.shrinkFactor
            }
        }
    }
}
