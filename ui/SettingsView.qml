pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.services
import qs.ui.widgets

// Settings content shown inside the morphed card. Tabs are chosen by the round
// buttons beside the card (see AnswerWindow); `tab` indexes `tabs`.
// Every control writes straight into Config.options (saved + hot-reloaded).
Item {
    id: root

    property int tab: 0
    readonly property var tabs: ["General", "Models", "Appearance"]

    readonly property var theme: Config.options.theme
    readonly property var win: Config.options.window
    readonly property var orc: Config.options.openrouter
    readonly property var cap: Config.options.capture

    // Configured models, always including the active one.
    readonly property var modelList: {
        const l = (root.orc.models || []).filter(m => typeof m === "string" && m);
        if (root.orc.model && !l.includes(root.orc.model)) l.unshift(root.orc.model);
        return l;
    }

    // Set background/foreground and re-derive the in-between tones (surface, muted)
    // so controls stay visible on any palette.
    function setBaseColor(key: string, value: string) {
        root.theme[key] = value;
        const bg = root.theme.background, fg = root.theme.foreground;
        root.theme.surface = Qt.tint(bg, Qt.alpha(fg, 0.11)).toString();
        root.theme.muted = Qt.tint(bg, Qt.alpha(fg, 0.55)).toString();
    }

    function resetColors() {
        root.theme.background = "#000000";
        root.theme.foreground = "#e8e8ee";
        root.theme.accent = "#8ab4ff";
        root.theme.surface = "#1f1f26";
        root.theme.muted = "#8a8a99";
    }

    function addModel(id: string) {
        id = id.trim();
        if (!id) return;
        const l = root.modelList.slice();
        if (!l.includes(id)) l.push(id);
        root.orc.models = l;
        if (!root.orc.model) root.orc.model = id;
    }

    // Built-in models not currently in the list.
    readonly property var missingPresets: Models.ids.filter(id => !root.modelList.includes(id))

    function addPresets() {
        root.orc.models = root.modelList.concat(root.missingPresets);
    }

    function removeModel(id: string) {
        const l = root.modelList.filter(m => m !== id);
        root.orc.models = l;
        if (root.orc.model === id) root.orc.model = l.length ? l[0] : "";
    }

    // Only works while the window has keyboard focus (click into it first).
    Shortcut {
        sequence: "Escape"
        onActivated: Solver.dismiss()
    }

    Text {
        id: title
        anchors.left: parent.left
        anchors.top: parent.top
        text: root.tabs[root.tab]
        color: root.theme.foreground
        font.family: root.theme.fontFamily || font.family
        font.pixelSize: root.theme.fontSize + 3
        font.weight: Font.DemiBold
    }

    Flickable {
        id: flick
        anchors.top: title.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: page.item ? page.item.implicitHeight : 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Loader {
            id: page
            width: flick.width
            sourceComponent: [generalPage, modelsPage, appearancePage][root.tab]
            onLoaded: flick.contentY = 0
        }
    }

    // ── General ────────────────────────────────────────────────────
    Component {
        id: generalPage

        Column {
            spacing: 8

            SectionLabel { text: "OpenRouter API key" }
            Field {
                width: parent.width
                secret: true
                value: root.orc.apiKey
                placeholder: Quickshell.env("OPENROUTER_API_KEY") ? "Using $OPENROUTER_API_KEY" : "sk-or-v1-…"
                onCommitted: t => root.orc.apiKey = t.trim()
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.StyledText
                text: `Saved to the config file. Get a key at <a href="https://openrouter.ai/keys">openrouter.ai/keys</a>.`
                color: root.theme.muted
                linkColor: root.theme.accent
                font.family: root.theme.fontFamily || font.family
                font.pixelSize: root.theme.fontSize - 2
                onLinkActivated: link => Qt.openUrlExternally(link)
                HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
            }

            SectionLabel { text: "Endpoint" }
            Field {
                width: parent.width
                value: root.orc.endpoint
                placeholder: "https://openrouter.ai/api/v1/chat/completions"
                onCommitted: t => root.orc.endpoint = t.trim() || "https://openrouter.ai/api/v1/chat/completions"
            }

            SectionLabel { text: "Capture" }
            Segmented {
                options: [
                    { label: "Focused screen", value: "focused" },
                    { label: "All screens", value: "all" },
                    { label: "Region", value: "region" }
                ]
                current: root.cap.mode
                onPicked: v => root.cap.mode = v
            }

            SectionLabel { text: "Behavior" }
            Toggle {
                width: parent.width
                label: "Copy answers automatically"
                checked: root.win.copyAnswer
                onToggled: c => root.win.copyAnswer = c
            }
            Stepper {
                width: parent.width
                label: "Hub timeout"
                suffix: "s"
                from: 0; to: 30; step: 1
                value: root.win.hubTimeoutMs / 1000
                onMoved: v => root.win.hubTimeoutMs = Math.round(v * 1000)
            }
            Stepper {
                width: parent.width
                label: "Auto-hide answer (0 = never)"
                suffix: "s"
                from: 0; to: 120; step: 5
                value: root.win.autoHideMs / 1000
                onMoved: v => root.win.autoHideMs = Math.round(v * 1000)
            }
        }
    }

    // ── Models ─────────────────────────────────────────────────────
    Component {
        id: modelsPage

        Column {
            spacing: 6

            SectionLabel { text: "Click a model to make it active" }

            Repeater {
                model: root.modelList

                Rectangle {
                    id: row
                    required property string modelData
                    readonly property bool active: modelData === root.orc.model

                    width: parent.width
                    height: 34
                    radius: Math.min(root.theme.radius, height / 2)
                    color: rowMouse.containsMouse || row.active ? root.theme.surface : "transparent"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.orc.model = row.modelData
                    }

                    // radio dot
                    Rectangle {
                        id: radio
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10
                        height: 10
                        radius: 5
                        color: row.active ? root.theme.accent : "transparent"
                        border.width: row.active ? 0 : 1.5
                        border.color: root.theme.muted
                    }

                    Text {
                        id: modelName
                        anchors.left: radio.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, provider.x - x - 8)
                        text: Models.nameOf(row.modelData)
                        elide: Text.ElideRight
                        color: row.active ? root.theme.foreground : root.theme.muted
                        font.family: root.theme.fontFamily || font.family
                        font.pixelSize: root.theme.fontSize
                    }

                    // provider (or full id on hover)
                    Text {
                        id: provider
                        anchors.right: remove.visible ? remove.left : parent.right
                        anchors.rightMargin: remove.visible ? 10 : 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, row.width * 0.55)
                        text: rowMouse.containsMouse || removeMouse.containsMouse
                            ? row.modelData : Models.providerOf(row.modelData)
                        elide: Text.ElideLeft
                        horizontalAlignment: Text.AlignRight
                        color: root.theme.muted
                        opacity: 0.7
                        font.family: root.theme.fontFamily || font.family
                        font.pixelSize: root.theme.fontSize - 3
                    }

                    Text {
                        id: remove
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        visible: rowMouse.containsMouse || removeMouse.containsMouse
                        text: "✕"
                        color: removeMouse.containsMouse ? root.theme.error : root.theme.muted
                        font.pixelSize: root.theme.fontSize - 2

                        MouseArea {
                            id: removeMouse
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.removeModel(row.modelData)
                        }
                    }
                }
            }

            Text {
                visible: root.modelList.length === 0
                text: "No models yet — add one below."
                color: root.theme.muted
                font.family: root.theme.fontFamily || font.family
                font.pixelSize: root.theme.fontSize
            }

            SectionLabel { text: "Add model" }
            Item {
                width: parent.width
                height: 32

                Field {
                    id: addField
                    anchors.left: parent.left
                    anchors.right: addBtn.left
                    anchors.rightMargin: 6
                    height: parent.height
                    commitOnBlur: false
                    placeholder: "provider/model-id"
                    onAccepted: t => { root.addModel(t); addField.text = ""; }
                }
                Rectangle {
                    id: addBtn
                    anchors.right: parent.right
                    width: 32
                    height: 32
                    radius: 16
                    color: addMouse.containsMouse ? root.theme.surface : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: addMouse.containsMouse ? root.theme.foreground : root.theme.muted
                        font.pixelSize: root.theme.fontSize + 4
                    }
                    MouseArea {
                        id: addMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.addModel(addField.text); addField.text = ""; }
                    }
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.StyledText
                text: `Use any vision-capable model id — <a href="https://openrouter.ai/models?input_modalities=image">browse models</a>.`
                    + (root.missingPresets.length
                        ? ` <a href="presets">Restore built-in models</a> (${root.missingPresets.length}).` : "")
                color: root.theme.muted
                linkColor: root.theme.accent
                font.family: root.theme.fontFamily || font.family
                font.pixelSize: root.theme.fontSize - 2
                onLinkActivated: link => link === "presets" ? root.addPresets() : Qt.openUrlExternally(link)
                HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
            }
        }
    }

    // ── Appearance ─────────────────────────────────────────────────
    Component {
        id: appearancePage

        Column {
            spacing: 6

            SectionLabel { text: "Position" }
            // Miniature screen: click a corner.
            Rectangle {
                id: screenPick
                readonly property var corners: ["top-left", "top-right", "bottom-left", "bottom-right"]
                width: 112
                height: 66
                radius: 8
                color: "transparent"
                border.width: 1.5
                border.color: root.theme.surface

                Repeater {
                    model: screenPick.corners

                    Rectangle {
                        id: corner
                        required property string modelData
                        readonly property bool active: root.win.position === modelData
                        readonly property bool hovered: cornerMouse.containsMouse

                        width: 26
                        height: 18
                        radius: 5
                        x: modelData.endsWith("left") ? 6 : screenPick.width - width - 6
                        y: modelData.startsWith("top") ? 6 : screenPick.height - height - 6
                        color: active ? root.theme.accent : hovered ? Qt.lighter(root.theme.surface, 1.6) : root.theme.surface

                        Behavior on color { ColorAnimation { duration: 120 } }

                        MouseArea {
                            id: cornerMouse
                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.win.position = corner.modelData
                        }
                    }
                }
            }

            Item {
                width: parent.width
                implicitHeight: colorsLabel.implicitHeight

                SectionLabel { id: colorsLabel; text: "Colors" }
                Text {
                    readonly property bool dirty: root.theme.background !== "#000000"
                                                  || root.theme.foreground !== "#e8e8ee"
                                                  || root.theme.accent !== "#8ab4ff"
                                                  || root.theme.surface !== "#1f1f26"
                                                  || root.theme.muted !== "#8a8a99"
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    visible: dirty
                    text: "reset"
                    color: resetMouse.containsMouse ? root.theme.foreground : root.theme.muted
                    font.family: root.theme.fontFamily || font.family
                    font.pixelSize: root.theme.fontSize - 2

                    MouseArea {
                        id: resetMouse
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.resetColors()
                    }
                }
            }
            ColorField {
                width: parent.width
                label: "Background"
                value: root.theme.background
                presets: ["#000000", "#0b0b0f", "#121218", "#1a1b26", "#1e1e2e", "#24273a", "#282a36", "#2e3440", "#f4f4f6", "#ffffff"]
                onPicked: c => root.setBaseColor("background", c)
            }
            ColorField {
                width: parent.width
                label: "Foreground"
                value: root.theme.foreground
                presets: ["#e8e8ee", "#ffffff", "#cdd6f4", "#c0caf5", "#d8dee9", "#ebdbb2", "#a9b1d6", "#4c4f69", "#1a1a1f", "#000000"]
                onPicked: c => root.setBaseColor("foreground", c)
            }
            ColorField {
                width: parent.width
                label: "Accent"
                value: root.theme.accent
                presets: ["#8ab4ff", "#7aa2f7", "#89dceb", "#94e2d5", "#a6e3a1", "#f9e2af", "#fab387", "#f38ba8", "#f5c2e7", "#cba6f7"]
                onPicked: c => root.theme.accent = c
            }

            SectionLabel { text: "Size & shape" }
            Stepper {
                width: parent.width
                label: "Corner roundness"
                suffix: "px"
                from: 0; to: 40; step: 1
                value: root.theme.radius
                onMoved: v => root.theme.radius = Math.round(v)
            }
            Stepper {
                width: parent.width
                label: "Width"
                suffix: "px"
                from: 280; to: 1000; step: 10
                value: root.win.width
                onMoved: v => root.win.width = Math.round(v)
            }
            Stepper {
                width: parent.width
                label: "Max height"
                suffix: "px"
                from: 380; to: 1200; step: 10
                value: root.win.maxHeight
                onMoved: v => root.win.maxHeight = Math.round(v)
            }
            Stepper {
                width: parent.width
                label: "Screen margin"
                suffix: "px"
                from: 0; to: 120; step: 2
                value: root.win.margin
                onMoved: v => root.win.margin = Math.round(v)
            }

            SectionLabel { text: "Text" }
            Stepper {
                width: parent.width
                label: "Font size"
                suffix: "px"
                from: 9; to: 28; step: 1
                value: root.theme.fontSize
                onMoved: v => root.theme.fontSize = Math.round(v)
            }
            Toggle {
                width: parent.width
                label: "Render Markdown"
                checked: root.win.markdown
                onToggled: c => root.win.markdown = c
            }
            Toggle {
                width: parent.width
                label: "Render LaTeX math"
                checked: Config.options.latex.enabled
                // LaTeX lives inside the Markdown renderer.
                enabled: root.win.markdown
                opacity: enabled ? 1 : 0.4
                onToggled: c => Config.options.latex.enabled = c
            }

            SectionLabel { text: `Font — ${root.theme.fontFamily || "system default"}` ; width: parent.width }
            Field {
                id: fontSearch
                width: parent.width
                commitOnBlur: false
                placeholder: "Search fonts"
            }
            Rectangle {
                width: parent.width
                height: 168
                radius: Math.min(root.theme.radius, 12)
                color: "transparent"
                border.width: 1
                border.color: root.theme.surface
                clip: true

                ListView {
                    id: fontList
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    readonly property var families: [""].concat(Qt.fontFamilies())
                    model: {
                        const q = fontSearch.text.trim().toLowerCase();
                        return q ? fontList.families.filter(f => f && f.toLowerCase().includes(q)) : fontList.families;
                    }

                    delegate: Rectangle {
                        id: fontRow
                        required property string modelData
                        readonly property bool active: modelData === root.theme.fontFamily

                        width: ListView.view.width
                        height: 28
                        radius: 6
                        color: active ? root.theme.surface : fontMouse.containsMouse ? Qt.alpha(root.theme.surface, 0.6) : "transparent"

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: fontRow.modelData || "System default"
                            color: fontRow.active ? root.theme.foreground : root.theme.muted
                            font.family: fontRow.modelData || font.family
                            font.pixelSize: root.theme.fontSize
                        }

                        MouseArea {
                            id: fontMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.theme.fontFamily = fontRow.modelData
                        }
                    }
                }
            }
        }
    }
}
