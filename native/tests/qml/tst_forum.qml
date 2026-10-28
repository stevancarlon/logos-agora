import QtQuick
import QtTest
import "../../forum/qml" as Forum

TestCase {
    id: testCase
    name: "ForumWorkflows"
    width: 1100
    height: 760
    visible: true
    when: windowShown
    Component {
        id: appComponent
        Forum.Main {
            width: 1100
            height: 760
        }
    }
    property var app
    Component {
        id: deliveryBridgeComponent
        QtObject {
            property var calls: []
            property string nodeStatus: "Connected"
            property bool uninitialized: false
            property var subscriptionDone: null
            function onModuleEvent(module, name) {}
            function callModuleAsync(module, method, args, done, timeout) {
                calls.push(method);
                if (method === "getConnectionStatus") {
                    done(uninitialized ? {success: false, error: "Context not initialized"} : {success: true, value: nodeStatus});
                } else if (method === "subscribe") {
                    subscriptionDone = done;
                } else {
                    done({success: true, value: true});
                }
            }
        }
    }
    function test_connectReusesSharedNodeAndOfflineCancelsSubscription() {
        var bridge = createTemporaryObject(deliveryBridgeComponent, testCase);
        var c = app.controller;
        c.bridge = bridge;
        c.connectNetwork(true);
        compare(bridge.calls.join(","), "getConnectionStatus,subscribe");
        c.disconnect();
        bridge.subscriptionDone({success: true, value: true});
        compare(c.connection, "offline");
    }
    function test_connectCreatesOnlyMissingNode() {
        var bridge = createTemporaryObject(deliveryBridgeComponent, testCase, {uninitialized: true});
        var c = app.controller;
        c.bridge = bridge;
        c.connectNetwork(true);
        compare(bridge.calls.join(","), "getConnectionStatus,createNode,start");
        c.disconnect();
        bridge.calls = [];
        bridge.uninitialized = false;
        bridge.nodeStatus = "Disconnected";
        c.connectNetwork(true);
        compare(bridge.calls.join(","), "getConnectionStatus,start");
        c.disconnect();
    }
    Component { id: stateSpyComponent; SignalSpy { signalName: "stateChanged" } }
    function test_buttonInteractionFeedback() {
        var button = findChild(app, "newThreadButton");
        mouseMove(button, button.width / 2, button.height / 2);
        tryCompare(button, "hovered", true);
        mousePress(button, button.width / 2, button.height / 2);
        tryVerify(function () { return button.scale < 0.99; });
        mouseRelease(button, button.width / 2, button.height / 2);
        tryCompare(findChild(app, "composeDialog"), "opened", true);
        tryCompare(button, "scale", 1);
        findChild(app, "composeDialog").close();
    }
    function test_returnToFeedRestoresPosition() {
        app.searchText = "Reading position fixture";
        for (var n = 0; n < 18; ++n)
            app.controller.call({op: "post", board: "general", title: "Reading position fixture " + n, body: "A longer discussion opener to exercise the scroll position."});
        app.controller.refresh();
        tryVerify(function () { return !app.controller.loading && app.visibleThreads.length === 18; });
        var list = findChild(app, "threadListView");
        list.positionViewAtIndex(8, ListView.Beginning);
        tryVerify(function () { return list.contentY > 200; });
        var offset = list.contentY;
        var selected = app.visibleThreads[8].id;
        app.openThread(selected);
        tryVerify(function () { return !app.controller.loading && app.discussionPosts.length > 0; });
        var back = findChild(app, "backToDiscussions");
        mouseClick(back, back.width / 2, back.height / 2);
        tryVerify(function () { return !app.controller.loading && app.selected === ""; });
        compare(app.searchText, "Reading position fixture");
        tryVerify(function () { return Math.abs(list.contentY - offset) < 3; });
    }
    function test_draftRefreshPreservesPostDelegate() {
        var id = "";
        app.controller.call({op: "post", board: "general", title: "Stable reading", body: "Select this text while drafting."}, function (r) { id = r.id; });
        app.openThread(id);
        tryVerify(function () { return !app.controller.loading && app.discussionPosts.length === 1; });
        var body = findChild(app, "post-body-" + id);
        verify(body !== null);
        body.select(0, 6);
        app.controller.draft(id, "Unfinished reply");
        app.controller.refresh();
        tryVerify(function () { return !app.controller.loading; });
        compare(findChild(app, "post-body-" + id), body);
        compare(body.selectedText, "Select");
    }
    function test_smallDialogScrollAndInlineError() {
        app.width = 400; app.height = 540;
        app.compose();
        var dialog = findChild(app, "composeDialog");
        tryCompare(dialog, "opened", true);
        verify(dialog.height <= app.height - 32);
        app.controller.error = "Could not save. Your draft is still here.";
        var errorLabel = findChild(app, "composeError");
        tryCompare(errorLabel, "visible", true);
        verify(errorLabel.text.indexOf("draft") >= 0);
        verify(dialog.contentItem.contentHeight > dialog.contentItem.height);
        dialog.contentItem.contentItem.contentY = dialog.contentItem.contentHeight - dialog.contentItem.height;
        var submit = findChild(app, "submitThreadButton");
        tryVerify(function () { return submit.mapToItem(app, submit.width, submit.height).x <= app.width - 16; });
        tryVerify(function () { return submit.mapToItem(app, 0, submit.height).y <= app.height - 16; });
        dialog.close();
        tryCompare(dialog, "visible", false);
        var profile = findChild(app, "identityDialog");
        profile.open();
        tryCompare(profile, "opened", true);
        verify(profile.height <= app.height - 32);
        verify(profile.contentItem.contentHeight > profile.contentItem.height);
        profile.close();
    }
    function test_mediumWidthAndSearchClear() {
        app.width = 950;
        tryCompare(app, "narrow", true);
        var profile = findChild(app, "profileButton");
        tryVerify(function () { return profile.mapToItem(app, profile.width, 0).x <= app.width - 16; });
        app.searchText = "Nothing matches this query";
        var search = findChild(app, "compactSearchField");
        verify(search !== null);
        var clear = findChild(search, "clearSearch");
        tryCompare(clear, "visible", true);
        mouseClick(clear, clear.width / 2, clear.height / 2);
        compare(app.searchText, "");
        tryCompare(search, "activeFocus", true);
    }
    function test_escapeCollapsesReplyWithoutLosingDraft() {
        var id = "";
        app.controller.call({op: "post", board: "general", title: "Escape draft", body: "Opening"}, function (r) { id = r.id; });
        app.openThread(id);
        tryVerify(function () { return !app.controller.loading; });
        app.beginReply();
        var input = findChild(app, "replyInput");
        input.text = "Keep this unfinished thought";
        keyClick(Qt.Key_Escape);
        tryCompare(app, "replyExpanded", false);
        compare(app.replyDraftCache[id], "Keep this unfinished thought");
        app.beginReply();
        compare(input.text, "Keep this unfinished thought");
    }
    function test_responsiveHeaderBounds() {
        var widths = [400, 950, 1080, 1100, 1440, 1780];
        var profile = findChild(app, "profileButton");
        var search = findChild(app, "headerSearch");
        var lastBoard = findChild(app, "board-governance");
        for (var i = 0; i < widths.length; i++) {
            app.width = widths[i];
            tryVerify(function () { return profile.mapToItem(app, profile.width, 0).x <= app.width - 16; });
            if (!app.narrow)
                tryVerify(function () { return lastBoard.mapToItem(app, lastBoard.width, 0).x + 8 <= search.mapToItem(app, 0, 0).x; });
        }
    }
    function test_networkBurstRefreshesOnce() {
        var c = app.controller;
        tryCompare(c, "refreshing", false);
        var spy = createTemporaryObject(stateSpyComponent, testCase, {target: c});
        for (var n = 0; n < 100; ++n) c.scheduleRefresh();
        tryCompare(spy, "count", 1);
        wait(150);
        compare(spy.count, 1);
        c.connection = "online";
        c.pendingReceives = 32;
        c.event("messageReceived", ["test", c.contentTopic, ""]);
        compare(c.pendingReceives, 32);
        verify(c.notice.indexOf("Recover missed posts") >= 0);
        c.pendingReceives = 0;
        c.disconnect();
    }
    Component {
        id: remoteAttachmentComponent
        Forum.AttachmentCard { }
    }
    function init() {
        app = createTemporaryObject(appComponent, testCase);
        verify(app !== null);
        tryCompare(app.controller, "ready", true);
    }
    function test_longThreadShowsSubmittedReply() {
        var rootId = "", lastId = "";
        app.controller.call({op: "post", board: "general", title: "Long reply test", body: "Opening"}, function(r) { rootId = r.id; });
        verify(rootId.length > 0);
        for (var n = 0; n < 55; ++n)
            app.controller.call({op: "post", board: "general", thread: rootId, body: "Earlier reply " + n});
        app.openThread(rootId);
        tryVerify(function () { return !app.controller.loading && app.replies(rootId).length === 50; });
        app.controller.savePost(rootId, "general", "", "New visible reply", function(r) {
            lastId = r.id;
            app.showPostedReply(rootId, r.id);
        });
        tryVerify(function () { return lastId.length > 0 && !app.controller.loading && app.findPost(lastId) !== null; });
        tryCompare(app, "pendingReplyScroll", "");
        var list = findChild(app, "postsView");
        tryVerify(function () { return list.atYEnd; });
        verify(app.replyHistory.length > 0);
        app.previousPage();
        tryVerify(function () { return !app.controller.loading && app.replyCursor === ""; });
    }
    function test_paginationNavigation() {
        app.searchText = "pagination fixture";
        for (var n = 0; n < 31; ++n) {
            app.controller.call({op: "post", board: "general", title: "pagination fixture " + n, body: "Temporary test discussion"});
        }
        app.controller.refresh();
        tryVerify(function () { return !app.controller.loading && app.visibleThreads.length === 30; });
        verify(app.controller.state.hasMore);
        app.nextPage();
        tryVerify(function () { return !app.controller.loading && app.visibleThreads.length === 1; });
        verify(!app.controller.state.hasMore);
        compare(app.feedHistory.length, 1);
        app.previousPage();
        tryVerify(function () { return !app.controller.loading && app.visibleThreads.length === 30; });
        compare(app.feedHistory.length, 0);
        app.nextPage();
        tryVerify(function () { return !app.controller.loading && app.visibleThreads.length === 1; });
        app.searchText = "no such pagination fixture";
        tryVerify(function () { return !app.controller.loading && app.visibleThreads.length === 0; });
        compare(app.feedCursor, "");
        compare(app.feedHistory.length, 0);
    }
    function test_headerNavigation() {
        var saved = findChild(app, "savedTab"), discussions = findChild(app, "discussionsTab");
        var profile = findChild(app, "profileButton");
        var profileDialog = findChild(app, "identityDialog");
        mouseClick(profile, profile.width / 2, profile.height / 2);
        tryCompare(profileDialog, "opened", true);
        tryCompare(saved, "visible", true);
        mouseClick(saved, saved.width / 2, saved.height / 2);
        tryCompare(profileDialog, "visible", false);
        compare(app.showingSaved, true);
        var general = findChild(app, "board-general");
        mouseClick(general, general.width / 2, general.height / 2);
        compare(app.board, "general");
        compare(app.showingSaved, false);
        var sort = findChild(app, "sortFilter");
        sort.forceActiveFocus();
        keyClick(Qt.Key_Down);
        compare(app.sorting, "newest");
        mouseClick(discussions, discussions.width / 2, discussions.height / 2);
        compare(app.showingSaved, false);
        compare(app.board, "all");
        var search = findChild(app, "headerSearch");
        search.forceActiveFocus();
        keyClick(Qt.Key_Z);
        compare(app.searchText, "z");
        mouseClick(profile, profile.width / 2, profile.height / 2);
        tryCompare(profileDialog, "opened", true);
        var status = findChild(app, "networkStatus");
        mouseClick(status, status.width / 2, status.height / 2);
        tryCompare(findChild(app, "networkDialog"), "opened", true);
        findChild(app, "networkDialog").close();
        tryCompare(findChild(app, "networkDialog"), "visible", false);
        app.width = 400;
        tryCompare(app, "narrow", true);
        var board = findChild(app, "boardFilter");
        verify(waitForRendering(board));
        mouseClick(profile, profile.width / 2, profile.height / 2);
        tryCompare(profileDialog, "opened", true);
        mouseClick(saved, saved.width / 2, saved.height / 2);
        tryCompare(profileDialog, "visible", false);
        compare(app.showingSaved, true);
        board.forceActiveFocus();
        keyClick(Qt.Key_Down);
        compare(app.board, "general");
        tryCompare(profileDialog, "visible", false);
        compare(app.showingSaved, true);
        var edge = board.mapToItem(app, board.width, 0);
        verify(edge.x <= app.width);
    }
    function test_feedReplyAction() {
        var id = "";
        app.controller.savePost("", "general", "Direct reply test", "Read and respond", function (r) {
            id = r.id;
        });
        app.searchText = "Direct reply test";
        tryVerify(function () { return !app.controller.loading && app.visibleThreads.length === 1; });
        var replyButton = null;
        tryVerify(function () {
            replyButton = findChild(app, "reply-" + id);
            return replyButton !== null;
        });
        verify(waitForRendering(replyButton));
        mouseClick(replyButton, replyButton.width / 2, replyButton.height / 2);
        compare(app.selected, id);
        compare(app.replyExpanded, true);
        tryCompare(findChild(app, "replyInput"), "activeFocus", true);
    }
    function test_attachmentCardAndLocalReply() {
        var file = null, id = "";
        app.controller.call({
            op: "attachmentImport",
            file: Qt.resolvedUrl("../../forum/assets/icon.png").toString()
        }, function (r) {
            file = r.attachment;
        });
        verify(file !== null);
        app.controller.savePost("", "general", "An attached picture", "Image example", function (r) {
            id = r.id;
        }, [file.id]);
        app.openThread(id);
        var card = null;
        tryVerify(function () {
            card = findChild(app, "attachment-" + file.id);
            return card !== null && card.preview !== null;
        });
        verify(waitForRendering(card));
        compare(app.current.status, "local");
        app.width = 400;
        wait(20);
        verify(card.mapToItem(app, card.width, 0).x <= app.width);
        app.controller.savePost(id, "general", "", "A local reply", function () {});
        verify(app.controller.notice.indexOf("local only") >= 0);
    }
    Component {
        id: delayedAttachmentController
        QtObject {
            property var completion
            function call(command, done) {
                completion = done;
            }
        }
    }
    Component {
        id: attachmentCardComponent
        Forum.AttachmentCard {}
    }
    function test_thumbnailReplyAfterCardRemoved() {
        var ctl = createTemporaryObject(delayedAttachmentController, testCase);
        var card = createTemporaryObject(attachmentCardComponent, testCase, {
            controller: ctl,
            attachment: {
                id: "delayed",
                name: "example.png",
                mime: "image/png",
                bytes: 100
            }
        });
        verify(typeof ctl.completion === "function");
        card.destroy();
        wait(1);
        ctl.completion({
            image: {
                width: 1,
                height: 1,
                pixels: [4294967295]
            }
        });
    }
    function test_inlineVideoPlayback() {
        var file = null, id = "";
        app.controller.call({
            op: "attachmentImport",
            file: Qt.resolvedUrl("../../../design/agora/demo-media/playback-test.mp4").toString()
        }, function (r) {
            file = r.attachment;
        });
        verify(file !== null);
        app.controller.savePost("", "building", "Video playback", "Local video", function (r) {
            id = r.id;
        }, [file.id]);
        app.openThread(id);
        var player = null;
        tryVerify(function () {
            player = findChild(app, "video-" + file.id);
            return player !== null;
        });
        player.playPause();
        tryVerify(function () {
            return player.decodedFrames > 2 && player.position > 100;
        }, 10000);
        compare(player.failure, "");
        mouseMove(player, player.width / 2, player.height / 2);
        tryCompare(player, "controlsShown", true);
        var controls = findChild(player, "videoControls-" + file.id);
        tryCompare(controls, "opacity", 1);
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
        tryCompare(player, "controlsShown", false);
        tryCompare(controls, "opacity", 0);
        player.forceActiveFocus();
        tryCompare(player, "controlsShown", true);
        player.playPause();
        tryCompare(player, "playing", false);
        verify(player.state.seekable);
        player.seekTo(3000);
        tryVerify(function () {
            return Math.abs(player.position - 3000) < 300;
        });
        player.playPause();
        tryCompare(player, "playing", true);
        app.controller.playingAttachment = "another-video";
        tryCompare(player, "playing", false);
        app.controller.playingAttachment = file.id;
        player.playPause();
        tryCompare(player, "playing", true);
        app.controller.draft(id, "Typing while watching");
        app.controller.refresh();
        tryVerify(function () { return !app.controller.loading; });
        compare(findChild(app, "video-" + file.id), player);
        verify(player.playing);
        app.leaveThread();
        wait(10);
        var current = null;
        app.controller.call({
            op: "attachmentVideo",
            action: "state"
        }, function (r) {
            current = r.video;
        });
        compare(current.id, "");
        compare(current.playing, false);
    }
    function test_remoteAttachmentRequiresExplicitFetch() {
        var calls = [];
        var controller = {
            transferBusy: false,
            transferState: {},
            call: function (request, done) { calls.push(request.op); },
            transferFile: function (id, operation, done) { calls.push(operation + ":" + id); }
        };
        var card = createTemporaryObject(remoteAttachmentComponent, testCase, {
            attachment: {id: "remote-video", name: "shared.mp4", mime: "video/mp4", bytes: 556240, available: false},
            controller: controller
        });
        verify(card !== null);
        verify(waitForRendering(card));
        compare(calls.length, 0);
        var button = findChild(card, "fetchAttachment");
        verify(button.visible);
        mouseClick(button, button.width / 2, button.height / 2);
        compare(calls.length, 1);
        compare(calls[0], "attachmentFetch:remote-video");
    }
    function test_profileAvatar() {
        var button = findChild(app, "profileButton");
        verify(waitForRendering(button));
        mouseClick(button, button.width / 2, button.height / 2);
        var dialog = findChild(app, "identityDialog");
        tryCompare(dialog, "opened", true);
        compare(dialog.title, "Profile");
        app.controller.mutate({
            op: "avatar",
            file: Qt.resolvedUrl("../../forum/assets/icon.png").toString()
        });
        compare(app.controller.error, "");
        compare(button.avatar.pixels.length, 4096);
        verify(waitForRendering(button));
        app.controller.mutate({
            op: "avatar",
            remove: true
        });
        verify(!button.avatar);
        dialog.close();
    }
    function test_themeToggle() {
        app.controller.mutate({
            op: "settings",
            theme: "dark"
        });
        compare(app.darkTheme, true);
        var toggle = findChild(app, "themeToggle");
        verify(waitForRendering(toggle));
        mouseClick(toggle, toggle.width / 2, toggle.height / 2);
        tryCompare(app, "darkTheme", false);
        compare(app.controller.state.theme, "light");
        mouseClick(toggle, toggle.width / 2, toggle.height / 2);
        tryCompare(app, "darkTheme", true);
    }
    function test_composePersistQuoteAndReply() {
        app.compose();
        var dialog = findChild(app, "composeDialog");
        tryCompare(dialog, "opened", true);
        var title = findChild(app, "titleInput"), body = findChild(app, "bodyInput");
        title.text = "A native UI test discussion";
        body.text = "A meaningful question for testing the local workflow.";
        app.saveNewDraft();
        verify(app.controller.state.drafts !== null);
        var result = null;
        app.controller.savePost("", "general", title.text, body.text, function (r) {
            result = r;
        });
        verify(result !== null);
        dialog.close();
        app.openThread(result.id);
        compare(app.current.title, "A native UI test discussion");
        compare(app.current.status, "queued");
        app.quote(app.current);
        var reply = findChild(app, "replyInput");
        verify(reply.text.indexOf(">>" + result.id.substring(0, 8)) === 0);
        app.controller.savePost(result.id, "general", "", "A tested reply", function () {});
        compare(app.replies(result.id).length, 1);
        app.controller.mutate({
            op: "bookmark",
            id: result.id
        });
        verify(app.controller.state.saved.indexOf(result.id) >= 0);
    }
    function test_replyDraftSurvivesNavigation() {
        var first = "", second = "";
        app.controller.savePost("", "general", "First draft target", "First body", function (r) {
            first = r.id;
        });
        app.controller.savePost("", "general", "Second draft target", "Second body", function (r) {
            second = r.id;
        });
        app.openThread(first);
        compare(app.replyExpanded, false);
        var prompt = findChild(app, "beginReplyButton");
        verify(waitForRendering(prompt));
        mouseClick(prompt, prompt.width / 2, prompt.height / 2);
        compare(app.replyExpanded, true);
        var input = findChild(app, "replyInput");
        input.text = "Preserve first draft before debounce";
        app.openThread(second);
        compare(input.text, "");
        app.beginReply();
        input.text = "Separate second draft";
        app.goBoard("general");
        app.controller.refresh();
        compare(app.controller.state.drafts[first], "Preserve first draft before debounce");
        compare(app.controller.state.drafts[second], "Separate second draft");
        app.openThread(first);
        compare(input.text, "Preserve first draft before debounce");
        compare(app.replyExpanded, false);
        app.quote(app.current);
        compare(app.replyExpanded, true);
        verify(input.text.indexOf(">>" + first.substring(0, 8)) >= 0);
    }
    function test_escapePreservesDraftImmediately() {
        app.compose();
        var dialog = findChild(app, "composeDialog");
        tryCompare(dialog, "opened", true);
        findChild(app, "titleInput").text = "Immediate draft";
        findChild(app, "bodyInput").text = "Close before debounce";
        dialog.close();
        app.controller.refresh();
        var draft = JSON.parse(app.controller.state.drafts.new);
        compare(draft.title, "Immediate draft");
    }
    function test_emptySearchAndBoardNavigation() {
        app.searchText = "does-not-match-any-real-post-7846";
        tryVerify(function () { return app.visibleThreads.length === 0; });
        app.goBoard("privacy");
        compare(app.selected, "");
        compare(app.board, "privacy");
    }
    function test_identitySwitch() {
        app.controller.mutate({
            op: "identity",
            alias: "test-alias"
        });
        compare(app.controller.activeAlias(), "test-alias");
        app.controller.mutate({
            op: "settings",
            mode: "anonymous"
        });
        compare(app.controller.state.mode, "anonymous");
    }
    function test_narrowLayout() {
        app.width = 560;
        tryCompare(app, "narrow", true);
        verify(app.width <= testCase.width);
        app.compose();
        tryCompare(findChild(app, "composeDialog"), "opened", true);
        verify(findChild(app, "composeDialog").width <= app.width);
    }
    function test_moduleResultParser() {
        compare(app.controller.parse('{"success":true,"value":"Connected"}'), "Connected");
        var failed = false;
        try {
            app.controller.parse('{"success":false,"error":"offline"}');
        } catch (e) {
            failed = true;
        }
        verify(failed);
    }
    Component {
        id: fakeBridgeComponent
        QtObject {
            property var controller
            property bool reject: false
            property var nodeConfig: null
            signal moduleEventReceived(string moduleName, string eventName, var data)
            function onModuleEvent(module, event) {
            }
            function callModuleAsync(module, method, args, done, timeout) {
                if (method === "createNode") {
                    nodeConfig = JSON.parse(args[0]);
                    var supported = ["", "twn", "logos.dev", "logos.test", "status.prod"];
                    done(JSON.stringify({success: supported.indexOf(nodeConfig.preset) >= 0,
                                         value: true, error: supported.indexOf(nodeConfig.preset) >= 0 ? "" : "Unsupported preset"}));
                } else if (method === "start") {
                    done(JSON.stringify({success: true, value: true}));
                    controller.event("nodeStarted", [true, ""]);
                } else if (method === "send") {
                    controller.event(reject ? "messageError" : "messageSent", ["early-ack", "", "peer refused"]);
                    done(JSON.stringify({
                        success: true,
                        value: "early-ack"
                    }));
                } else
                    done(JSON.stringify({
                        success: true,
                        value: method === "getConnectionStatus" ? "Connected" : true
                    }));
            }
        }
    }
    function test_startDeliveryNode() {
        var c = app.controller, b = createTemporaryObject(fakeBridgeComponent, testCase, {controller: c});
        c.bridge = b;
        c.startNode();
        compare(c.error, "");
        compare(c.connection, "online");
        compare(b.nodeConfig.messagingOverrides.anonymityLevel, "Required");
        compare(b.nodeConfig.messagingOverrides.backfillEnabled, true);
    }
    function test_partialConnectivityKeepsSubscription() {
        var c = app.controller, b = createTemporaryObject(fakeBridgeComponent, testCase, {controller: c});
        c.bridge = b;
        c.connectNetwork();
        c.event("connectionStateChanged", ["PartiallyConnected"]);
        compare(c.connection, "online");
        compare(c.connectionDetail, "PartiallyConnected");
        c.disconnect();
        c.event("connectionStateChanged", ["PartiallyConnected"]);
        compare(c.connection, "offline");
    }
    function test_earlyDeliveryAcknowledgement() {
        var c = app.controller, b = createTemporaryObject(fakeBridgeComponent, testCase, {
            controller: c
        });
        c.bridge = b;
        c.connectNetwork();
        compare(c.connection, "online");
        var id = "";
        c.savePost("", "general", "Transport test", "Persist before sending", function (r) {
            id = r.id;
        });
        for (var n = 0; n < 20 && app.findPost(id).status !== "sent"; n++) {
            c.pump();
            tryCompare(c, "inFlight", "");
        }
        compare(app.findPost(id).status, "sent");
        c.disconnect();
        compare(c.connection, "offline");
    }
    function test_deliveryFailureRetainsPost() {
        var c = app.controller, b = createTemporaryObject(fakeBridgeComponent, testCase, {
            controller: c,
            reject: true
        });
        c.bridge = b;
        c.connectNetwork();
        var id = "";
        c.savePost("", "general", "Failed transport test", "Retain this post", function (r) {
            id = r.id;
        });
        for (var n = 0; n < 20 && app.findPost(id).status !== "failed"; n++) {
            c.pump();
            tryCompare(c, "inFlight", "");
        }
        compare(app.findPost(id).status, "failed");
        compare(app.findPost(id).body, "Retain this post");
        verify(app.findPost(id).error.indexOf("peer refused") >= 0);
    }
}
