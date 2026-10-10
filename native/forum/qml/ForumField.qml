import QtQuick
import QtQuick.Controls

TextField {
    id: control
    implicitHeight: 40
    leftPadding: 12
    rightPadding: 12
    font.family: "Adwaita Sans"
    font.pixelSize: 13
    color: palette.text
    placeholderTextColor: palette.placeholderText
    selectionColor: palette.highlight
    selectedTextColor: palette.highlightedText
    background: Rectangle {
        radius: 6
        color: control.palette.base
        border.color: control.activeFocus ? control.palette.accent : control.palette.mid
        border.width: 1
    }
}
