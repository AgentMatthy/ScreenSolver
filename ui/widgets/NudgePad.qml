pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// Arrow pad for fine positioning:      ▲
//                                    ◀ ⟲ ▶      x +4
//                                      ▼        y −2
// Click = 1px, hold to repeat (speeds up to 5px), scroll = vertical (horizontal
// scroll / shift+scroll = horizontal). The centre button resets to 0,0.
Item {
    id: root

    readonly property var theme: Config.options.theme

    property int valueX: 0
    property int valueY: 0
    // [min, max] for each axis.
    property var rangeX: [-10000, 10000]
    property var rangeY: [-10000, 10000]

    signal moved(int x, int y)

    readonly property bool dirty: valueX !== 0 || valueY !== 0
    // Effective (clamped) values; a stored value past the screen edge snaps back on the next nudge.
    readonly property int shownX: clamp(valueX, rangeX)
    readonly property int shownY: clamp(valueY, rangeY)

    function clamp(v: int, r: var): int {
        return Math.max(r[0], Math.min(r[1], v));
    }
    function nudge(dx: int, dy: int) {
        const x = clamp(root.shownX + dx, root.rangeX), y = clamp(root.shownY + dy, root.rangeY);
        if (x !== root.valueX || y !== root.valueY) root.moved(x, y);
    }
    function sign(v: int): string {
        return v > 0 ? `+${v}` : v < 0 ? `−${-v}` : "0";
    }

    readonly property int cell: 26
    readonly property int spacing: 2

    implicitWidth: pad.width + 12 + readout.implicitWidth
    implicitHeight: pad.height

    Item {
        id: pad
        width: 3 * root.cell + 2 * root.spacing
        height: width

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const horiz = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y);
                const d = horiz ? event.angleDelta.x : event.angleDelta.y;
                if (horiz || (event.modifiers & Qt.ShiftModifier))
                    root.nudge(d > 0 ? -1 : 1, 0);
                else
                    root.nudge(0, d > 0 ? -1 : 1);
            }
        }

        PadButton { col: 1; row: 0; glyph: "▲"; dx: 0; dy: -1 }
        PadButton { col: 0; row: 1; glyph: "◀"; dx: -1; dy: 0 }
        PadButton { col: 2; row: 1; glyph: "▶"; dx: 1; dy: 0 }
        PadButton { col: 1; row: 2; glyph: "▼"; dx: 0; dy: 1 }
        PadButton {
            col: 1; row: 1
            glyph: "⟲"
            glyphSize: root.theme.fontSize
            enabled: root.dirty
            onActivated: root.moved(0, 0)
        }
    }

    Column {
        id: readout
        anchors.left: pad.right
        anchors.leftMargin: 12
        anchors.verticalCenter: pad.verticalCenter
        spacing: 2

        Repeater {
            model: [["x", root.shownX], ["y", root.shownY]]

            Text {
                required property var modelData
                text: `${modelData[0]}  ${root.sign(modelData[1])} px`
                color: modelData[1] !== 0 ? root.theme.foreground : root.theme.muted
                font.family: root.theme.fontFamily || font.family
                font.pixelSize: root.theme.fontSize - 1
                font.features: { "tnum": 1 }
            }
        }
    }

    component PadButton: Rectangle {
        id: btn
        property int col
        property int row
        property string glyph
        property int glyphSize: root.theme.fontSize - 4
        property int dx: 0
        property int dy: 0
        property int repeats: 0
        signal activated

        x: col * (root.cell + root.spacing)
        y: row * (root.cell + root.spacing)
        width: root.cell
        height: root.cell
        radius: root.cell / 2
        opacity: enabled ? 1 : 0.35
        color: mouse.containsMouse ? root.theme.surface : "transparent"
        scale: mouse.pressed ? 0.9 : 1

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 90 } }
        Behavior on opacity { NumberAnimation { duration: 120 } }

        // Default action: nudge.
        onActivated: if (dx || dy) root.nudge(dx, dy)

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            color: mouse.containsMouse ? root.theme.foreground : root.theme.muted
            font.family: root.theme.fontFamily || font.family
            font.pixelSize: btn.glyphSize
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: btn.activated()
            onPressAndHold: if (btn.dx || btn.dy) { btn.repeats = 0; repeat.start(); }
            onReleased: repeat.stop()
            onCanceled: repeat.stop()
        }

        Timer {
            id: repeat
            interval: 40
            repeat: true
            onTriggered: {
                btn.repeats++;
                const s = btn.repeats > 20 ? 5 : 1;
                root.nudge(btn.dx * s, btn.dy * s);
            }
        }
    }
}
