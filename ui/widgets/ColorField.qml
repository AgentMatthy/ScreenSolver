pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// "Label                 ● [#8ab4ff]"
// Click the swatch to open a row of presets; or type any hex (#rgb, #rrggbb, #aarrggbb).
Item {
    id: root

    readonly property var theme: Config.options.theme

    property string label: ""
    property string value: "#000000"
    property var presets: []
    property bool open: false

    signal picked(string color)

    function normalize(t: string): string {
        let s = t.trim().toLowerCase();
        if (s && !s.startsWith("#")) s = "#" + s;
        return /^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/.test(s) ? s : "";
    }

    implicitWidth: 200
    implicitHeight: 32 + (root.open ? palette.height + 8 : 0)
    clip: true

    Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Text {
        anchors.left: parent.left
        y: (32 - height) / 2
        text: root.label
        color: root.theme.foreground
        font.family: root.theme.fontFamily || font.family
        font.pixelSize: root.theme.fontSize
    }

    Row {
        anchors.right: parent.right
        height: 32
        spacing: 8

        // swatch (toggles presets)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            radius: 11
            color: root.value
            border.width: 1.5
            border.color: root.open || swatchMouse.containsMouse ? root.theme.foreground : Qt.lighter(root.theme.surface, 1.6)
            scale: swatchMouse.pressed ? 0.9 : 1

            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }
            Behavior on scale { NumberAnimation { duration: 90 } }

            MouseArea {
                id: swatchMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.open = !root.open
            }
        }

        Field {
            id: hex
            property bool invalid: false
            anchors.verticalCenter: parent.verticalCenter
            width: 96
            height: 28
            value: root.value
            placeholder: "#rrggbb"
            border.color: invalid ? root.theme.error
                                  : hex.inputItem.activeFocus ? Qt.alpha(root.theme.accent, 0.6) : "transparent"
            Connections {
                target: hex.inputItem
                function onTextEdited() {
                    hex.invalid = hex.text.trim() !== "" && root.normalize(hex.text) === "";
                }
            }
            onCommitted: t => {
                const c = root.normalize(t);
                if (c) {
                    root.picked(c);
                    hex.text = c;
                } else {
                    hex.text = root.value;
                }
                hex.invalid = false;
            }
        }
    }

    Flow {
        id: palette
        y: 32 + 6
        width: parent.width
        spacing: 6
        opacity: root.open ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 150 } }

        Repeater {
            model: root.presets

            Rectangle {
                id: preset
                required property string modelData
                readonly property bool active: root.value.toLowerCase() === modelData.toLowerCase()

                width: 20
                height: 20
                radius: 10
                color: modelData
                border.width: active || presetMouse.containsMouse ? 2 : 1
                border.color: active ? root.theme.foreground
                                     : presetMouse.containsMouse ? root.theme.foreground : Qt.lighter(root.theme.surface, 1.6)
                scale: presetMouse.containsMouse ? 1.12 : 1

                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                MouseArea {
                    id: presetMouse
                    anchors.fill: parent
                    anchors.margins: -2
                    enabled: root.open
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(preset.modelData)
                }
            }
        }
    }
}
