pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// Row of pill options; `options` is a list of strings or { label, value } objects.
Rectangle {
    id: root

    readonly property var theme: Config.options.theme

    property var options: []
    property var current

    signal picked(var value)

    implicitWidth: row.implicitWidth + 6
    implicitHeight: 32
    radius: Math.min(root.theme.radius, height / 2)
    color: root.theme.surface

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.options

            Rectangle {
                id: pill
                required property var modelData
                readonly property var optValue: typeof modelData === "object" ? modelData.value : modelData
                readonly property string optLabel: typeof modelData === "object" ? modelData.label : String(modelData)
                readonly property bool active: optValue === root.current

                width: Math.max(label.implicitWidth + 20, 44)
                height: root.height - 6
                radius: Math.max(0, root.radius - 3)
                color: active ? root.theme.background : mouse.containsMouse ? Qt.alpha(root.theme.background, 0.4) : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: pill.optLabel
                    color: pill.active ? root.theme.foreground : root.theme.muted
                    font.family: root.theme.fontFamily || font.family
                    font.pixelSize: root.theme.fontSize - 1
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(pill.optValue)
                }
            }
        }
    }
}
