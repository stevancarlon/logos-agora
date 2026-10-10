import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    property bool selected: false
    property bool navigation: false
    implicitHeight: 36
    implicitWidth: Math.max(70, contentItem.implicitWidth + 24)
    hoverEnabled: true
    padding: 10
    font.family: "Adwaita Sans"
    font.pixelSize: 12
    font.weight: control.primary || control.selected ? Font.DemiBold : Font.Normal
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.primary ? "#13291c" : control.enabled ? control.palette.buttonText : control.palette.placeholderText
        horizontalAlignment: control.navigation ? Text.AlignLeft : Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: 6
        color: control.primary ? (control.down ? "#96bda0" : control.hovered ? "#c1dbc5" : "#a7c9ae") : control.selected || control.hovered ? control.palette.highlight : control.flat || control.navigation ? "transparent" : control.palette.button
        border.width: control.activeFocus || (!control.flat && !control.navigation && !control.primary) ? 1 : 0
        border.color: control.activeFocus ? control.palette.accent : control.palette.mid
        opacity: control.enabled ? 1 : 0.5
    }
}
