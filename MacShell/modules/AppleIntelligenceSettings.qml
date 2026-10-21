import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../I18n.js" as I18n

Column {
    id: root

    property var t: null    // theme palette from MacDock
    property var hub: null  // shared hub

    spacing: 14
    width: parent ? parent.width : 520

    // Settings state
    property bool siriEnabled: true
    property bool wakeWordEnabled: true
    property string language: "vi-VN"
    property string voice: "vi"
    property real edgeGlowIntensity: 1.0
    property string geminiModel: "gemini-2.5-flash"
    property string apiKey: ""
    property bool isLoaded: false

    readonly property string settingsPath: Quickshell.env("HOME") + "/.config/quickshell/MacShell/siri_settings.json"
    readonly property string geminiConfigPath: Quickshell.env("HOME") + "/.config/quickshell/MacShell/gemini_config.json"

    // FileView for settings persistence
    FileView {
        id: siriStore
        path: root.settingsPath
        printErrors: false
        onLoaded: {
            try {
                var o = JSON.parse(text());
                if (o.enabled !== undefined) root.siriEnabled = o.enabled;
                if (o.wake_word_enabled !== undefined) root.wakeWordEnabled = o.wake_word_enabled;
                if (o.language !== undefined) root.language = o.language;
                if (o.voice !== undefined) root.voice = o.voice;
                if (o.edge_glow_intensity !== undefined) root.edgeGlowIntensity = o.edge_glow_intensity;
                if (o.model !== undefined) root.geminiModel = o.model;
                if (o.api_key !== undefined) root.apiKey = o.api_key;
            } catch (e) {
                console.log("[SiriSettings] Parse error:", e);
            }
            root.isLoaded = true;
        }
        onLoadFailed: {
            root.isLoaded = true;
            // Write defaults
            root.saveSettings();
        }
    }

    Timer {
        id: saveDebounce
        interval: 350
        repeat: false
        onTriggered: root.writeToDisk()
    }

    function saveSettings() {
        if (!root.isLoaded) return;
        saveDebounce.restart();
    }

    function writeToDisk() {
        var o = {
            enabled: root.siriEnabled,
            wake_word_enabled: root.wakeWordEnabled,
            wake_words: ["hey siri", "siri", "ơi siri"],
            language: root.language,
            voice: root.voice,
            edge_glow_intensity: root.edgeGlowIntensity,
            model: root.geminiModel,
            api_key: root.apiKey
        };
        siriStore.setText(JSON.stringify(o, null, 2));

        // Sync with gemini_config.json
        geminiStore.setText(JSON.stringify({
            api_key: root.apiKey !== "" ? root.apiKey : "YOUR_GEMINI_API_KEY_HERE",
            model: root.geminiModel
        }, null, 2));
    }

    FileView {
        id: geminiStore
        path: root.geminiConfigPath
        printErrors: false
    }

    // Process to test API
    Process {
        id: testApiProc
        property string statusMsg: ""
        property bool testing: false

        stdout: StdioCollector {
            onStreamFinished: {
                testApiProc.testing = false;
                if (text.indexOf("Error") >= 0 || text.indexOf("error") >= 0) {
                    testApiProc.statusMsg = I18n.tr("API Connection Failed");
                } else {
                    testApiProc.statusMsg = I18n.tr("API Connected Successfully!");
                }
            }
        }
        onExited: {
            testApiProc.testing = false;
        }
    }

    function runApiTest() {
        testApiProc.statusMsg = I18n.tr("Testing connection...");
        testApiProc.testing = true;
        testApiProc.command = [
            "/home/kuro/.config/quickshell/MacShell/venv/bin/python",
            "/home/kuro/.config/quickshell/MacShell/scripts/siri_daemon.py",
            "--test-api"
        ];
        testApiProc.running = true;
    }

    // ── HEADER HERO BANNER ──
    Rectangle {
        width: parent.width
        height: 84
        radius: 14
        color: t ? t.card : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: t ? t.cardBorder : Qt.rgba(1, 1, 1, 0.1)

        Row {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 16

            SiriOrb {
                width: 48; height: 48
                anchors.verticalCenter: parent.verticalCenter
                isProcessing: true
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    text: "Apple Intelligence & Siri"
                    color: t ? t.text : "white"
                    font.family: t ? t.fam : "Open Runde"
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }

                Text {
                    text: I18n.tr("Supercharge your Linux desktop with on-device Siri & Gemini AI")
                    color: t ? t.text2 : "#8E8E93"
                    font.family: t ? t.fam : "Open Runde"
                    font.pixelSize: 12
                }
            }
        }
    }

    // ── SECTION 1: SYSTEM TOGGLES ──
    Rectangle {
        width: parent.width
        height: toggleCol.implicitHeight + 20
        radius: 12
        color: t ? t.card : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: t ? t.cardBorder : Qt.rgba(1, 1, 1, 0.1)

        Column {
            id: toggleCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            // Siri Master Switch
            Item {
                width: parent.width
                height: 36

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: I18n.tr("Enable Apple Intelligence & Siri"); color: t ? t.text : "white"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { text: I18n.tr("Enable voice assistant and Type to Siri floating pill"); color: t ? t.text2 : "#8E8E93"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 11 }
                }

                Switch {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.siriEnabled
                    onToggled: { root.siriEnabled = checked; root.saveSettings(); }
                }
            }

            Rectangle { width: parent.width; height: 1; color: t ? t.cardBorder : Qt.rgba(1, 1, 1, 0.08) }

            // Wake word switch
            Item {
                width: parent.width
                height: 36

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: I18n.tr("Listen for \"Hey Siri\""); color: t ? t.text : "white"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { text: I18n.tr("Offline wake word detection via background daemon"); color: t ? t.text2 : "#8E8E93"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 11 }
                }

                Switch {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.wakeWordEnabled
                    onToggled: { root.wakeWordEnabled = checked; root.saveSettings(); }
                }
            }
        }
    }

    // ── SECTION 2: LANGUAGE & VOICE ──
    Rectangle {
        width: parent.width
        height: langCol.implicitHeight + 20
        radius: 12
        color: t ? t.card : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: t ? t.cardBorder : Qt.rgba(1, 1, 1, 0.1)

        Column {
            id: langCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Item {
                width: parent.width
                height: 36

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: I18n.tr("Assistant Language"); color: t ? t.text : "white"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { text: I18n.tr("Primary speech recognition and TTS language"); color: t ? t.text2 : "#8E8E93"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 11 }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Rectangle {
                        width: 90; height: 28; radius: 6
                        color: root.language === "vi-VN" ? (t ? t.accent : "#0A84FF") : (t ? Qt.rgba(1,1,1,0.08) : "#2C2C2E")
                        Text { anchors.centerIn: parent; text: "Tiếng Việt"; color: "white"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 12 }
                        TapHandler { onTapped: { root.language = "vi-VN"; root.voice = "vi"; root.saveSettings(); } }
                    }

                    Rectangle {
                        width: 90; height: 28; radius: 6
                        color: root.language === "en-US" ? (t ? t.accent : "#0A84FF") : (t ? Qt.rgba(1,1,1,0.08) : "#2C2C2E")
                        Text { anchors.centerIn: parent; text: "English (US)"; color: "white"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 12 }
                        TapHandler { onTapped: { root.language = "en-US"; root.voice = "en-us+f3"; root.saveSettings(); } }
                    }
                }
            }
        }
    }

    // ── SECTION 3: VISUAL EFFECTS & EDGE GLOW ──
    Rectangle {
        width: parent.width
        height: glowCol.implicitHeight + 20
        radius: 12
        color: t ? t.card : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: t ? t.cardBorder : Qt.rgba(1, 1, 1, 0.1)

        Column {
            id: glowCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Item {
                width: parent.width
                height: 38

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: I18n.tr("Edge Glow Intensity"); color: t ? t.text : "white"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { text: I18n.tr("Width and brightness of screen border wave: ") + Math.round(root.edgeGlowIntensity * 100) + "%"; color: t ? t.text2 : "#8E8E93"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 11 }
                }

                Slider {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 140
                    from: 0.2
                    to: 1.5
                    value: root.edgeGlowIntensity
                    onMoved: {
                        root.edgeGlowIntensity = value;
                        root.saveSettings();
                    }
                }
            }
        }
    }

    // ── SECTION 4: GOOGLE GEMINI AI CONFIGURATION ──
    Rectangle {
        width: parent.width
        height: geminiCol.implicitHeight + 24
        radius: 12
        color: t ? t.card : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: t ? t.cardBorder : Qt.rgba(1, 1, 1, 0.1)

        Column {
            id: geminiCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 14

            // Model Selection
            Item {
                width: parent.width
                height: 36

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: I18n.tr("Gemini AI Model"); color: t ? t.text : "white"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { text: I18n.tr("Google Generative AI model engine"); color: t ? t.text2 : "#8E8E93"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 11 }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Rectangle {
                        width: 110; height: 28; radius: 6
                        color: root.geminiModel === "gemini-2.5-flash" ? (t ? t.accent : "#0A84FF") : (t ? Qt.rgba(1,1,1,0.08) : "#2C2C2E")
                        Text { anchors.centerIn: parent; text: "2.5 Flash (Fast)"; color: "white"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 11; font.weight: Font.Medium }
                        TapHandler { onTapped: { root.geminiModel = "gemini-2.5-flash"; root.saveSettings(); } }
                    }

                    Rectangle {
                        width: 110; height: 28; radius: 6
                        color: root.geminiModel === "gemini-2.5-pro" ? (t ? t.accent : "#0A84FF") : (t ? Qt.rgba(1,1,1,0.08) : "#2C2C2E")
                        Text { anchors.centerIn: parent; text: "2.5 Pro (Deep)"; color: "white"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 11; font.weight: Font.Medium }
                        TapHandler { onTapped: { root.geminiModel = "gemini-2.5-pro"; root.saveSettings(); } }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: t ? t.cardBorder : Qt.rgba(1, 1, 1, 0.08) }

            // API Key Input
            Column {
                width: parent.width
                spacing: 6

                Text { text: I18n.tr("Gemini API Key"); color: t ? t.text : "white"; font.family: t ? t.fam : "Open Runde"; font.pixelSize: 13; font.weight: Font.DemiBold }

                Row {
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: parent.width - 100
                        height: 32
                        radius: 6
                        color: t ? Qt.rgba(0, 0, 0, 0.25) : "#1C1C1E"
                        border.width: 1
                        border.color: t ? t.cardBorder : Qt.rgba(1, 1, 1, 0.12)

                        TextInput {
                            id: keyInput
                            anchors.fill: parent
                            anchors.margins: 8
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: t ? t.fam : "Open Runde"
                            font.pixelSize: 12
                            color: "white"
                            echoMode: TextInput.Password
                            text: root.apiKey
                            onTextChanged: {
                                root.apiKey = text;
                                root.saveSettings();
                            }
                        }
                    }

                    Rectangle {
                        width: 92; height: 32; radius: 6
                        color: testApiProc.testing ? Qt.rgba(1,1,1,0.2) : (t ? t.accent : "#0A84FF")
                        Text {
                            anchors.centerIn: parent
                            text: testApiProc.testing ? "..." : I18n.tr("Test Key")
                            color: "white"
                            font.family: t ? t.fam : "Open Runde"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        TapHandler {
                            onTapped: root.runApiTest()
                        }
                    }
                }

                Text {
                    visible: testApiProc.statusMsg !== ""
                    text: testApiProc.statusMsg
                    color: testApiProc.statusMsg.indexOf("Failed") >= 0 ? "#FF453A" : "#30D158"
                    font.family: t ? t.fam : "Open Runde"
                    font.pixelSize: 11
                }
            }
        }
    }
}
