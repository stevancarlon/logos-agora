import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool selected: false
    implicitWidth: contentItem.implicitWidth + 24
    implicitHeight: 46
    hoverEnabled: true
    padding: 12
    font.family: "Adwaita Sans"
    font.pixelSize: 13
    font.weight: selected ? Font.DemiBold : Font.Normal
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.selected || control.hovered ? control.palette.text : control.palette.placeholderText
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }
    background: Rectangle {
        color: control.hovered ? control.palette.button : "transparent"
        border.width: control.activeFocus ? 1 : 0
        border.color: control.palette.accent
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            height: 2
            visible: control.selected
            color: control.palette.accent
        }
    }
}
