import QtQuick
Item {
    id: root
    property string role: ROLE_JSON
    property bool announced: false
    property bool posted: false
    property bool replied: false
    ForumController {
        id: forum
        onReadyChanged: if (ready) {
            function begin() {
            if (root.role === "prepare") {
                function prepare(files) {
                    forum.savePost("", "general", "Isolated network acceptance", "Synthetic acceptance message on a private test network", function (r) {
                        console.log("AGORA_OFFLINE_QUEUED", r.id);
                    }, files);
                }
                if (MEDIA_FILE_JSON) call({op: "attachmentImport", file: MEDIA_FILE_JSON}, function (r) { prepare([r.attachment.id]); });
                else prepare([]);
                return;
            }
            if (root.role === "sender" && state.posts.length > 0) root.posted = true;
            attachEvents();
            connection = root.role === "history" ? "offline" : "connecting";
            moduleCall("createNode", [CONFIG_JSON], function () {
                moduleCall("start", [], function () {});
            });
            }
            call({op: "settings", storageEndpoint: STORAGE_API_JSON, mode: TEST_MODE_JSON}, function () {
                call({op: "snapshot"}, function (r) { state = r; begin(); });
            });
        }
        onErrorChanged: if (error) console.log("AGORA_PEER_ERROR", error)
        onConnectionChanged: if (connection === "online" && !root.announced) {
            root.announced = true;
            moduleCall("getNodeInfo", ["MyMultiaddresses"], function (value) {
                console.log("AGORA_PEER_ADDRESSES", JSON.stringify(value));
            });
            if (root.role === "sender") publishTimer.start();
        }
        onStateChanged: {
            if (root.role === "history" && state.posts.length >= 2)
                console.log("AGORA_STORE_RECOVERED", state.posts.length);
            for (var i = 0; i < state.posts.length; ++i) {
                var post = state.posts[i];
                if (root.role === "receiver" && post.title === "Isolated network acceptance" && !root.replied) {
                    root.replied = true;
                    console.log("AGORA_PEER_RECEIVED", post.id);
                    if (post.attachments.length) transferFile(post.attachments[0].id, "attachmentFetch", function () {
                        console.log("AGORA_ATTACHMENT_FETCHED");
                    });
                    savePost(post.id, "general", "", "Reply from independent Basecamp backend", function () {});
                }
                if (root.role === "sender" && post.body === "Reply from independent Basecamp backend")
                    console.log("AGORA_PEER_REPLY", post.id);
            }
        }
    }
    Connections {
        target: forum.bridge
        function onModuleEventReceived(module, name, data) {
            if (root.role === "history" && module === "delivery_module" && name === "nodeStarted" && data[0])
                historyTimer.start();
        }
    }
    Timer {
        id: historyTimer
        interval: 1500
        onTriggered: forum.loadHistory(STORE_PEER_JSON)
    }
    Timer {
        id: publishTimer
        interval: 6000
        onTriggered: if (!root.posted) {
            root.posted = true;
            forum.savePost("", "general", "Isolated network acceptance", "Synthetic acceptance message on a private test network", function (r) {
                console.log("AGORA_PEER_CREATED", r.id);
            });
        }
    }
}
