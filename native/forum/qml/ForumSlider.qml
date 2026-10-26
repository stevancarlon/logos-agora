import QtQuick
import QtQuick.Controls.Basic

Slider {
    id: control
    leftPadding: 6
    rightPadding: 6
    implicitHeight: 40
    background: Rectangle {
        x: control.leftPadding
        y: (control.height - height) / 2
        width: control.availableWidth
        height: 3
        radius: 1.5
        color: control.palette.mid
        Rectangle {
            width: control.position * parent.width
            height: parent.height
            radius: parent.radius
            color: control.palette.accent
        }
    }
    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: (control.height - height) / 2
        width: 12
        height: 12
        radius: 6
        color: control.enabled ? control.palette.text : control.palette.mid
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? control.palette.accent : control.palette.base
    }
}
