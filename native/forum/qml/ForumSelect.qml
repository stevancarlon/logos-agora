import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    implicitHeight: 40
    property bool fitOptions: false
    property bool quiet: false
    implicitWidth: fitOptions ? Math.ceil(optionWidth()) + leftPadding + rightPadding : 164
    FontMetrics {
        id: metrics
        font: control.font
    }
    function optionWidth() {
        var widest = 0;
        for (var i = 0; i < count; i++)
            widest = Math.max(widest, metrics.advanceWidth(textAt(i)));
        return widest;
    }
    leftPadding: quiet ? 0 : 12
    rightPadding: 34
    hoverEnabled: true
    font.family: "Adwaita Sans"
    font.pixelSize: 13
    contentItem: Text {
        text: control.displayText
        font: control.font
        color: control.palette.text
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Canvas {
        x: control.width - width - 13
        y: Math.round((control.height - height) / 2)
        width: 10
        height: 6
        property color ink: control.palette.placeholderText
        onInkChanged: requestPaint()
        onPaint: {
            var c = getContext("2d");
            c.reset();
            c.strokeStyle = ink;
            c.lineWidth = 1.3;
            c.lineCap = "round";
            c.lineJoin = "round";
            c.beginPath();
            c.moveTo(1, 1);
            c.lineTo(5, 5);
            c.lineTo(9, 1);
            c.stroke();
        }
    }
    background: Rectangle {
        radius: 6
        color: control.hovered ? control.palette.alternateBase : control.quiet ? "transparent" : control.palette.base
        border.color: control.activeFocus ? control.palette.accent : control.quiet ? "transparent" : control.palette.mid
    }
}
