import QtQuick
import QtQuick.Controls.Basic

Button {
    id: control
    property bool selected: false
    implicitWidth: contentItem.implicitWidth + 24
    implicitHeight: 46
    scale: down ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
    hoverEnabled: true
    HoverHandler {
        enabled: control.enabled
        cursorShape: Qt.PointingHandCursor
    }
    padding: 12
    font.family: "Adwaita Sans"
    font.pixelSize: 13
    font.weight: Font.Medium
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.selected || control.hovered ? control.palette.text : control.palette.placeholderText
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }
    background: Rectangle {
        Behavior on color { ColorAnimation { duration: 110 } }
        Behavior on border.color { ColorAnimation { duration: 110 } }
        color: control.hovered ? control.palette.button : "transparent"
        border.width: control.visualFocus ? 1 : 0
        border.color: control.palette.accent
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            height: 2
            opacity: control.selected ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            color: control.palette.accent
        }
    }
}
