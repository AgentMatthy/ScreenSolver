pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// "Label            −  14  +"   (click, hold to repeat, or scroll on the value)
Item {
    id: root

    readonly property var theme: Config.options.theme

    property string label: ""
    property real value: 0
    property real from: 0
    property real to: 100
    property real step: 1
    property string suffix: ""

    signal moved(real value)

    function nudge(dir: int) {
        const v = Math.max(root.from, Math.min(root.to, root.value + dir * root.step));
        if (v !== root.value) root.moved(v);
    }

    implicitWidth: 200
    implicitHeight: 32

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.theme.foreground
        font.family: root.theme.fontFamily || font.family
        font.pixelSize: root.theme.fontSize
    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        StepButton { glyph: "−"; dir: -1 }

        Text {
            width: 52
            height: 26
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: `${Math.round(root.value * 100) / 100}${root.suffix}`
            color: root.theme.foreground
            font.family: root.theme.fontFamily || font.family
            font.pixelSize: root.theme.fontSize
            font.features: { "tnum": 1 }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => root.nudge(event.angleDelta.y > 0 ? 1 : -1)
            }
        }

        StepButton { glyph: "+"; dir: 1 }
    }

    component StepButton: Rectangle {
        id: btn
        property string glyph
        property int dir

        width: 26
        height: 26
        radius: 13
        color: mouse.containsMouse ? root.theme.surface : "transparent"
        scale: mouse.pressed ? 0.9 : 1

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 90 } }

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            color: mouse.containsMouse ? root.theme.foreground : root.theme.muted
            font.family: root.theme.fontFamily || font.family
            font.pixelSize: root.theme.fontSize + 2
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.nudge(btn.dir)
            onPressAndHold: repeat.start()
            onReleased: repeat.stop()
            onCanceled: repeat.stop()
        }

        Timer {
            id: repeat
            interval: 60
            repeat: true
            onTriggered: root.nudge(btn.dir)
        }
    }
}
