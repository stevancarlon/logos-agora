pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Button {
    id: link
    property var controller
    property color ink: "#ededed"
    property color muted: "#a3a3a3"
    property color surface: "#222222"
    property color outline: "#333333"
    property real previewWidth: 420
    property var targetPost: null
    property bool threadAvailable: false
    property bool resolving: false
    property bool pendingOpen: false
    property string issue: ""
    property int requestEpoch: 0
    property bool showResult: false
    signal postActivated(var post)
    implicitWidth: Math.max(40, Math.ceil(label.implicitWidth) + 2)
    implicitHeight: 40
    padding: 0
    horizontalPadding: 0
    hoverEnabled: true
    font.family: "monospace"
    font.pixelSize: 13
    Accessible.name: "Open post " + text
    Accessible.description: "Preview the quoted post on hover or keyboard focus. Activate to jump to it."

    function openTarget() {
        pendingOpen = false;
        if (!threadAvailable) {
            issue = "The original thread is not available yet.";
            showResult = true; resultTimer.restart();
            return;
        }
        preview.close();
        postActivated(targetPost);
    }
    function resolve(openAfter) {
        pendingOpen = pendingOpen || openAfter;
        if (targetPost) { if (pendingOpen) openTarget(); return; }
        if (resolving || !controller) return;
        resolving = true;
        issue = "";
        var epoch = ++requestEpoch;
        controller.call({op: "postReference", reference: text.substring(2)}, function(r) {
            if (!link || epoch !== link.requestEpoch) return;
            link.resolving = false;
            if (r.state === "found") {
                link.targetPost = r.post;
                link.threadAvailable = r.threadAvailable;
                if (link.pendingOpen) link.openTarget();
            } else {
                link.issue = r.state === "ambiguous" ? "This short ID matches more than one post." : "This post is not available on this device yet.";
                if (link.pendingOpen) { link.showResult = true; resultTimer.restart(); }
                link.pendingOpen = false;
            }
        }, function() {
            if (!link || epoch !== link.requestEpoch) return;
            link.resolving = false;
            link.issue = "Could not load this post. Try again.";
            if (link.pendingOpen) { link.showResult = true; resultTimer.restart(); }
            link.pendingOpen = false;
        });
    }
    onTextChanged: {
        ++requestEpoch;
        targetPost = null; resolving = false; pendingOpen = false; issue = "";
        showResult = false;
    }
    onHoveredChanged: if (hovered) resolve(false)
    onVisualFocusChanged: if (visualFocus) resolve(false)
    onClicked: resolve(true)
    Keys.onReturnPressed: resolve(true)
    Keys.onEnterPressed: resolve(true)
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    Timer { id: resultTimer; interval: 2500; onTriggered: link.showResult = false }
    contentItem: Text {
        id: label
        text: link.text
        textFormat: Text.PlainText
        font.family: link.font.family
        font.pixelSize: link.font.pixelSize
        color: link.hovered || link.visualFocus ? link.ink : link.muted
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        font.underline: link.hovered || link.visualFocus
    }
    background: Rectangle {
        radius: 4
        color: "transparent"
        border.width: link.visualFocus ? 1 : 0
        border.color: link.ink
    }
    ToolTip {
        id: preview
        objectName: "quotePreview"
        parent: link
        x: 0
        visible: link.hovered || link.visualFocus || link.showResult
        delay: link.showResult ? 0 : 300
        timeout: -1
        margins: 12
        width: Math.min(link.previewWidth, (Overlay.overlay ? Overlay.overlay.width : 440) - 24)
        padding: 16
        background: Rectangle { color: link.surface; radius: 10; border.color: link.outline }
        contentItem: ColumnLayout {
            spacing: 10
            Text {
                Layout.fillWidth: true
                visible: !!link.targetPost
                text: !link.targetPost ? "" : link.targetPost.mode === "anonymous" ? "Anonymous" : link.targetPost.mode === "uid" ? link.targetPost.author.substring(0, 8) : link.targetPost.author
                color: link.ink
                font.family: "Adwaita Sans"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: !!link.targetPost && !!link.targetPost.title
                text: link.targetPost ? link.targetPost.title : ""
                color: link.ink
                font.family: "Adwaita Sans"
                font.pixelSize: 15
                font.weight: Font.DemiBold
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Loader {
                Layout.preferredWidth: 128
                Layout.preferredHeight: active ? 96 : 0
                visible: active
                active: !!link.targetPost && link.targetPost.attachments.length > 0
                sourceComponent: FeedAttachmentPreview {
                    attachment: link.targetPost.attachments[0]
                    controller: link.controller
                    count: link.targetPost.attachments.length
                    ink: link.ink; muted: link.muted; surface: link.surface; outline: link.outline
                }
            }
            Text {
                objectName: "quotePreviewBody"
                Layout.fillWidth: true
                text: link.issue || (link.targetPost ? link.targetPost.body : "Loading post…")
                color: link.targetPost && !link.issue ? link.ink : link.muted
                font.family: "Adwaita Sans"
                font.pixelSize: 14
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 8
                elide: Text.ElideRight
            }
        }
    }
}
