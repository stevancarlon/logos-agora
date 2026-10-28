import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: card
    objectName: "attachment-" + attachment.id
    required property var attachment
    required property var controller
    readonly property bool available: attachment.available !== false
    property var preview: null
    property color ink: "#ededed"
    property color muted: "#a3a3a3"
    property color surface: "#181818"
    property color outline: "#333333"
    signal downloadRequested(string attachmentId, string filename)
    width: Math.min(parent ? parent.width : 320, video ? 480 : 320)
    height: content.implicitHeight + (video ? 0 : 20)
    color: video ? "#080808" : surface
    border.color: video ? "transparent" : outline
    radius: 6
    readonly property bool video: attachment.mime.indexOf("video/") === 0
    readonly property bool pdf: attachment.mime === "application/pdf"
    function openFile() {
        controller.call({
            op: "attachmentOpen",
            id: attachment.id
        });
    }
    function loadPreview() { if (!available) return; controller.call({
        op: "attachmentPreview",
        id: attachment.id
    }, function (r) {
        // Basecamp replies asynchronously; the list may have destroyed this card.
        if (card)
            card.preview = r.image;
    }); }
    Component.onCompleted: loadPreview()
    onAvailableChanged: loadPreview()
    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: card.video ? 0 : 10
        spacing: 8
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: card.video ? width * 9 / 16 : card.pdf ? 104 : 160
            Canvas {
                id: thumb
                anchors.top: parent.top
                width: parent.width
                height: card.video ? width * 9 / 16 : parent.height
                visible: !videoLoader.item || !videoLoader.item.hasVideo
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Connections {
                    target: card
                    function onPreviewChanged() {
                        thumb.requestPaint();
                    }
                }
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var p = card.preview;
                    if (!p || !p.pixels)
                        return;
                    var scale = Math.min(width / p.width, height / p.height);
                    var ox = (width - p.width * scale) / 2, oy = (height - p.height * scale) / 2;
                    for (var y = 0; y < p.height; y++)
                        for (var x = 0; x < p.width; x++) {
                            var c = p.pixels[y * p.width + x];
                            ctx.fillStyle = "rgba(" + ((c >>> 16) & 255) + "," + ((c >>> 8) & 255) + "," + (c & 255) + "," + ((c >>> 24) / 255) + ")";
                            ctx.fillRect(ox + x * scale, oy + y * scale, scale + .1, scale + .1);
                        }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: !card.preview && !card.video && card.available
                text: card.pdf ? "PDF" : card.video ? "VIDEO" : "IMAGE"
                color: card.muted
                font.pixelSize: 22
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: !card.video && card.available
                onClicked: card.openFile()
            }
            Loader {
                id: videoLoader
                anchors.fill: parent
                active: card.video && card.available
                function loadVideo() { if (active && String(source) === "")
                    setSource("InlineVideo.qml", {
                        attachmentId: card.attachment.id,
                        controller: card.controller,
                        ink: card.ink,
                        muted: card.muted
                    }); }
                onActiveChanged: loadVideo()
                Component.onCompleted: loadVideo()
            }
            ForumButton {
                objectName: "fetchAttachment"
                implicitHeight: 40
                anchors.centerIn: parent
                visible: !card.available
                enabled: !card.controller.transferBusy
                text: card.controller.transferBusy && card.controller.transferState.id === card.attachment.id ? "Fetching…" : "Fetch " + (card.attachment.bytes >= 1048576 ? (card.attachment.bytes / 1048576).toFixed(1) + " MB" : Math.ceil(card.attachment.bytes / 1024) + " KB")
                Accessible.name: "Fetch attachment " + card.attachment.name
                onClicked: card.controller.transferFile(card.attachment.id, "attachmentFetch", function () {})
            }
            Connections {
                target: videoLoader.item
                function onDownloadRequested() {
                    card.downloadRequested(card.attachment.id, card.attachment.name);
                }
            }
            Text {
                anchors.centerIn: parent
                width: parent.width - 24
                visible: videoLoader.status === Loader.Error
                text: "Video playback requires the Agora multimedia launcher."
                wrapMode: Text.Wrap
                color: card.muted
            }
        }
        Text {
            visible: !card.video
            Layout.fillWidth: true
            text: card.attachment.name
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            color: card.ink
            font.family: "Adwaita Sans"
            font.pixelSize: 12
        }
        Text {
            visible: !card.video
            Layout.fillWidth: true
            text: (card.pdf ? "PDF" : card.video ? "Video" : "Image") + " · " + (card.attachment.bytes >= 1048576 ? (card.attachment.bytes / 1048576).toFixed(1) + " MB" : Math.ceil(card.attachment.bytes / 1024) + " KB") + (card.available ? " · On this device" : " · Logos Storage")
            color: card.muted
            font.family: "Adwaita Sans"
            font.pixelSize: 11
        }
        RowLayout {
            visible: !card.video && card.available
            Layout.fillWidth: true
            ForumButton {
                visible: !card.video
                text: "Open"
                flat: true
                onClicked: card.openFile()
            }
            Item {
                Layout.fillWidth: true
            }
            ForumButton {
                text: "Download"
                flat: true
                onClicked: card.downloadRequested(card.attachment.id, card.attachment.name)
            }
        }
    }
}
