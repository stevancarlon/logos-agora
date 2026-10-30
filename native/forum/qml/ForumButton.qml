import QtQuick
import QtQuick.Controls.Basic

Button {
    id: control
    property bool primary: false
    property bool selected: false
    property bool navigation: false
    property real cornerRadius: 6
    implicitHeight: 36
    implicitWidth: Math.max(70, contentItem.implicitWidth + 24)
    scale: down ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
    hoverEnabled: true
    HoverHandler {
        enabled: control.enabled
        cursorShape: Qt.PointingHandCursor
    }
    padding: 10
    font.family: "Adwaita Sans"
    font.pixelSize: 12
    font.weight: control.primary || control.selected ? Font.DemiBold : Font.Normal
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.primary ? control.palette.window : control.enabled ? control.palette.buttonText : control.palette.placeholderText
        horizontalAlignment: control.navigation ? Text.AlignLeft : Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        Behavior on color { ColorAnimation { duration: 110 } }
        Behavior on border.color { ColorAnimation { duration: 110 } }
        radius: control.cornerRadius
        color: control.primary ? (control.down ? Qt.darker(control.palette.accent, 1.25) : control.hovered ? Qt.lighter(control.palette.accent, 1.15) : control.palette.accent) : control.selected || control.hovered ? control.palette.highlight : control.flat || control.navigation ? "transparent" : control.palette.button
        border.width: control.visualFocus || (!control.flat && !control.navigation && !control.primary) ? 1 : 0
        border.color: control.visualFocus ? control.palette.accent : control.palette.mid
        opacity: control.enabled ? 1 : 0.5
    }
}
