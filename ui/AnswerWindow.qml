pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// Small floating overlay showing the solver's status / answer.
PanelWindow {
    id: root

    readonly property var win: Config.options.window
    readonly property var theme: Config.options.theme
    readonly property string pos: win.position

    screen: Quickshell.screens.find(s => s.name === Solver.monitor) ?? Quickshell.screens[0]

    WlrLayershell.namespace: "screensolver"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
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

    implicitWidth: root.win.width
    implicitHeight: Math.min(card.implicitHeight, root.win.maxHeight)

    Timer {
        id: autoHide
        interval: Math.max(0, root.win.autoHideMs)
        running: interval > 0 && Solver.state === "done" && !hover.hovered
        onTriggered: Solver.dismiss()
    }

    Rectangle {
        id: card

        anchors.fill: parent
        implicitHeight: layout.implicitHeight + 2 * layout.anchors.margins
        radius: root.theme.radius
        color: root.theme.background
        border.width: 1
        border.color: root.theme.border
        focus: true

        Keys.onEscapePressed: Solver.dismiss()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)
                && !answerText.selectedText) {
                Solver.copy();
                event.accepted = true;
            } else if (event.key === Qt.Key_R) {
                Solver.solve();
                event.accepted = true;
            }
        }

        HoverHandler { id: hover }

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // ── Header ──────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    id: statusDot
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: 4
                    color: Solver.state === "error" ? root.theme.error
                         : Solver.state === "done" ? "#7ee787"
                         : root.theme.accent

                    SequentialAnimation on opacity {
                        running: Solver.busy
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) statusDot.opacity = 1
                        NumberAnimation { to: 0.25; duration: 500; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutQuad }
                    }
                }

                Label {
                    text: "ScreenSolver"
                    font.weight: Font.DemiBold
                }

                Label {
                    Layout.fillWidth: true
                    text: Solver.provider?.model ?? ""
                    color: root.theme.muted
                    font.pixelSize: root.theme.fontSize - 3
                    elide: Text.ElideMiddle
                }

                Label {
                    visible: Solver.state === "done"
                    text: `${((Solver.finishedAt - Solver.startedAt) / 1000).toFixed(1)}s`
                    color: root.theme.muted
                    font.pixelSize: root.theme.fontSize - 3
                }

                IconButton {
                    tooltip: "Copy (Ctrl+C)"
                    visible: Solver.state === "done" || Solver.state === "error"
                    onClicked: {
                        Solver.copy();
                        copiedFlash.restart();
                    }
                }
                IconButton {
                    text: "↻"
                    tooltip: "Retry (R)"
                    visible: !Solver.busy
                    onClicked: Solver.solve()
                }
                IconButton {
                    text: "✕"
                    tooltip: "Close (Esc)"
                    onClicked: Solver.dismiss()
                }
            }

            // ── Body ────────────────────────────────────────────────
            Label {
                visible: Solver.state === "thinking"
                Layout.fillWidth: true
                text: "Thinking" + ".".repeat(dots.count)
                color: root.theme.muted

                Timer {
                    id: dots
                    property int count: 1
                    interval: 350
                    repeat: true
                    running: Solver.state === "thinking"
                    onTriggered: count = count % 3 + 1
                }
            }

            Flickable {
                id: flick
                visible: Solver.state === "done" || Solver.state === "error"
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: answerText.implicitHeight
                contentWidth: width
                contentHeight: answerText.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                TextEdit {
                    id: answerText
                    width: flick.width
                    readOnly: true
                    selectByMouse: true
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

            Label {
                id: copied
                visible: opacity > 0
                opacity: 0
                text: "Copied to clipboard"
                color: root.theme.accent
                font.pixelSize: root.theme.fontSize - 3

                SequentialAnimation on opacity {
                    id: copiedFlash
                    running: false
                    NumberAnimation { to: 1; duration: 80 }
                    PauseAnimation { duration: 900 }
                    NumberAnimation { to: 0; duration: 300 }
                }
            }
        }
    }

    component Label: Text {
        color: root.theme.foreground
        font.family: root.theme.fontFamily || font.family
        font.pixelSize: root.theme.fontSize
    }

    component IconButton: Rectangle {
        id: btn
        property alias text: glyph.text
        property string tooltip
        signal clicked

        implicitWidth: 24
        implicitHeight: 24
        radius: 6
        color: mouse.containsMouse ? root.theme.surface : "transparent"

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
                color: btn.color.a > 0 ? btn.color : root.theme.background
                border.width: 1.5
                border.color: glyph.color
            }
        }

        Text {
            id: glyph
            anchors.centerIn: parent
            color: mouse.containsMouse ? root.theme.foreground : root.theme.muted
            font.pixelSize: root.theme.fontSize
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
