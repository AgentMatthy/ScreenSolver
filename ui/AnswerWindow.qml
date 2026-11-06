pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// Minimal floating overlay. One black shape that morphs between modes:
//   hub         → a still dot in the anchored corner; hovering it pops out
//                 round buttons: solve (▶) and settings (⚙). Times out after window.hubTimeoutMs.
//   thinking    → the dot, gently pulsing (scale only).
//   done/error  → the dot morphs into the answer card; copy / retry / close buttons beside it.
//   settings    → the dot morphs into the settings card; the buttons beside it are tabs
//                 (General / Models / Appearance) followed by close.
//
// The surface has a fixed size (card + buttons at their largest) so the morph doesn't
// have to resize it every frame; an input mask keeps the transparent parts click-through.
PanelWindow {
    id: root

    readonly property var win: Config.options.window
    readonly property var theme: Config.options.theme
    readonly property string pos: win.position
    readonly property string mode: Solver.state === "settings" ? "settings"
        : (Solver.state === "done" || Solver.state === "error") ? "answer"
        : "dot"

    readonly property bool expanded: mode !== "dot"
    readonly property bool hubOpen: Solver.state === "hub" && hover.hovered
    // Buttons sit on the side facing the screen centre (left, unless anchored left).
    readonly property bool buttonsOnLeft: !pos.endsWith("left")
    // "top" | "bottom" | "center"
    readonly property string vAlign: pos.startsWith("top") ? "top" : pos.startsWith("bottom") ? "bottom" : "center"

    readonly property int dotSize: 14
    readonly property int btnSize: 30
    readonly property int gap: 8
    readonly property int pad: 14
    readonly property int morphMs: 320
    readonly property int settingsHeight: Math.min(root.win.maxHeight, 460)

    // Whichever button column is currently shown (null = none).
    readonly property Item activeButtons: root.hubOpen ? hubButtons
        : root.mode === "answer" ? answerButtons
        : root.mode === "settings" ? tabButtons
        : null

    screen: Quickshell.screens.find(s => s.name === Solver.monitor) ?? Quickshell.screens[0]

    WlrLayershell.namespace: "screensolver"
    WlrLayershell.layer: WlrLayer.Overlay
    // Never take keyboard focus — except in settings, which has text fields: there it
    // becomes OnDemand (focused when clicked). Keyboard control is otherwise via global IPC binds.
    WlrLayershell.keyboardFocus: root.mode === "settings" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    focusable: root.mode === "settings"
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        top: root.pos.startsWith("top")
        bottom: root.pos.startsWith("bottom")
        left: root.pos.endsWith("left")
        right: root.pos.endsWith("right")
    }
    margins {
        top: root.win.margin
        bottom: root.win.margin
        left: root.win.margin
        right: root.win.margin
    }

    implicitWidth: root.win.width + root.gap + root.btnSize
    implicitHeight: Math.max(root.win.maxHeight, tabButtons.implicitHeight)

    // Only the dot/card and the visible buttons receive input; the rest is click-through.
    // In hub mode the hit zone also bridges the gap between dot and buttons so hover holds.
    mask: Region {
        item: Solver.state === "hub" ? hubZone : card
        Region { item: root.activeButtons }
    }

    Timer {
        id: autoHide
        interval: Math.max(0, root.win.autoHideMs)
        running: interval > 0 && Solver.state === "done" && !hover.hovered
        onTriggered: Solver.dismiss()
    }

    Timer {
        id: hubTimeout
        interval: Math.max(0, root.win.hubTimeoutMs)
        running: interval > 0 && Solver.state === "hub" && !hover.hovered
        onTriggered: Solver.dismiss()
    }

    Item {
        id: stage
        anchors.fill: parent

        HoverHandler { id: hover }

        // A btnSize square in the anchored corner that the dot sits centred in,
        // so the dot lines up with the button column.
        readonly property real slotX: root.buttonsOnLeft ? width - root.btnSize : 0
        readonly property real slotY: root.vAlign === "top" ? 0
            : root.vAlign === "bottom" ? height - root.btnSize
            : (height - root.btnSize) / 2

        // Hub hit zone: the slot, plus the gap and button column while open.
        Item {
            id: hubZone
            readonly property real extra: root.hubOpen ? root.gap + hubButtons.width : 0
            x: root.buttonsOnLeft ? stage.slotX - extra : stage.slotX
            y: Math.min(stage.slotY, root.hubOpen ? hubButtons.y : stage.slotY)
            width: root.btnSize + extra
            height: root.hubOpen ? Math.max(root.btnSize, hubButtons.height) : root.btnSize
        }

        // ── Dot / card ──────────────────────────────────────────────
        Rectangle {
            id: card

            readonly property real fullHeight: root.mode === "settings"
                ? root.settingsHeight
                : Math.min(answerText.implicitHeight + 2 * root.pad, root.win.maxHeight)
            // Dot is centred in the slot; the card sits flush in the corner.
            property real inset: root.expanded ? 0 : (root.btnSize - root.dotSize) / 2

            width: root.expanded ? root.win.width : root.dotSize
            height: root.expanded ? fullHeight : root.dotSize
            radius: root.expanded ? root.theme.radius : root.dotSize / 2
            x: root.buttonsOnLeft ? parent.width - width - inset : inset
            y: root.vAlign === "top" ? inset
             : root.vAlign === "bottom" ? parent.height - height - inset
             : (parent.height - height) / 2
            color: root.theme.background
            clip: true

            Behavior on width { NumberAnimation { duration: root.morphMs; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: root.morphMs; easing.type: Easing.OutCubic } }
            Behavior on radius { NumberAnimation { duration: root.morphMs; easing.type: Easing.OutCubic } }
            Behavior on inset { NumberAnimation { duration: root.morphMs; easing.type: Easing.OutCubic } }

            // Pulse while thinking: scale in and out a little, never fading. The hub dot is still.
            SequentialAnimation on scale {
                running: Solver.state === "thinking"
                loops: Animation.Infinite
                onRunningChanged: if (!running) settle.restart()
                NumberAnimation { to: 0.7; duration: 650; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
            }
            NumberAnimation { id: settle; target: card; property: "scale"; to: 1; duration: 150 }

            // Fixed-size content pinned to the card's anchored corner, revealed as the card grows.
            Item {
                id: body
                width: root.win.width
                height: card.fullHeight
                x: root.buttonsOnLeft ? card.width - width : 0
                y: root.vAlign === "top" ? 0
                 : root.vAlign === "bottom" ? card.height - height
                 : (card.height - height) / 2
                opacity: root.expanded ? 1 : 0
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: root.morphMs } }

                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.margins: root.pad
                    visible: root.mode === "answer"
                    contentWidth: width
                    contentHeight: answerText.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    TextEdit {
                        id: answerText
                        width: flick.width
                        readOnly: true
                        selectByMouse: true
                        activeFocusOnPress: false
                        wrapMode: TextEdit.Wrap
                        textFormat: Solver.state === "done" && root.win.markdown
                            ? TextEdit.MarkdownText : TextEdit.PlainText
                        text: Solver.state === "error" ? Solver.error : Solver.answer
                        color: Solver.state === "error" ? root.theme.error : root.theme.foreground
                        selectionColor: root.theme.accent
                        selectedTextColor: root.theme.background
                        font.family: root.theme.fontFamily || font.family
                        font.pixelSize: root.theme.fontSize + 1
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }

                Loader {
                    id: settingsLoader
                    anchors.fill: parent
                    anchors.margins: root.pad + 2
                    active: root.mode === "settings"
                    sourceComponent: SettingsView {}
                }
            }
        }

        // ── Button columns beside the card (only one is shown at a time) ─
        ButtonColumn {
            id: hubButtons
            shown: root.hubOpen

            IconButton {
                shown: hubButtons.shown
                text: "▶"
                glyphSize: root.theme.fontSize - 3
                onClicked: Solver.solve()
            }
            IconButton {
                shown: hubButtons.shown
                text: "⚙\uFE0E"
                onClicked: Solver.settings()
            }
        }

        ButtonColumn {
            id: answerButtons
            shown: root.mode === "answer"

            IconButton {
                id: copyBtn
                property bool copied: false
                shown: answerButtons.shown
                text: copied ? "✓" : ""
                onClicked: {
                    // No keyboard focus → no Ctrl+C, so this copies the selection if any.
                    if (answerText.selectedText)
                        Quickshell.execDetached(["wl-copy", "--", answerText.selectedText]);
                    else
                        Solver.copy();
                    copied = true;
                    copiedReset.restart();
                }
                Timer { id: copiedReset; interval: 1000; onTriggered: copyBtn.copied = false }
            }
            IconButton {
                shown: answerButtons.shown
                text: "↻"
                onClicked: Solver.solve()
            }
            IconButton {
                shown: answerButtons.shown
                text: "✕"
                onClicked: Solver.dismiss()
            }
        }

        ButtonColumn {
            id: tabButtons
            shown: root.mode === "settings"

            Repeater {
                // General / Models / Appearance
                model: ["⌂", "≡", "◐"]

                IconButton {
                    required property string modelData
                    required property int index
                    shown: tabButtons.shown
                    text: modelData
                    active: settingsLoader.item?.tab === index
                    onClicked: if (settingsLoader.item) settingsLoader.item.tab = index
                }
            }
            IconButton {
                shown: tabButtons.shown
                text: "✕"
                onClicked: Solver.dismiss()
            }
        }
    }

    component ButtonColumn: Column {
        property bool shown: false
        spacing: root.gap
        // Beside the card (or beside the dot's slot while it's a dot).
        x: root.buttonsOnLeft ? card.x - card.inset - root.gap - width
                              : card.x + card.width + card.inset + root.gap
        y: root.vAlign === "top" ? 0
         : root.vAlign === "bottom" ? stage.height - height
         : (stage.height - height) / 2
    }

    component IconButton: Rectangle {
        id: btn
        property alias text: glyph.text
        property int glyphSize: root.theme.fontSize
        property bool shown: false
        property bool active: false
        readonly property bool lit: mouse.containsMouse || active
        signal clicked

        implicitWidth: root.btnSize
        implicitHeight: root.btnSize
        radius: width / 2
        color: btn.lit ? root.theme.surface : root.theme.background
        scale: btn.shown ? (mouse.pressed ? 0.9 : 1) : 0.3
        opacity: btn.shown ? 1 : 0

        Behavior on scale { NumberAnimation { duration: root.morphMs; easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: root.morphMs * 0.6 } }
        Behavior on color { ColorAnimation { duration: 120 } }

        // Default icon: two overlapping squares ("copy"), used when no text is set.
        Item {
            visible: !glyph.text
            anchors.centerIn: parent
            width: 12
            height: 12
            Rectangle {
                x: 3; y: 0; width: 9; height: 9; radius: 2
                color: "transparent"
                border.width: 1.5
                border.color: glyph.color
            }
            Rectangle {
                x: 0; y: 3; width: 9; height: 9; radius: 2
                color: btn.color
                border.width: 1.5
                border.color: glyph.color
            }
        }

        Text {
            id: glyph
            anchors.centerIn: parent
            color: btn.lit ? root.theme.foreground : root.theme.muted
            font.family: root.theme.fontFamily || font.family
            font.pixelSize: btn.glyphSize
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            enabled: btn.shown
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
