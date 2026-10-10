import QtQuick

QtObject {
    id: ctl
    property var backend: typeof forumLocal !== "undefined" ? forumLocal : null
    property var bridge: typeof logos !== "undefined" ? logos : null
    property bool eventsAttached: false
    property var earlyEvents: []
    property bool ready: false
    property string error: ""
    property string playingAttachment: ""
    property string notice: ""
    property var state: ({
            posts: [],
            identities: [],
            saved: [],
            drafts: {},
            active: "",
            mode: "alias",
            rotate: false
        })
    property string connection: "offline"
    property string connectionDetail: "Local mode · posts stay in your outbox"
    property string inFlight: ""
    property string requestId: ""
    property double started: 0
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
        call({
            op: "snapshot"
        }, function (r) {
            state = r;
            if (!ready)
                console.log("FORUM_STATE_READY", r.identities.length, "identities");
            ready = true;
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
    function draft(key, body) {
        call({
            op: "draft",
            id: key,
            body: body
        });
    }
    function activeAlias() {
        for (var i = 0; i < state.identities.length; i++)
            if (state.identities[i].id === state.active)
                return state.identities[i].alias;
        return "Choose identity";
    }
    function savePost(thread, board, title, body, done, attachments) {
        mutate({
            op: "post",
            thread: thread,
            board: board,
            title: title,
            body: body,
            attachments: attachments || []
        }, function (r) {
            notice = r.status === "local" ? "Saved on this device. This conversation is local only." : "Saved locally. Publication requires a confirmed delivery.";
            if (done)
                done(r);
        });
    }
    function moduleCall(method, args, done) {
        if (!bridge) {
            error = "Logos Delivery is available inside Basecamp.";
            return;
        }
        bridge.callModuleAsync("delivery_module", method, args, function (raw) {
            try {
                done(parse(raw));
            } catch (e) {
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
    function connectNetwork() {
        if (!attachEvents())
            return;
        if (connection === "connecting" || connection === "online")
            return;
        connection = "connecting";
        connectionDetail = "Starting Logos Delivery…";
        error = "";

        // Use the host's shared delivery node if already connected. Never stop or
        // reconfigure a node owned by another app. A fresh node is explicitly started.
        moduleCall("getConnectionStatus", [], function (status) {
            if (String(status).toLowerCase().indexOf("connected") === 0) {
                subscribe();
                return;
            }
            connection = "error";
            connectionDetail = "Start a Delivery node in Basecamp, then connect here.";
        });
    }
    function subscribe() {
        moduleCall("subscribe", [contentTopic], function () {
            connection = "online";
            connectionDetail = "Subscribed via Logos Delivery · public discussions";
            notice = "Connected. Queued messages will be sent gradually.";
        });
    }
    function startNode() {
        if (!attachEvents())
            return;

        connection = "connecting";
        connectionDetail = "Creating Delivery node with required mix routing…";
        moduleCall("createNode", [JSON.stringify({
                mode: "Core",
                preset: "bridge.test",
                messagingOverrides: {
                    anonymityLevel: "Required",
                    backfillEnabled: true,
                    backfillRequestTimeoutSeconds: 10
                }
            })], function () {
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
    function pump() {
        if (inFlight) {
            if (Date.now() - started > 60000)
                fail("Delivery acknowledgement timed out. Retry uses the same message ID.");
            return;
        }
        if (connection !== "online" || !ready)
            return;
        call({
            op: "next"
        }, function (r) {
            if (!r.item)
                return;
            inFlight = r.item.id;
            started = Date.now();
            requestId = "";
            earlyEvents = [];
            // Encode through native QByteArray property, not an ambiguous JS string.
            Qt.callLater(function () {
                moduleCall("send", [contentTopic, backend.outboundPayload], function (value) {
                    if (!inFlight)
                        return;
                    requestId = String(value);
                    mutate({
                        op: "delivery",
                        id: inFlight,
                        status: "sending",
                        request: requestId
                    });
                    var pending = earlyEvents;
                    earlyEvents = [];
                    for (var i = 0; i < pending.length; i++)
                        event(pending[i].name, pending[i].data);
                });
            });
        });
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
            var receive = function (raw) {
                try {
                    var r = JSON.parse(raw);
                    if (!r.ok) {
                        notice = "An invalid network message was rejected.";
                        return;
                    }
                    refresh();
                } catch (e) {
                    error = String(e);
                }
            };
            if (typeof forumLocal !== "undefined")
                receive(backend.receiveBytes(data[2]));
            else
                bridge.watch(backend.receiveBytes(data[2]), receive, function (e) {
                    error = String(e);
                });
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
            return;
        }
        if (name === "connectionStateChanged" && connection !== "offline") {
            var s = String(data[0]).toLowerCase();
            if (s === "connected") {
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
            ctl.refresh();
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
