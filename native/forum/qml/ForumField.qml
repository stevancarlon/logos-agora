import QtQuick
import QtQuick.Controls.Basic

TextField {
    id: control
    property bool clearable: false
    implicitHeight: 40
    leftPadding: 12
    rightPadding: clearable ? 40 : 12
    font.family: "Adwaita Sans"
    font.pixelSize: 13
    color: palette.text
    placeholderTextColor: palette.placeholderText
    selectionColor: palette.highlight
    selectedTextColor: palette.highlightedText
    ToolButton {
        objectName: "clearSearch"
        visible: control.clearable && control.text.length > 0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: parent.height
        text: "×"
        hoverEnabled: true
        Accessible.name: "Clear search"
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Item {}
        contentItem: Text {
            text: parent.text
            color: parent.hovered ? control.palette.text : control.palette.placeholderText
            font.pixelSize: 18
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        onClicked: { control.clear(); control.textEdited(); control.forceActiveFocus(); }
    }
    background: Rectangle {
        radius: 6
        color: control.palette.base
        border.color: control.activeFocus ? control.palette.accent : control.palette.mid
        border.width: 1
        Behavior on border.color { ColorAnimation { duration: 110 } }
    }
}
