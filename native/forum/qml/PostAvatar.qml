import QtQuick

Rectangle {
    id: portrait
    property var avatar: null
    property string initial: "·"
    property color ink: "#a3a3a3"
    implicitWidth: 28
    implicitHeight: 28
    radius: Math.min(width, height) / 2
    color: "#202020"
    Accessible.ignored: true // The adjacent author label identifies this post.

    Text {
        anchors.centerIn: parent
        visible: !portrait.avatar
        text: portrait.initial
        textFormat: Text.PlainText
        color: portrait.ink
        font.family: "Adwaita Sans"
        font.pixelSize: 14
    }
    Canvas {
        id: image
        objectName: "avatarPortrait"
        anchors.fill: parent
        property var pixels: portrait.avatar
        onPixelsChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (!pixels || !pixels.pixels) return;
            // Validated backend pixels work inside Basecamp's QML sandbox.
            ctx.save();
            ctx.beginPath();
            ctx.arc(width / 2, height / 2, Math.min(width, height) / 2, 0, Math.PI * 2);
            ctx.clip();
            var sx = width / pixels.size, sy = height / pixels.size;
            for (var y = 0; y < pixels.size; ++y)
                for (var x = 0; x < pixels.size; ++x) {
                    var c = pixels.pixels[y * pixels.size + x];
                    ctx.fillStyle = "rgba(" + ((c >>> 16) & 255) + "," + ((c >>> 8) & 255) + "," + (c & 255) + "," + ((c >>> 24) / 255) + ")";
                    ctx.fillRect(x * sx, y * sy, sx + .1, sy + .1);
                }
            ctx.restore();
        }
    }
}
