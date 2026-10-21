import QtQuick
import QtQuick.Effects

Item {
    id: root

    // Public properties
    property bool active: false        // strictly false when parent dialog/window is closed to save 100% CPU/RAM
    property real audioLevel: 0.0      // 0.0 to 1.0 from mic or simulated
    property bool isProcessing: false  // true when AI is thinking or speaking
    property real animSpeed: 1.0       // base speed multiplier

    implicitWidth: 28
    implicitHeight: 28

    // Internal animation time
    property real animTime: 0.0

    FrameAnimation {
        running: root.active && root.visible && root.opacity > 0.01
        onTriggered: {
            root.animTime += 0.016 * root.animSpeed;
            if (root.animTime > 10000.0) root.animTime = 0.0;
        }
    }

    // Outer subtle diffuse glow layer
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * (root.isProcessing ? 1.25 : 1.10)
        height: width
        radius: width / 2
        opacity: root.isProcessing ? 0.35 : (0.15 + root.audioLevel * 0.25)

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#00F0FF" }
            GradientStop { position: 0.5; color: "#8A2BE2" }
            GradientStop { position: 1.0; color: "#FF2D55" }
        }

        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250 } }
    }

    // ── GLSL 3D FLUID PLASMA SHADER ──
    ShaderEffect {
        id: orbShader
        anchors.fill: parent
        visible: root.active && root.visible && root.opacity > 0.01

        fragmentShader: Qt.resolvedUrl("siriorb.frag.qsb")

        property vector2d itemSize: Qt.vector2d(width, height)
        property real u_time: root.animTime
        property real u_audioLevel: root.audioLevel
        property real isProcessing: root.isProcessing ? 1.0 : 0.0

        scale: root.isProcessing ? (1.0 + 0.06 * Math.sin(root.animTime * 6.0)) : (1.0 + root.audioLevel * 0.08)
        Behavior on scale { NumberAnimation { duration: 80 } }
    }
}

