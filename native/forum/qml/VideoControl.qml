import QtQuick
import QtQuick.Controls

ToolButton {
    id: control
    property string symbol: "play"
    property string label: ""
    implicitWidth: 40
    implicitHeight: 40
    focusPolicy: Qt.TabFocus
    Accessible.name: label
    ToolTip.visible: hovered
    ToolTip.delay: 650
    ToolTip.text: label
    background: Rectangle {
        radius: 5
        color: control.hovered || control.activeFocus ? "#25ffffff" : "transparent"
        border.color: control.activeFocus ? "#c5d6c7" : "transparent"
    }
    contentItem: Item {
        Canvas {
            anchors.centerIn: parent
            width: 18
            height: 18
            property string symbol: control.symbol
            onSymbolChanged: requestPaint()
            onPaint: {
                var c = getContext("2d");
                c.reset();
                c.strokeStyle = "#f2f3ee";
                c.fillStyle = "#f2f3ee";
                c.lineWidth = 1.4;
                c.lineCap = "round";
                c.lineJoin = "round";
                c.beginPath();
                if (symbol === "play") {
                    c.moveTo(5, 3);
                    c.lineTo(14, 9);
                    c.lineTo(5, 15);
                    c.closePath();
                    c.fill();
                } else if (symbol === "pause") {
                    c.fillRect(5, 3, 2, 12);
                    c.fillRect(11, 3, 2, 12);
                } else if (symbol === "download") {
                    c.moveTo(9, 2);
                    c.lineTo(9, 12);
                    c.moveTo(5, 8);
                    c.lineTo(9, 12);
                    c.lineTo(13, 8);
                    c.moveTo(3, 12);
                    c.lineTo(3, 16);
                    c.lineTo(15, 16);
                    c.lineTo(15, 12);
                    c.stroke();
                } else {
                    c.moveTo(2, 7);
                    c.lineTo(5, 7);
                    c.lineTo(9, 3);
                    c.lineTo(9, 15);
                    c.lineTo(5, 11);
                    c.lineTo(2, 11);
                    c.closePath();
                    c.stroke();
                    c.beginPath();
                    if (symbol === "muted") {
                        c.moveTo(12, 6);
                        c.lineTo(17, 12);
                        c.moveTo(17, 6);
                        c.lineTo(12, 12);
                    } else {
                        c.arc(10, 9, 4, -.8, .8);
                        c.moveTo(15, 3);
                        c.quadraticCurveTo(20, 9, 15, 15);
                    }
                    c.stroke();
                }
            }
        }
    }
}
