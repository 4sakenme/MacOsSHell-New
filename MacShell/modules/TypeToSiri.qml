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

    // Running clock for GLSL flowing border animation
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
        prompt = "";
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

            // Click-through everywhere EXCEPT the pill and response popup
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

            // ── DRAGGABLE FLOATING CONTAINER (Bottom-Centered, 110px above Dock) ──
            Item {
                id: pillContainer
                z: 10

                // Centered horizontally, 110px above screen bottom (above Dock)
                width: 380
                height: 44 + (bubbleBox.visible ? (bubbleBox.height + 10) : 0)

                x: (win.width - width) / 2 + dragOffset.x
                y: (win.height - 44 - 110) - (bubbleBox.visible ? (bubbleBox.height + 10) : 0) + dragOffset.y

                // Drag offset tracking
                QtObject {
                    id: dragOffset
                    property real x: 0
                    property real y: 0
                }

                // Opacity & Scale entrance animation
                opacity: root.animProgress
                scale: 0.95 + 0.05 * root.animProgress

                // ── 1. POPUP PHẢN HỒI (NẰM NGAY PHÍA TRÊN THANH VIÊN THUỐC) ──
                Item {
                    id: bubbleBox
                    anchors.bottom: pillBox.top
                    anchors.bottomMargin: 10
                    width: parent.width
                    height: Math.min(260, Math.max(68, bubbleCol.implicitHeight + 24))
                    visible: root.response !== "" || root.isThinking
                    z: 5

                    // Glass Bubble Background (#E6121318 deep black glass)
                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: Qt.rgba(0.07, 0.075, 0.095, 0.90)
                        border.color: Qt.rgba(1, 1, 1, 0.14)
                        border.width: 1

                        // Inner specular highlight
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 1
                            height: 16
                            radius: 16
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.09) }
                                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.00) }
                            }
                        }
                    }

                    Column {
                        id: bubbleCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        // Header
                        Item {
                            width: parent.width
                            height: 16

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Text {
                                    text: "✨"
                                    font.pixelSize: 11
                                }

                                Text {
                                    text: "Apple Intelligence"
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

                        // Scrollable response text
                        Flickable {
                            width: parent.width
                            height: Math.min(200, responseContent.implicitHeight)
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
                                lineHeight: 1.35
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // ── 2. MINIMAL LIQUID GLASS PILL BAR (Height: 44px, Width: 380px) ──
                Item {
                    id: pillBox
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 44
                    z: 10

                    // Flowing Gradient Border Shader Effect (1px thin Apple Intelligence shimmer)
                    ShaderEffect {
                        id: flowingBorder
                        anchors.fill: parent
                        anchors.margins: -1.0

                        fragmentShader: Qt.resolvedUrl("flowingborder.frag.qsb")

                        property vector2d itemSize: Qt.vector2d(width, height)
                        property real u_time: root.animTime
                        property real borderWidth: 1.2
                        property real borderRadius: height * 0.5
                        property real isThinking: root.isThinking ? 1.0 : 0.0
                    }

                    // Main Glass Pill Background (#E6121318 deep black glass)
                    Rectangle {
                        id: glassBg
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.rgba(0.07, 0.075, 0.095, 0.90)
                        border.color: Qt.rgba(1, 1, 1, 0.16)
                        border.width: 1

                        // Inner subtle specular highlight at top
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 1
                            height: 20
                            radius: height / 2
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.00) }
                            }
                        }
                    }

                    // MouseArea for dragging the entire pill window
                    MouseArea {
                        id: dragHandler
                        anchors.fill: parent
                        z: 1

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

                    // Content Row: Dynamic SiriOrb Icon (28x28) + TextInput + Action Button
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 10
                        spacing: 8
                        z: 10

                        // Dynamic 3D Fluid Plasma SiriOrb (28x28px)
                        SiriOrb {
                            id: siriOrbIcon
                            width: 28; height: 28
                            anchors.verticalCenter: parent.verticalCenter
                            isProcessing: root.isThinking || (root.edgeGlow && root.edgeGlow.siriState === "speaking")
                            audioLevel: root.edgeGlow ? root.edgeGlow.effectiveAudioLevel : 0.0
                        }

                        // Text Input Field (Dual Mode: Voice Stream & Type Input)
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - siriOrbIcon.width - actionBtn.width - 26
                            height: parent.height

                            TextInput {
                                id: mainInput
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true

                                font.family: "Open Runde"
                                font.pixelSize: 13
                                font.weight: Font.Normal
                                color: "white"
                                selectionColor: "#00F0FF"
                                selectedTextColor: "#000000"

                                // Voice Streaming: Stream STT text automatically into input
                                Connections {
                                    target: root
                                    function onPromptChanged() {
                                        if (root.prompt !== "" && (!mainInput.activeFocus || mainInput.text === "")) {
                                            mainInput.text = root.prompt;
                                        }
                                    }
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
                                    font.pixelSize: 13
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
                            width: 24; height: 24; radius: 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: btnHover.hovered ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.08)
                            border.color: Qt.rgba(1, 1, 1, 0.12)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: root.isThinking ? "⋯" : (mainInput.text.length > 0 ? "↑" : "✕")
                                color: "white"
                                font.family: "Open Runde"
                                font.pixelSize: 12
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
            }
        }
    }
}
