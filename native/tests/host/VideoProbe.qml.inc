    // Injected only into a marked disposable CI profile; never shipped in Main.qml.
    Timer {
        id: hostVideoProbe
        interval: 250
        repeat: true
        running: true
        property int stage: 0
        onStageChanged: console.log("AGORA_HOST_VIDEO_STAGE", stage)
        property string fileId: ""
        property var player: null
        property int frames: 0
        function findPlayer(item) {
            if (item.objectName === "video-" + fileId) return item;
            var children = item.children || [];
            for (var i = 0; i < children.length; ++i) {
                var found = findPlayer(children[i]);
                if (found) return found;
            }
            return null;
        }
        function fail(message) {
            console.log("AGORA_HOST_VIDEO_FAIL", message);
            stop();
        }
        onTriggered: {
            if (player && stage >= 2 && player.failure) { fail(player.failure); return; }
            if (stage === 0 && forum.ready) {
                stage = -1;
                forum.call({op: "attachmentImport", file: VIDEO_FILE_JSON}, function (r) {
                    if (!r.ok || !r.attachment) { fail(JSON.stringify(r)); return; }
                    fileId = r.attachment.id;
                    forum.savePost("", "building", "[Synthetic acceptance] Inline video", "Disposable host playback test", function (post) {
                        if (!post.ok) { fail(JSON.stringify(post)); return; }
                        root.openThread(post.id);
                        stage = 1;
                    }, [fileId]);
                });
            } else if (stage === 1) {
                player = findPlayer(root);
                if (player) { player.playPause(); stage = 2; }
            } else if (stage === 2 && player.decodedFrames > 2 && player.position > 100) {
                if (player.failure) { fail(player.failure); return; }
                frames = player.decodedFrames;
                player.playPause();
                stage = 3;
            } else if (stage === 3 && !player.playing) {
                if (!player.state.seekable) { fail("Video is not seekable"); return; }
                player.seekTo(3000);
                stage = 4;
            } else if (stage === 4 && Math.abs(player.position - 3000) < 300) {
                player.playPause();
                stage = 5;
            } else if (stage === 5 && player.playing && player.decodedFrames > frames) {
                frames = player.decodedFrames;
                root.leaveThread();
                stage = -1;
                forum.call({op: "attachmentVideo", action: "state"}, function (r) {
                    if (!r.ok || r.video.playing || r.video.id !== "") { fail(JSON.stringify(r)); return; }
                    console.log("AGORA_HOST_VIDEO_PASS", frames, "frames; pause seek resume navigation-stop passed");
                    hostVideoProbe.stop();
                });
            }
        }
    }
