import QtQuick
import QtQuick.Controls.Basic

AbstractButton {
    id: control
    property var avatar: null
    readonly property color iconColor: hovered || activeFocus ? palette.buttonText : palette.placeholderText
    implicitWidth: 36
    implicitHeight: 36
    hoverEnabled: true
    Accessible.name: "Profile"
    ToolTip.visible: hovered
    ToolTip.delay: 600
    ToolTip.text: "Profile"
    background: Rectangle {
        radius: width / 2
        color: control.hovered ? control.palette.highlight : "transparent"
        border.color: control.activeFocus ? control.palette.accent : control.palette.mid
        border.width: control.activeFocus ? 2 : 1
    }
    contentItem: Item {
        Canvas {
            id: portrait
            anchors.fill: parent
            property var portraitData: control.avatar
            onPortraitDataChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                if (portraitData && portraitData.pixels) {
                    // Paint validated pixels from the backend; no file or data URLs
                    // cross Basecamp's QML sandbox.
                    var size = portraitData.size;
                    ctx.save();
                    ctx.beginPath();
                    ctx.arc(width / 2, height / 2, Math.min(width, height) / 2 - 2, 0, Math.PI * 2);
                    ctx.clip();
                    var step = (width - 4) / size;
                    for (var y = 0; y < size; y++)
                        for (var x = 0; x < size; x++) {
                            var c = portraitData.pixels[y * size + x];
                            ctx.fillStyle = "rgba(" + ((c >>> 16) & 255) + "," + ((c >>> 8) & 255) + "," + (c & 255) + "," + ((c >>> 24) / 255) + ")";
                            ctx.fillRect(2 + x * step, 2 + y * step, step + .1, step + .1);
                        }
                    ctx.restore();
                } else {
                    ctx.strokeStyle = control.iconColor;
                    ctx.lineWidth = Math.max(1.5, width / 28);
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    ctx.arc(width / 2, height * .37, width * .13, 0, Math.PI * 2);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.arc(width / 2, height * .79, width * .24, Math.PI, Math.PI * 2);
                    ctx.stroke();
                }
            }
            Connections {
                target: control
                function onPaletteChanged() {
                    portrait.requestPaint();
                }
                function onIconColorChanged() {
                    portrait.requestPaint();
                }
            }
        }
    }
}
