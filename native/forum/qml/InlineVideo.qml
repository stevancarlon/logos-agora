import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Agora.Media 1.0

FocusScope {
    id: player
    required property string attachmentId
    required property var controller
    property color ink: "#e6e8df"
    property color muted: "#a7b2a9"
    property bool loading: false
    property bool busy: false
    property string failure: ""
    property var state: ({
            position: 0,
            duration: 0,
            playing: false,
            seekable: false,
            volume: 0.7,
            muted: false,
            generation: -1,
            hasVideo: false
        })
    property string frame: ""
    readonly property bool hasVideo: frame !== ""
    readonly property bool playing: state.playing && controller.playingAttachment === attachmentId
    readonly property int decodedFrames: output.framesPresented
    readonly property int position: state.position
    readonly property int duration: state.duration
    implicitHeight: width * 9 / 16
    signal downloadRequested
    activeFocusOnTab: true
    readonly property bool controlsShown: !playing || videoHover.hovered || activeFocus
    HoverHandler {
        id: videoHover
    }
    Keys.onSpacePressed: playPause()
    Keys.onLeftPressed: seekTo(Math.max(0, position - 5000))
    Keys.onRightPressed: seekTo(Math.min(duration, position + 5000))
    objectName: "video-" + attachmentId
    function command(action, extra) {
        var request = {
            op: "attachmentVideo",
            action: action,
            id: attachmentId,
            generation: state.generation
        };
        if (extra)
            for (var key in extra)
                request[key] = extra[key];
        controller.call(request, function (r) {
            if (!player)
                return;
            player.loading = false;
            player.busy = false;
            if (r.video.id !== player.attachmentId && !(r.video.id === "" && (action === "volume" || action === "mute")))
                return;
            player.state = r.video;
            player.failure = r.video.error;
            if (r.video.frame !== undefined)
                player.frame = r.video.frame;
        }, function (error) {
            if (player) {
                player.failure = error;
                player.loading = false;
                player.busy = false;
            }
        });
    }
    function clock(ms) {
        var secs = Math.floor(ms / 1000);
        return Math.floor(secs / 60) + ":" + (secs % 60 < 10 ? "0" : "") + secs % 60;
    }
    function playPause() {
        if (loading)
            return;
        if (playing) {
            command("pause");
            return;
        }
        controller.playingAttachment = attachmentId;
        failure = "";
        loading = true;
        command("play");
    }
    function seekTo(ms) {
        command("seek", {
            position: ms
        });
    }
    Connections {
        target: player.controller
        function onPlayingAttachmentChanged() {
            if (player.controller.playingAttachment !== player.attachmentId && player.state.playing) {
                player.command("pause");
                var next = player.state;
                next.playing = false;
                player.state = next;
            }
        }
    }
    onVisibleChanged: if (!visible && playing)
        command("pause")
    Component.onDestruction: {
        if (controller.playingAttachment === attachmentId) {
            controller.playingAttachment = "";
            controller.call({
                op: "attachmentVideo",
                id: attachmentId,
                action: "stop"
            });
        }
    }
    Timer {
        interval: 40
        repeat: true
        running: player.visible && player.controller.playingAttachment === player.attachmentId
        onTriggered: if (!player.busy) {
            player.busy = true;
            player.command("state");
        }
    }
    FrameSurface {
        id: output
        anchors.top: parent.top
        width: parent.width
        height: width * 9 / 16
        packet: player.frame
        visible: player.hasVideo
    }
    MouseArea {
        anchors.fill: output
        cursorShape: Qt.PointingHandCursor
        onClicked: player.playPause()
    }
    Rectangle {
        anchors.fill: output
        color: "#141c17"
        visible: player.failure !== ""
        Text {
            anchors.fill: parent
            anchors.margins: 16
            text: player.failure
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignVCenter
            color: player.ink
        }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 92
        opacity: controls.opacity
        gradient: Gradient {
            GradientStop {
                position: 0
                color: "transparent"
            }
            GradientStop {
                position: 1
                color: "#b0000000"
            }
        }
    }
    ColumnLayout {
        id: controls
        objectName: "videoControls-" + player.attachmentId
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.bottomMargin: 2
        spacing: 0
        opacity: player.controlsShown ? 1 : 0
        visible: opacity > 0
        enabled: player.controlsShown
        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }
        ForumSlider {
            id: seek
            stepSize: 1000
            objectName: "seek-" + player.attachmentId
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            palette.mid: "#55ffffff"
            palette.accent: "#dbe7dd"
            palette.text: "#f2f3ee"
            palette.base: "#40000000"
            from: 0
            to: Math.max(1, player.duration)
            value: player.position
            enabled: player.state.seekable
            onMoved: player.seekTo(value)
            Accessible.name: "Video position"
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 2
            VideoControl {
                objectName: "playPause-" + player.attachmentId
                symbol: player.playing ? "pause" : "play"
                label: player.playing ? "Pause video" : "Play video"
                enabled: !player.loading
                onClicked: player.playPause()
            }
            Text {
                text: player.loading ? "Loading…" : player.clock(player.position) + " / " + player.clock(player.duration)
                color: "#e5e8e2"
                font.family: "monospace"
                font.pixelSize: 10
            }
            Item {
                Layout.fillWidth: true
            }
            VideoControl {
                symbol: player.state.muted ? "muted" : "sound"
                label: player.state.muted ? "Unmute video" : "Mute video"
                onClicked: player.command("mute", {
                    muted: !player.state.muted
                })
            }
            ForumSlider {
                objectName: "volume-" + player.attachmentId
                stepSize: 0.05
                Layout.preferredWidth: 56
                Layout.preferredHeight: 40
                palette.mid: "#55ffffff"
                palette.accent: "#dbe7dd"
                palette.text: "#f2f3ee"
                palette.base: "#40000000"
                from: 0
                to: 1
                value: player.state.volume
                onMoved: player.command("volume", {
                    volume: value
                })
                Accessible.name: "Video volume"
            }
        }
    }
    VideoControl {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 4
        opacity: controls.opacity
        visible: opacity > 0
        enabled: player.controlsShown
        symbol: "download"
        label: "Download video"
        onClicked: player.downloadRequested()
    }
}
