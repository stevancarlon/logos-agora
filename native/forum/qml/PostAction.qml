import QtQuick
import QtQuick.Controls.Basic

AbstractButton {
    id: action
    property string iconName: "reply"
    property color ink: "#a3a3a3"
    property color activeInk: "#ededed"
    implicitWidth: 40
    implicitHeight: 40
    hoverEnabled: true
    scale: down ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
    Accessible.name: text
    ToolTip.visible: hovered
    ToolTip.delay: 500
    ToolTip.text: text
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    background: Rectangle {
        color: "transparent"
        radius: 5
        border.width: action.visualFocus ? 1 : 0
        border.color: action.activeInk
    }
    contentItem: Item {
        ForumIcon {
            anchors.centerIn: parent
            width: 18; height: 18
            name: action.iconName
            ink: action.hovered || action.visualFocus ? action.activeInk : action.ink
            opacity: action.enabled ? 1 : 0.4
        }
    }
}
