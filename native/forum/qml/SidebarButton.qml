import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Button {
    id: control
    property bool selected: false
    property string symbol: "general"
    property real uiScale: 1
    implicitHeight: 48 * uiScale
    hoverEnabled: true
    leftPadding: 24 * uiScale
    rightPadding: 12 * uiScale
    contentItem: RowLayout {
        spacing: 20 * control.uiScale
        ForumIcon {
            name: control.symbol
            ink: control.selected ? control.palette.text : control.palette.placeholderText
            Layout.preferredWidth: 24 * control.uiScale
            Layout.preferredHeight: 24 * control.uiScale
        }
        Text {
            Layout.fillWidth: true
            text: control.text
            font.family: "Adwaita Sans"
            font.pixelSize: 16 * control.uiScale
            font.weight: control.selected ? Font.DemiBold : Font.Normal
            color: control.selected ? control.palette.text : control.palette.placeholderText
            elide: Text.ElideRight
        }
    }
    background: Rectangle {
        radius: 6
        color: control.selected ? control.palette.highlight : control.hovered ? control.palette.button : "transparent"
        border.width: control.activeFocus ? 1 : 0
        border.color: control.palette.accent
        Rectangle {
            visible: control.selected
            width: 3
            height: parent.height
            color: control.palette.accent
        }
    }
}
