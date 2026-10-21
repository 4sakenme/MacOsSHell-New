import QtQuick
import QtQuick.Effects
import Quickshell
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

    readonly property bool isListening: siriState === "listening"
    readonly property bool isThinking: siriState === "thinking"
    readonly property bool isSpeaking: siriState === "speaking"

    // Animation progress & smooth transitions
    readonly property real targetProgress: active ? 1.0 : 0.0
    property real smoothProgress: 0.0
    property real bloomProgress: 0.0

    Behavior on smoothProgress {
        NumberAnimation {
            duration: root.active ? 420 : 350
            easing.type: Easing.OutCubic
        }
    }

    // 650ms OutCubic: Apple Intelligence perimeter shockwave burst
    NumberAnimation {
        id: bloomAnim
        target: root
        property: "bloomProgress"
        from: 0.0
        to: 1.0
        duration: 650
        easing.type: Easing.OutCubic
    }

    onActiveChanged: {
        smoothProgress = active ? 1.0 : 0.0;
        if (active) {
            bloomProgress = 0.0;
            bloomAnim.restart();
        } else {
            dismissTimer.stop();
            bloomAnim.stop();
            bloomProgress = 0.0;
        }
    }

    function switchToType() {
        if (typeToSiri) {
            typeToSiri.open();
        }
    }

    function dismiss() {
        active = false;
        siriState = "idle";
        userPrompt = "";
        siriResponse = "";
        if (typeToSiri && typeToSiri.isOpen) {
            typeToSiri.close();
        }
    }

    // Auto-dismiss timer after speaking has finished
    Timer {
        id: dismissTimer
        interval: 6500
        repeat: false
        onTriggered: {
            if (root.active && (root.siriState === "speaking" || root.siriResponse !== "")) {
                root.active = false;
            }
        }
    }

    onSiriStateChanged: {
        if (siriState === "speaking") {
            dismissTimer.restart();
        }
    }

    // Running clock for GLSL wave undulations (~60 FPS)
    property real animTime: 0.0
    FrameAnimation {
        running: root.smoothProgress > 0.001
        onTriggered: {
            root.animTime += 0.016;
            if (root.animTime > 10000.0) root.animTime = 0.0;
        }
    }

    // Dynamic voice breathing level
    readonly property real simulatedPulse: isListening
        ? (0.18 + 0.12 * Math.sin(animTime * 5.0))
        : (isSpeaking ? (0.28 + 0.20 * Math.sin(animTime * 6.5)) : (isThinking ? (0.14 + 0.10 * Math.sin(animTime * 3.5)) : 0.0))

    readonly property real effectiveAudioLevel: Math.max(audioLevel, simulatedPulse)

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

            visible: root.smoothProgress > 0.001

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

            // ── SHADEREFFECT: SCREEN EDGE GLOW WAVE ──
            ShaderEffect {
                id: edgeGlowShader
                anchors.fill: parent

                fragmentShader: Qt.resolvedUrl("siriedgeglow.frag.qsb")

                property vector2d itemSize: Qt.vector2d(width, height)
                property real u_time: root.animTime
                property real screenRadius: 28.0
                property real glowWidth: 26.0       // Balanced 26px Apple Intelligence glow width with diffused aura
                property real audioLevel: root.effectiveAudioLevel
                property real animProgress: root.smoothProgress
                property vector2d u_origin: Qt.vector2d(0.96, 0.02)
                property real u_bloomProgress: root.bloomProgress
            }
        }
    }
}
