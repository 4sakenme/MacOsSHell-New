import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../I18n.js" as I18n

Scope {
    id: root

    // Reference to SiriEdgeGlow component
    property var edgeGlow: null

    // State properties
    property bool isOpen: false
    property string prompt: ""
    property string response: ""
    property bool isThinking: false

    // Smooth open/close animation
    property real animProgress: 0.0
    Behavior on animProgress {
        NumberAnimation {
            duration: root.isOpen ? 280 : 220
            easing.type: Easing.OutCubic
        }
    }

    // Running clock for GLSL flowing animations
    property real animTime: 0.0
    FrameAnimation {
        running: root.animProgress > 0.001
        onTriggered: {
            root.animTime += 0.016;
            if (root.animTime > 10000.0) root.animTime = 0.0;
        }
    }

    onIsOpenChanged: {
        animProgress = isOpen ? 1.0 : 0.0;
        if (isOpen) {
            if (edgeGlow) {
                edgeGlow.active = true;
                edgeGlow.siriState = "listening";
                edgeGlow.userPrompt = "";
                edgeGlow.siriResponse = "";
            }
        } else {
            if (edgeGlow) {
                edgeGlow.active = false;
                edgeGlow.siriState = "idle";
            }
            isThinking = false;
        }
    }

    // Public functions
    function open() {
        isOpen = true;
    }

    function close() {
        isOpen = false;
        response = "";
        isThinking = false;
        if (edgeGlow) edgeGlow.dismiss();
    }

    function toggle() {
        if (isOpen) close();
        else open();
    }

    function ask(text: string) {
        if (!text || text.trim() === "") return;
        var cleanPrompt = text.trim();
        prompt = cleanPrompt;
        response = "";
        isThinking = true;
        isOpen = true;

        if (edgeGlow) {
            edgeGlow.active = true;
            edgeGlow.siriState = "thinking";
            edgeGlow.userPrompt = cleanPrompt;
            edgeGlow.siriResponse = "";
        }

        queryProc.command = [
            "/home/kuro/.config/quickshell/MacShell/venv/bin/python",
            "/home/kuro/.config/quickshell/MacShell/scripts/siri_daemon.py",
            "--query", cleanPrompt
        ];
        queryProc.running = true;
    }

    // Background Process to execute query via siri_daemon.py
    Process {
        id: queryProc
        running: false
        onExited: {
            root.isThinking = false;
        }
    }

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

            WlrLayershell.namespace: "type-to-siri"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            visible: root.animProgress > 0.001

            // Click-through everywhere EXCEPT the pill and response bubble
            mask: Region {
                item: root.isOpen ? pillContainer : emptyMask
            }
            Item { id: emptyMask; width: 0; height: 0 }

            // Click outside pill to dismiss
            MouseArea {
                anchors.fill: parent
                z: 0
                onClicked: root.close()
            }

            // ── DRAGGABLE FLOATING CONTAINER ──
            Item {
                id: pillContainer
                z: 10

                // Default position: Centered horizontally, 20% down from top
                x: (win.width - width) / 2 + dragOffset.x
                y: Math.max(80, win.height * 0.18) + dragOffset.y

                width: 440
                height: pillBox.height + (bubbleBox.visible ? (bubbleBox.height + 12) : 0)

                // Drag offset tracking
                QtObject {
                    id: dragOffset
                    property real x: 0
                    property real y: 0
                }

                // Opacity & Scale entrance animation
                opacity: root.animProgress
                scale: 0.94 + 0.06 * root.animProgress

                // MouseArea for dragging the entire pill window
                MouseArea {
                    id: dragHandler
                    anchors.fill: pillBox
                    z: 1

                    drag.target: null // Handled manually for smooth offset

                    property real startMouseX: 0
                    property real startMouseY: 0
                    property real startOffsetX: 0
                    property real startOffsetY: 0
                    property bool isDragging: false

                    onPressed: mouse => {
                        isDragging = true;
                        startMouseX = mouse.x;
                        startMouseY = mouse.y;
                        startOffsetX = dragOffset.x;
                        startOffsetY = dragOffset.y;
                    }

                    onPositionChanged: mouse => {
                        if (isDragging) {
                            dragOffset.x = startOffsetX + (mouse.x - startMouseX);
                            dragOffset.y = startOffsetY + (mouse.y - startMouseY);
                        }
                    }

                    onReleased: isDragging = false
                    onCanceled: isDragging = false
                }

                // ── 1. LIQUID GLASS PILL BAR ──
                Item {
                    id: pillBox
                    width: parent.width
                    height: 50
                    z: 5

                    // Flowing Gradient Border Shader Effect (Apple Intelligence)
                    ShaderEffect {
                        id: flowingBorder
                        anchors.fill: parent
                        anchors.margins: -2.0

                        fragmentShader: Qt.resolvedUrl("flowingborder.frag.qsb")

                        property vector2d itemSize: Qt.vector2d(width, height)
                        property real u_time: root.animTime
                        property real borderWidth: 2.2
                        property real borderRadius: height * 0.5
                        property real isThinking: root.isThinking ? 1.0 : 0.0
                    }

                    // Main Glass Pill Background
                    Rectangle {
                        id: glassBg
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.rgba(0.08, 0.08, 0.11, 0.82)
                        border.color: Qt.rgba(1, 1, 1, 0.18)
                        border.width: 1

                        // Inner subtle specular highlight at top
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 1
                            height: 22
                            radius: height / 2
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.12) }
                                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.00) }
                            }
                        }
                    }

                    // Content Row: Siri Orb + TextInput + Action Button
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10
                        z: 10

                        // Siri Orb (3D Fluid Plasma Shader)
                        SiriOrb {
                            id: siriOrb
                            width: 30; height: 30
                            anchors.verticalCenter: parent.verticalCenter
                            isProcessing: root.isThinking || (root.edgeGlow && root.edgeGlow.siriState === "speaking")
                            audioLevel: root.edgeGlow ? root.edgeGlow.effectiveAudioLevel : 0.0
                        }

                        // Text Input Field
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - siriOrb.width - actionBtn.width - 32
                            height: parent.height

                            TextInput {
                                id: mainInput
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true

                                font.family: "Open Runde"
                                font.pixelSize: 14
                                font.weight: Font.Normal
                                color: "white"
                                selectionColor: "#00F0FF"
                                selectedTextColor: "#000000"

                                Connections {
                                    target: root
                                    function onIsOpenChanged() {
                                        if (root.isOpen) {
                                            inputFocusTimer.restart();
                                        }
                                    }
                                }

                                Timer {
                                    id: inputFocusTimer
                                    interval: 80
                                    repeat: false
                                    onTriggered: mainInput.forceActiveFocus()
                                }

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: I18n.tr("Ask Siri or type a command...")
                                    font.family: "Open Runde"
                                    font.pixelSize: 14
                                    color: Qt.rgba(1, 1, 1, 0.38)
                                    visible: mainInput.text.length === 0 && !mainInput.inputMethodComposing
                                }

                                Keys.onReturnPressed: {
                                    if (mainInput.text.trim() !== "") {
                                        var q = mainInput.text;
                                        mainInput.text = "";
                                        root.ask(q);
                                    }
                                }

                                Keys.onEscapePressed: {
                                    root.close();
                                }
                            }
                        }

                        // Action Button (Send / Close)
                        Rectangle {
                            id: actionBtn
                            width: 26; height: 26; radius: 13
                            anchors.verticalCenter: parent.verticalCenter
                            color: btnHover.hovered ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                            border.color: Qt.rgba(1, 1, 1, 0.12)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: root.isThinking ? "⋯" : (mainInput.text.length > 0 ? "↑" : "✕")
                                color: "white"
                                font.family: "Open Runde"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }

                            HoverHandler { id: btnHover }

                            TapHandler {
                                onTapped: {
                                    if (mainInput.text.length > 0) {
                                        var q = mainInput.text;
                                        mainInput.text = "";
                                        root.ask(q);
                                    } else {
                                        root.close();
                                    }
                                }
                            }
                        }
                    }
                }

                // ── 2. RESPONSE BUBBLE (GEMINI STREAMING / ANSWER BOX) ──
                Item {
                    id: bubbleBox
                    anchors.top: pillBox.bottom
                    anchors.topMargin: 10
                    width: parent.width
                    height: Math.min(280, Math.max(76, bubbleCol.implicitHeight + 28))
                    visible: root.response !== "" || root.isThinking

                    z: 5

                    // Glass Bubble Background
                    Rectangle {
                        anchors.fill: parent
                        radius: 20
                        color: Qt.rgba(0.08, 0.08, 0.11, 0.88)
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        // Header top specular
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 1
                            height: 18
                            radius: 18
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.08) }
                                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.00) }
                            }
                        }
                    }

                    Column {
                        id: bubbleCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        // Response Header
                        Item {
                            width: parent.width
                            height: 18

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Text {
                                    text: "✨"
                                    font.pixelSize: 12
                                }

                                Text {
                                    text: "Gemini Intelligence"
                                    color: "#00F0FF"
                                    font.family: "Open Runde"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "✕"
                                color: Qt.rgba(1, 1, 1, 0.45)
                                font.pixelSize: 11

                                TapHandler {
                                    onTapped: root.response = ""
                                }
                            }
                        }

                        // Scrollable response body
                        Flickable {
                            width: parent.width
                            height: Math.min(220, responseContent.implicitHeight)
                            contentWidth: width
                            contentHeight: responseContent.implicitHeight
                            clip: true

                            Text {
                                id: responseContent
                                width: parent.width
                                text: root.response !== "" ? root.response : I18n.tr("Thinking and analyzing...")
                                color: "white"
                                font.family: "Open Runde"
                                font.pixelSize: 13
                                lineHeight: 1.38
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }

    // Pulse timer for breathing animation
    property real pulsePhase: 0.0
    Timer {
        id: pulsingTimer
        interval: 33
        repeat: true
        running: root.isOpen && root.isThinking
        onTriggered: {
            root.pulsePhase += 0.15;
            if (root.pulsePhase > 62.8) root.pulsePhase = 0.0;
        }
    }
}
