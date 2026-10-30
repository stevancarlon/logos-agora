import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: tile
    required property var attachment
    required property var controller
    property int count: 1
    property color ink: "#ededed"
    property color muted: "#a3a3a3"
    property color surface: "#181818"
    property color outline: "#333333"
    property var preview: null
    readonly property bool video: attachment && attachment.mime.indexOf("video/") === 0
    readonly property bool pdf: attachment && attachment.mime === "application/pdf"
    property int requestEpoch: 0
    implicitWidth: 136
    implicitHeight: 106
    radius: 8
    color: surface
    border.color: outline
    function loadPreview() {
        var epoch = ++requestEpoch;
        preview = null;
        if (!attachment || attachment.available === false) return;
        controller.call({op: "attachmentPreview", id: attachment.id}, function(r) {
            if (tile && epoch === tile.requestEpoch) tile.preview = r.image;
        }, function() {}); // A missing local preview must not interrupt browsing.
    }
    Component.onCompleted: loadPreview()
    onAttachmentChanged: if (controller) loadPreview()
    onPreviewChanged: thumbnail.requestPaint()
    Accessible.ignored: true // The containing thread row owns navigation.
    Canvas {
        id: thumbnail
        anchors.fill: parent
        anchors.margins: 4
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var c = getContext("2d");
            c.reset();
            var p = tile.preview;
            if (!p || !p.pixels) return;
            var scale = Math.min(width / p.width, height / p.height);
            var ox = (width - p.width * scale) / 2, oy = (height - p.height * scale) / 2;
            for (var y = 0; y < p.height; y++)
                for (var x = 0; x < p.width; x++) {
                    var pixel = p.pixels[y * p.width + x];
                    c.fillStyle = "rgba(" + ((pixel >>> 16) & 255) + "," + ((pixel >>> 8) & 255) + "," + (pixel & 255) + "," + ((pixel >>> 24) / 255) + ")";
                    c.fillRect(ox + x * scale, oy + y * scale, scale + .1, scale + .1);
                }
        }
    }
    Text {
        anchors.centerIn: parent
        visible: !tile.preview && !tile.video
        text: tile.pdf ? "PDF" : "Image"
        color: tile.muted
        font.pixelSize: 16
    }
    Rectangle {
        anchors.centerIn: parent
        visible: tile.video
        width: 36; height: 36; radius: 18
        color: "#bd111111"
        border.color: "#cccccc"
        Text { anchors.centerIn: parent; text: "▶"; color: "#ffffff"; font.pixelSize: 16 }
    }
    Rectangle {
        objectName: "attachment-count"
        visible: tile.count > 1
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        width: countText.implicitWidth + 12
        height: 24
        radius: 4
        color: "#dd111111"
        Text { id: countText; anchors.centerIn: parent; text: "+" + (tile.count - 1); color: "#ffffff"; font.pixelSize: 12 }
    }
}
