import QtQuick
import qs.config

// Single-line text field.
//   value      external value (e.g. from config); shown unless the user is editing
//   committed  emitted on Enter / focus loss / destruction when the text differs from `value`
//   accepted   emitted on Enter (always)
Rectangle {
    id: root

    readonly property var theme: Config.options.theme

    property string value: ""
    property string placeholder: ""
    property bool secret: false
    property bool revealed: false
    property bool commitOnBlur: true
    property alias text: input.text
    readonly property alias inputItem: input

    signal committed(string text)
    signal accepted(string text)

    function commit() {
        if (root.commitOnBlur && input.text !== root.value)
            root.committed(input.text);
    }

    implicitWidth: 200
    implicitHeight: 32
    radius: Math.min(root.theme.radius, height / 2)
    color: root.theme.surface
    border.width: 1
    border.color: input.activeFocus ? Qt.alpha(root.theme.accent, 0.6) : "transparent"

    Behavior on border.color { ColorAnimation { duration: 120 } }

    onValueChanged: if (!input.activeFocus) input.text = root.value
    Component.onCompleted: input.text = root.value
    Component.onDestruction: root.commit()

    TextInput {
        id: input
        anchors.left: parent.left
        anchors.right: reveal.visible ? reveal.left : parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        clip: true
        color: root.theme.foreground
        selectionColor: root.theme.accent
        selectedTextColor: root.theme.background
        selectByMouse: true
        echoMode: root.secret && !root.revealed ? TextInput.Password : TextInput.Normal
        font.family: root.theme.fontFamily || font.family
        font.pixelSize: root.theme.fontSize

        onEditingFinished: root.commit()
        onAccepted: root.accepted(input.text)

        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: !input.text
            text: root.placeholder
            color: root.theme.muted
            elide: Text.ElideRight
            font: input.font
        }
    }

    // show / hide toggle for secrets
    Text {
        id: reveal
        visible: root.secret
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.revealed ? "hide" : "show"
        color: revealMouse.containsMouse ? root.theme.foreground : root.theme.muted
        font.family: root.theme.fontFamily || font.family
        font.pixelSize: root.theme.fontSize - 2

        MouseArea {
            id: revealMouse
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.revealed = !root.revealed
        }
    }
}
