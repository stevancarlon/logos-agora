import QtQuick

QtObject {
    id: ctl
    property var backend: typeof forumLocal !== "undefined" ? forumLocal : null
    property var bridge: typeof logos !== "undefined" ? logos : null
    property bool eventsAttached: false
    property var earlyEvents: []
    property bool ready: false
    property bool startupConnectionChecked: false
    property int connectionEpoch: 0
    property var browseQuery: ({})
    onBrowseQueryChanged: {
        error = "";
        if (backend) scheduleRefresh(true);
    }
    property bool refreshing: false
    readonly property bool loading: refreshing || refreshTimer.running
    property bool refreshAgain: false
    property int pendingReceives: 0
    function scheduleRefresh(immediate) {
        if (refreshing) { refreshAgain = true; return; }
        // User navigation runs next frame; network bursts remain coalesced.
        if (immediate || !refreshTimer.running) {
            refreshTimer.interval = immediate ? 0 : 100;
            refreshTimer.restart();
        }
    }
    property Timer refreshTimer: Timer {
        interval: 100
        onTriggered: ctl.refresh()
    }
    property string error: ""
    property bool posting: false
    property bool transferBusy: false
    property bool transferStarting: false
    property bool transferPolling: false
    property int transferEpoch: 0
    property var transferState: ({})
    property var transferDone: null
    function transferFile(id, operation, done) {
        if (transferBusy) { error = "Wait for the current attachment transfer."; posting = false; return; }
        transferEpoch++;
        transferBusy = true;
        transferStarting = true;
        transferState = {id: id, status: "running"};
        call({op: operation, id: id}, function (r) {
            transferStarting = false;
            if (r.alreadyAvailable) { transferBusy = false; if (done) done(); return; }
            transferState = r.transfer;
            transferDone = done;
            transferBusy = true;
        }, function (message) { transferStarting = false; transferBusy = false; error = message; posting = false; });
    }
    property Timer transferTimer: Timer {
        interval: 250
        repeat: true
        running: ctl.transferBusy && !ctl.transferStarting
        onTriggered: {
          if (ctl.transferPolling) return;
          ctl.transferPolling = true;
          var epoch = ctl.transferEpoch;
          ctl.call({op: "attachmentTransfer"}, function (r) {
            ctl.transferPolling = false;
            if (epoch !== ctl.transferEpoch) return;
            ctl.transferState = r.transfer;
            if (r.transfer.status === "running") return;
            ctl.transferBusy = false;
            var done = ctl.transferDone;
            ctl.transferDone = null;
            if (r.transfer.status === "complete") {
                ctl.refresh();
                if (done) done();
            } else {
                ctl.posting = false;
                ctl.error = r.transfer.error || "Attachment transfer failed.";
            }
        }, function (message) {
            ctl.transferPolling = false;
            if (epoch !== ctl.transferEpoch) return;
            ctl.transferBusy = false;
            ctl.posting = false;
            ctl.transferDone = null;
            ctl.error = message;
        })
        }
    }
    property string playingAttachment: ""
    property string notice: ""
    property var state: ({
            posts: [],
            hasMore: false, nextCursor: "", view: "recent", threadId: "",
            identities: [],
            avatars: {},
            saved: [],
            drafts: {},
            active: "",
            mode: "alias",
            rotate: false
        })
    property string connection: "offline"
    property string connectionDetail: "Local mode · posts stay in your outbox"
    // Subscription is not publishing readiness. Read the shared node's scope;
    // never infer it from our preferred preset or mutate its credentials.
    property string publishingState: "unknown"
    property string publishingDetail: "Checking publishing availability…"
    property bool publishingCheckBusy: false
    property double publishingCheckedAt: 0
    property double publishingCheckStarted: 0
    onPublishingStateChanged: console.log("FORUM_PUBLISHING_STATE", publishingState)
    property int publishingCheckEpoch: 0
    readonly property bool publishingReady: publishingState === "ready"
    function invalidatePublishing() {
        publishingCheckEpoch++;
        publishingCheckBusy = false;
        publishingCheckedAt = 0;
        publishingState = "unknown";
        publishingDetail = "Checking publishing availability…";
    }
    function publishingResult(raw) {
        // Rust module responses can contain a JSON string inside the host wrapper.
        for (var n = 0; n < 6; n++) {
            if (typeof raw === "string") { raw = JSON.parse(raw); continue; }
            if (!raw || raw.error || raw.success === false)
                throw Error(raw ? JSON.stringify(raw.error || "Module call failed") : "Empty module response");
            if (raw.success === true) { raw = raw.value; continue; }
            return raw;
        }
        throw Error("Invalid publishing readiness response");
    }
    function checkPublishing() {
        if (!bridge || connection !== "online" || publishingCheckBusy) return;
        publishingCheckBusy = true;
        publishingCheckStarted = Date.now();
        var token = ++publishingCheckEpoch;
        var epoch = connectionEpoch;
        function current() { return token === publishingCheckEpoch && epoch === connectionEpoch && connection === "online"; }
        function finish(ok, detail) {
            if (!current()) return;
            publishingCheckBusy = false;
            publishingCheckedAt = Date.now();
            publishingState = ok ? "ready" : "blocked";
            publishingDetail = ok ? "" : "Publishing unavailable · posts remain queued. " + detail;
        }
        function invoke(module, method, args, done, timeout) {
            try {
                bridge.callModuleAsync(module, method, args, function(raw) {
                    if (!current()) return;
                    try { done(publishingResult(raw)); }
                    catch (e) { finish(false, String(e)); }
                }, timeout);
            } catch (e) { finish(false, String(e)); }
        }
        invoke("delivery_module", "rlnState", [], function(node) {
            if (node.state === "Disabled") { finish(true, ""); return; }
            if (node.state !== "Ready") {
                finish(false, node.message || "Delivery credentials are not ready."); return;
            }
            if (!node.registryId || !node.rlnIdentifier) {
                finish(false, "Update Logos Delivery to expose its publishing scope."); return;
            }
            invoke("liblogos_rln_module", "get_membership_state", [node.registryId, node.rlnIdentifier], function(membership) {
                var usable = membership.state === "active" || membership.state === "grace_period";
                finish(usable, usable ? "" : "Delivery credentials need attention (" + String(membership.state || "unknown") + ").");
            }, 90000);
        }, 15000);
    }
    property string inFlight: ""
    property int sendEpoch: 0
    property bool claimingPost: false
    property string requestId: ""
    property double started: 0
    // Delivery's retry window can report its result after 60 seconds.
    // Leave room for that terminal event before applying our watchdog.
    readonly property int acknowledgementTimeoutMs: 90000
    readonly property string contentTopic: "/logos-forum/1/commons/json"
    property var eventNames: ["messageSent", "messageError", "messageReceived", "connectionStateChanged", "nodeStarted"]
    function parse(raw) {
        var r = typeof raw === "string" ? JSON.parse(raw) : raw;
        if (!r || r.error || r.success === false)
            throw Error(r ? (typeof r.error === "object" ? JSON.stringify(r.error) : r.error || "Module call failed") : "Empty module response");
        return r.success === true ? r.value : r;
    }
    function call(command, done, failed) {
        var reject = function (e) {
            if (failed)
                failed(String(e));
            else
                error = String(e);
        };
        if (!backend) {
            reject("Forum backend is not ready.");
            return;
        }
        var success = function (raw) {
            try {
                var r = JSON.parse(raw);
                if (!r.ok)
                    throw Error(r.error);
                if (done)
                    done(r);
            } catch (e) {
                reject(e);
            }
        };
        try {
            if (typeof forumLocal !== "undefined")
                success(backend.dispatch(JSON.stringify(command)));
            else
                bridge.watch(backend.dispatch(JSON.stringify(command)), success, function (e) {
                    reject(e);
                });
        } catch (e) {
            reject(e);
        }
    }
    function refresh() {
        if (refreshing) { refreshAgain = true; return; }
        refreshTimer.stop();
        refreshing = true;
        refreshAgain = false;
        var query = {op: "snapshot"};
        for (var key in browseQuery) query[key] = browseQuery[key];
        var version = JSON.stringify(browseQuery);
        call(query, function (r) {
            if (version !== JSON.stringify(browseQuery)) {
                refreshing = false;
                scheduleRefresh();
                return;
            }
            state = r;
            if (!ready)
                console.log("FORUM_STATE_READY", r.identities.length, "identities");
            ready = true;
            if (!startupConnectionChecked) {
                startupConnectionChecked = true;
                if (state.autoConnect && bridge) Qt.callLater(function () { ctl.connectNetwork(true); });
            }
            refreshing = false;
            if (refreshAgain) scheduleRefresh();
        }, function (message) {
            refreshing = false;
            if (version !== JSON.stringify(browseQuery)) { scheduleRefresh(); return; }
            error = message;
        });
    }
    function attach() {
        if (typeof forumLocal === "undefined" && typeof logos !== "undefined") {
            backend = bridge.module("logos_forum");
        }
        if (backend)
            refresh();
    }
    function mutate(command, done) {
        error = "";
        call(command, function (r) {
            refresh();
            if (done)
                done(r);
        });
    }
    function draft(key, body, done, failed) {
        call({
            op: "draft",
            id: key,
            body: body
        }, done, failed);
    }
    function avatarForPost(post) {
        return post && post.mode !== "anonymous" && post.authorId && state.avatars
            ? state.avatars[post.authorId] || null : null;
    }
    function activeAlias() {
        for (var i = 0; i < state.identities.length; i++)
            if (state.identities[i].id === state.active)
                return state.identities[i].alias;
        return "Choose identity";
    }
    function savePost(thread, board, title, body, done, attachments) {
        if (posting) return;
        posting = true;
        error = "";
        var files = attachments || [];
        var index = 0;
        function submit() {
            call({op: "post", thread: thread, board: board, title: title, body: body, attachments: files}, function (r) {
                posting = false;
                refresh();
                notice = r.status === "local" ? "Saved on this device. This conversation is local only." : "Saved locally. Publication requires a confirmed delivery.";
                if (done) done(r);
            }, function (message) { posting = false; error = message; });
        }
        function uploadNext() {
            if (index >= files.length) { submit(); return; }
            transferFile(files[index++], "attachmentUpload", uploadNext);
        }
        if (files.length && state.storageEndpoint && thread) {
            call({op: "postInfo", id: thread}, function (r) {
                if (!r.post || !r.post.id || r.post.thread) { posting = false; error = "Thread is not available locally."; return; }
                if (r.post.status === "local") submit(); else uploadNext();
            }, function (message) { posting = false; error = message; });
        } else if (files.length && state.storageEndpoint) uploadNext();
        else submit();
    }
    function moduleCall(method, args, done, failed) {
        if (!bridge) {
            error = "Logos Delivery is available inside Basecamp.";
            return;
        }
        bridge.callModuleAsync("delivery_module", method, args, function (raw) {
            try {
                done(parse(raw));
            } catch (e) {
                if (failed) { failed(String(e)); return; }
                connection = "error";
                connectionDetail = String(e);
                error = String(e);
                if (inFlight)
                    fail(String(e));
            }
        }, 15000);
    }
    function attachEvents() {
        if (!bridge) {
            error = "Logos Delivery is available inside Basecamp.";
            return false;
        }
        if (!eventsAttached) {
            for (var i = 0; i < eventNames.length; i++)
                bridge.onModuleEvent("delivery_module", eventNames[i]);
            eventsAttached = true;
        }
        return true;
    }
    function connectNetwork(startIfNeeded) {
        if (!attachEvents())
            return;
        if (connection === "connecting" || connection === "online")
            return;
        connection = "connecting";
        var epoch = ++connectionEpoch;
        connectionDetail = "Starting Logos Delivery…";
        error = "";

        // Use the host's shared delivery node if already connected. Never stop or
        // reconfigure a node owned by another app. A fresh node is explicitly started.
        moduleCall("getConnectionStatus", [], function (status) {
            if (epoch !== connectionEpoch) return;
            var connected = String(status).toLowerCase();
            if (connected === "connected" || connected === "partiallyconnected") {
                subscribe();
                return;
            }
            if (startIfNeeded && connected === "disconnected") {
                // Start the existing node without changing its configuration.
                moduleCall("start", [], function () {});
                return;
            }
            if (startIfNeeded && connected === "connecting") return;
            connection = "error";
            connectionDetail = "Start a Delivery node in Basecamp, then connect here.";
        }, function (message) {
            if (epoch !== connectionEpoch) return;
            if (startIfNeeded && message.indexOf("Context not initialized") >= 0) {
                startNode();
                return;
            }
            connection = "error";
            connectionDetail = message;
            error = message;
        });
    }
    function subscribe() {
        if (connection === "offline") return;
        var epoch = connectionEpoch;
        moduleCall("subscribe", [contentTopic], function () {
            if (epoch !== connectionEpoch) return;
            connection = "online";
            invalidatePublishing();
            checkPublishing();
            connectionDetail = "Subscribed via Logos Delivery · public discussions";
            notice = "Connected. Queued messages will be sent gradually.";
        });
    }
    function startNode() {
        if (!attachEvents())
            return;

        connection = "connecting";
        var epoch = ++connectionEpoch;
        connectionDetail = "Creating Delivery node with required mix routing…";
        moduleCall("createNode", [JSON.stringify({
                mode: "Core",
                preset: "logos.test",
                messagingOverrides: {
                    anonymityLevel: "Required",
                    backfillEnabled: true,
                    backfillRequestTimeoutSeconds: 10
                }
            })], function () {
            if (epoch !== connectionEpoch) return;
            moduleCall("start", [], function () {
                connectionDetail = "Waiting for node start and peers…";
            });
        });
    }
    function loadHistory(peer) {
        if (!peer || peer.indexOf("/") !== 0) {
            error = "Enter a Store peer multiaddress.";
            return;
        }
        var query = {
            requestId: "forum-history-" + Date.now(),
            includeData: true,
            paginationForward: true,
            contentTopics: [contentTopic],
            paginationLimit: 50
        };
        if (state.historyPeer === peer && state.historyCursor)
            query.paginationCursor = state.historyCursor;
        moduleCall("storeQuery", [JSON.stringify(query), peer, 10000], function (value) {
            var page = typeof value === "string" ? JSON.parse(value) : value;
            mutate({
                op: "historyPage",
                peer: peer,
                page: page
            }, function (r) {
                notice = "History: " + r.accepted + " recovered, " + r.duplicates + " already stored, " + r.rejected + " rejected.";
            });
        });
    }
    function disconnect() {
        connectionEpoch++;
        invalidatePublishing();
        connection = "offline";
        connectionDetail = "Local mode · drafts and posts stay on this device";/* Do not stop the shared host node. */
    }
    function fail(message) {
        var pid = inFlight;
        inFlight = "";
        requestId = "";
        if (pid)
            mutate({
                op: "delivery",
                id: pid,
                status: "failed",
                error: message
            });
    }
    function retryPost(id) {
        if (!id) return;
        mutate({op: "retry", id: id}, function() {
            // Retry the stored envelope, never compose a second post.
            if (connection === "online") {
                invalidatePublishing();
                checkPublishing();
            }
            pump();
        });
    }
    function pump() {
        if (claimingPost) return;
        if (inFlight) {
            if (Date.now() - started > acknowledgementTimeoutMs)
                fail("Delivery acknowledgement timed out. Retry uses the same message ID.");
            return;
        }
        if (connection !== "online" || !ready)
            return;
        if (publishingCheckBusy && Date.now() - publishingCheckStarted > 110000) {
            publishingCheckEpoch++;
            publishingCheckBusy = false;
            publishingCheckedAt = Date.now();
            publishingState = "blocked";
            publishingDetail = "Publishing unavailable · credential check timed out. Posts remain queued.";
        }
        var age = Date.now() - publishingCheckedAt;
        if (!publishingCheckedAt || age >= (publishingReady ? 60000 : 30000)) {
            // Expired readiness cannot authorize another send during a slow check.
            publishingState = "checking";
            checkPublishing();
        }
        if (!publishingReady || publishingCheckBusy) return;
        claimingPost = true;
        call({
            op: "next"
        }, function (r) {
            claimingPost = false;
            if (!r.item)
                return;
            var pid = r.item.id, epoch = ++sendEpoch;
            inFlight = pid;
            started = Date.now();
            requestId = "";
            earlyEvents = [];
            // Encode through native QByteArray property, not an ambiguous JS string.
            Qt.callLater(function () {
                if (epoch !== sendEpoch || inFlight !== pid) return;
                moduleCall("send", [contentTopic, backend.outboundPayload], function (value) {
                    if (epoch !== sendEpoch || inFlight !== pid)
                        return;
                    requestId = String(value);
                    mutate({
                        op: "delivery",
                        id: pid,
                        status: "sending",
                        request: requestId
                    });
                    var pending = earlyEvents;
                    earlyEvents = [];
                    for (var i = 0; i < pending.length; i++)
                        event(pending[i].name, pending[i].data);
                }, function(message) {
                    if (epoch === sendEpoch && inFlight === pid) fail(message);
                });
            });
        }, function(message) { claimingPost = false; error = message; });
    }
    function event(name, data) {
        if ((name === "messageSent" || name === "messageError") && inFlight && !requestId) {
            if (earlyEvents.length < 32)
                earlyEvents.push({
                    name: name,
                    data: data
                });
            return;
        }
        if (name === "nodeStarted" && connection !== "offline") {
            if (data[0])
                subscribe();
            else {
                connection = "error";
                connectionDetail = String(data[1]);
            }
            return;
        }
        if (name === "messageReceived" && data[1] === contentTopic && connection === "online") {
            if (pendingReceives >= 32) {
                notice = "Incoming traffic is busy. Recover missed posts from Network → Advanced.";
                return;
            }
            pendingReceives++;
            var receive = function (raw) {
                pendingReceives--;
                try {
                    var r = JSON.parse(raw);
                    if (!r.ok) {
                        notice = r.rateLimited ? "Incoming traffic is busy. Recover missed posts from Network → Advanced." : "An invalid network message was rejected.";
                        return;
                    }
                    if (!r.duplicate) scheduleRefresh();
                } catch (e) {
                    error = String(e);
                }
            };
            try {
                if (typeof forumLocal !== "undefined")
                    receive(backend.receiveBytes(data[2]));
                else
                    bridge.watch(backend.receiveBytes(data[2]), receive, function (e) {
                        pendingReceives--;
                        error = String(e);
                    });
            } catch (e) {
                pendingReceives--;
                error = String(e);
            }
            return;
        }
        if (name === "messageSent" && requestId && String(data[0]) === requestId) {
            var pid = inFlight;
            inFlight = "";
            requestId = "";
            mutate({
                op: "delivery",
                id: pid,
                status: "sent"
            });
            return;
        }
        if (name === "messageError" && requestId && String(data[0]) === requestId) {
            fail(String(data[2]));
            if (/rln|membership|credential|ambiguous_selection/i.test(String(data[2]))) {
                invalidatePublishing();
                checkPublishing();
            }
            return;
        }
        if (name === "connectionStateChanged" && connection !== "offline") {
            var s = String(data[0]).toLowerCase();
            if (s === "connected" || s === "partiallyconnected") {
                if (connection !== "online")
                    subscribe();
            } else
                connection = "connecting";
            connectionDetail = String(data[0]);
        }
    }
    property Connections backendSignals: Connections {
        target: ctl.backend
        ignoreUnknownSignals: true
        function onChanged() {
            ctl.scheduleRefresh();
        }
    }
    property Connections bridgeSignals: Connections {
        target: ctl.bridge
        ignoreUnknownSignals: true
        function onViewModuleReadyChanged(name, isReady) {
            if (name === "logos_forum" && isReady)
                ctl.attach();
        }
        function onModuleEventReceived(moduleName, eventName, data) {
            if (moduleName === "delivery_module")
                ctl.event(eventName, data);
        }
    }
    property Timer pumpTimer: Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: ctl.pump()
    }
    Component.onCompleted: Qt.callLater(attach)
}
