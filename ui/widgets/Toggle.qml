import QtQuick
import qs.config

// "Label                 (◯━)"   — the whole row is clickable.
Item {
    id: root

    readonly property var theme: Config.options.theme

    property string label: ""
    property bool checked: false

    signal toggled(bool checked)

    implicitWidth: 200
    implicitHeight: 32

    Text {
        anchors.left: parent.left
        anchors.right: track.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        elide: Text.ElideRight
        color: root.theme.foreground
        font.family: root.theme.fontFamily || font.family
        font.pixelSize: root.theme.fontSize
    }

    Rectangle {
        id: track
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 20
        radius: 10
        color: root.checked ? root.theme.accent : root.theme.surface

        Behavior on color { ColorAnimation { duration: 150 } }

        Rectangle {
            width: 14
            height: 14
            radius: 7
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 3 : 3
            color: root.checked ? root.theme.background : root.theme.muted

            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
