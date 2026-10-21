import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../I18n.js" as I18n

Scope {
    id: root

    // Shared Hub reference from shell.qml
    property var hub: null

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

    Behavior on smoothProgress {
        NumberAnimation {
            duration: root.active ? 420 : 350
            easing.type: Easing.OutCubic
        }
    }

    onActiveChanged: {
        smoothProgress = active ? 1.0 : 0.0;
        if (!active) {
            dismissTimer.stop();
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

    function dismiss() {
        active = false;
        siriState = "idle";
        userPrompt = "";
        siriResponse = "";
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
        ? (0.22 + 0.16 * Math.sin(animTime * 7.0))
        : (isSpeaking ? (0.35 + 0.28 * Math.sin(animTime * 9.0)) : (isThinking ? (0.18 + 0.12 * Math.sin(animTime * 4.0)) : 0.0))

    readonly property real effectiveAudioLevel: Math.max(audioLevel, simulatedPulse)

    // ══════════════════════════════════════════════════════════════════
    // FULLSCREEN OVERLAY ON EVERY SCREEN
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
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            visible: root.smoothProgress > 0.001

            // Mask: Click-through everywhere EXCEPT the floating speech card
            mask: Region {
                item: (root.active && siriCard.visible && (root.userPrompt !== "" || root.siriResponse !== "" || siriHover.hovered)) ? siriCard : emptyMask
            }
            Item { id: emptyMask; width: 0; height: 0 }

            // ── SHADEREFFECT: SCREEN EDGE GLOW WAVE ──
            ShaderEffect {
                id: edgeGlowShader
                anchors.fill: parent

                fragmentShader: Qt.resolvedUrl("siriedgeglow.frag.qsb")

                property vector2d itemSize: Qt.vector2d(width, height)
                property real u_time: root.animTime
                property real screenRadius: 28.0
                property real glowWidth: 36.0
                property real audioLevel: root.effectiveAudioLevel
                property real animProgress: root.smoothProgress
            }

            // ── FLOATING APPLE INTELLIGENCE SIRI SPEECH CARD ──
            Item {
                id: siriCardContainer
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 52
                width: Math.min(parent.width - 64, Math.max(380, cardCol.implicitWidth + 48))
                height: cardCol.implicitHeight + 32

                opacity: root.smoothProgress
                scale: 0.92 + 0.08 * root.smoothProgress
                transformOrigin: Item.Bottom

                Behavior on opacity { NumberAnimation { duration: 280 } }
                Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

                // Drop Shadow
                RectangularShadow {
                    anchors.fill: siriCard
                    radius: siriCard.radius
                    blur: 32; offset.y: 10
                    color: Qt.rgba(0, 0, 0, 0.65)
                }

                // Siri Card Surface
                Rectangle {
                    id: siriCard
                    anchors.fill: parent
                    radius: 24

                    // Obsidian Frosted Glass
                    color: Qt.rgba(0.06, 0.06, 0.09, 0.88)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.14)

                    // Siri Chromatic Rim Gradient Border
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -1
                        radius: parent.radius + 1
                        z: -1
                        color: "transparent"
                        border.width: 1.2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(0.0, 0.94, 1.0, 0.70) }
                            GradientStop { position: 0.35; color: Qt.rgba(0.61, 0.32, 0.88, 0.70) }
                            GradientStop { position: 0.70; color: Qt.rgba(1.0, 0.18, 0.33, 0.70) }
                            GradientStop { position: 1.0; color: Qt.rgba(1.0, 0.58, 0.0, 0.65) }
                        }
                    }

                    HoverHandler { id: siriHover }

                    Column {
                        id: cardCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 16
                        spacing: 12

                        // Header: Siri Orb + State Tag + Close Button
                        Item {
                            width: parent.width
                            height: 28

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                // Siri Orb (Animated breathing chromatic gradient sphere)
                                Rectangle {
                                    width: 26; height: 26; radius: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "#00F0FF" }
                                        GradientStop { position: 0.5; color: "#9B51E0" }
                                        GradientStop { position: 1.0; color: "#FF2D55" }
                                    }

                                    // Inner pulse
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 14 + root.effectiveAudioLevel * 8
                                        height: width
                                        radius: width / 2
                                        color: Qt.rgba(1, 1, 1, 0.75)
                                        Behavior on width { NumberAnimation { duration: 60 } }
                                    }
                                }

                                Column {
                                    spacing: 1
                                    Text {
                                        text: "Apple Intelligence Siri"
                                        color: "white"
                                        font.family: "Open Runde"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                    }

                                    Text {
                                        text: root.isListening ? I18n.tr("Listening...") : (root.isThinking ? I18n.tr("Gemini Thinking...") : (root.isSpeaking ? I18n.tr("Speaking...") : I18n.tr("Ready")))
                                        color: root.isListening ? "#00F0FF" : (root.isThinking ? "#9B51E0" : (root.isSpeaking ? "#FF2D55" : "#8E8E93"))
                                        font.family: "Open Runde"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            // Close Button
                            Rectangle {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22; height: 22; radius: 11
                                color: closeTap.pressed ? Qt.rgba(1, 1, 1, 0.25) : (closeHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.06))
                                border.color: Qt.rgba(1, 1, 1, 0.10)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: "white"
                                    font.pixelSize: 9
                                }
                                HoverHandler { id: closeHover }
                                TapHandler {
                                    id: closeTap
                                    onTapped: root.active = false
                                }
                            }
                        }

                        // User Prompt Display (what user said)
                        Rectangle {
                            visible: root.userPrompt !== ""
                            width: parent.width
                            height: promptText.implicitHeight + 16
                            radius: 12
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1

                            Row {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                Text {
                                    text: "🗣️"
                                    font.pixelSize: 12
                                }

                                Text {
                                    id: promptText
                                    width: parent.width - 28
                                    text: root.userPrompt
                                    color: "#e4e1e7"
                                    font.family: "Open Runde"
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        // Gemini AI Response Display
                        Rectangle {
                            visible: root.siriResponse !== "" || root.isThinking
                            width: parent.width
                            height: Math.min(320, responseText.implicitHeight + 20)
                            radius: 14
                            color: Qt.rgba(0, 0, 0, 0.35)
                            border.color: Qt.rgba(0, 0.94, 1.0, 0.20)
                            border.width: 1
                            clip: true

                            Flickable {
                                anchors.fill: parent
                                anchors.margins: 10
                                contentWidth: width
                                contentHeight: responseText.implicitHeight
                                clip: true

                                Text {
                                    id: responseText
                                    width: parent.width
                                    text: root.siriResponse !== "" ? root.siriResponse : I18n.tr("Processing your request with Gemini...")
                                    color: "white"
                                    font.family: "Open Runde"
                                    font.pixelSize: 13
                                    font.weight: Font.Normal
                                    lineHeight: 1.35
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
