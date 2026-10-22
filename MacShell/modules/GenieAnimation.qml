import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root

    // ── Input properties ──
    property var sourceRect: ({ x: 0, y: 0, width: 800, height: 600 })
    property var targetPoint: ({ x: 960, y: 1040 })
    property real progress: 0.0
    property var sourceTexture: null // toplevel capture source
    property string minimizeAnimation: "genie" // "genie", "scale", "none"
    property var targetScreen: null

    property bool active: false
    property bool isUnminimize: false
    property var onCompleteCallback: null

    // ── NumberAnimation as requested: 380ms Easing.InOutQuad ──
    NumberAnimation {
        id: anim
        target: root
        property: "progress"
        duration: 380
        easing.type: Easing.InOutQuad
        onFinished: root.finishAnimation()
    }

    function startMinimize(rect, dockPt, toplevel, screenObj, callback) {
        if (minimizeAnimation === "none") {
            if (typeof callback === "function") callback();
            return;
        }
        anim.stop();
        sourceRect = rect;
        targetPoint = dockPt;
        sourceTexture = toplevel;
        targetScreen = screenObj;
        isUnminimize = false;
        onCompleteCallback = callback;
        progress = 0.0;
        active = true;

        anim.from = 0.0;
        anim.to = 1.0;
        anim.restart();
    }

    function startUnminimize(rect, dockPt, toplevel, screenObj, callback) {
        if (minimizeAnimation === "none") {
            if (typeof callback === "function") callback();
            return;
        }
        anim.stop();
        sourceRect = rect;
        targetPoint = dockPt;
        sourceTexture = toplevel;
        targetScreen = screenObj;
        isUnminimize = true;
        onCompleteCallback = callback;
        progress = 1.0;
        active = true;

        anim.from = 1.0;
        anim.to = 0.0;
        anim.restart();
    }

    function finishAnimation() {
        active = false;
        sourceTexture = null; // Clean up snapshot texture resource immediately (0% RAM/CPU)
        var cb = onCompleteCallback;
        onCompleteCallback = null;
        if (typeof cb === "function") {
            cb();
        }
    }

    // ── Fullscreen Overlay on each screen (100% click-through, 0% CPU when inactive) ──
    Variants {
        id: screenVariants
        model: Quickshell.screens

        PanelWindow {
            id: overlayWin
            required property var modelData
            screen: modelData

            // Only visible on the active screen during the animation
            visible: root.active && (root.targetScreen === null || root.targetScreen.name === modelData.name)
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {} // 100% click-through
            WlrLayershell.namespace: "macshell-genie"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Item {
                anchors.fill: parent

                // Off-screen container to guarantee scene graph paints the snapshot into texture
                Item {
                    x: -99999
                    y: -99999
                    width: Math.max(1, root.sourceRect.width || 800)
                    height: Math.max(1, root.sourceRect.height || 600)

                    ScreencopyView {
                        id: snapshotView
                        anchors.fill: parent
                        live: false
                        captureSource: root.active ? root.sourceTexture : null
                        onCaptureSourceChanged: {
                            if (captureSource !== null && typeof captureFrame === "function") {
                                captureFrame();
                            }
                        }
                    }
                }

                ShaderEffectSource {
                    id: effectSrc
                    sourceItem: snapshotView
                    hideSource: true
                    live: true
                }

                ShaderEffect {
                    anchors.fill: parent
                    fragmentShader: Qt.resolvedUrl("genie.frag.qsb")
                    visible: root.active && root.minimizeAnimation !== "none"

                    property real qt_Opacity: 1.0
                    property vector2d screenSize: Qt.vector2d(overlayWin.width, overlayWin.height)
                    property vector4d sourceRect: Qt.vector4d(
                        root.sourceRect.x || 0,
                        root.sourceRect.y || 0,
                        root.sourceRect.width || 800,
                        root.sourceRect.height || 600
                    )
                    property vector2d targetPoint: Qt.vector2d(
                        root.targetPoint.x || 0,
                        root.targetPoint.y || 0
                    )
                    property real progress: root.progress
                    property real mode: root.minimizeAnimation === "scale" ? 1.0 : 0.0
                    property var sourceTexture: effectSrc
                }
            }
        }
    }
}
