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
    function test_automaticConnectionRespectsProfilePreference_data() {
        return [{tag: "automatic", enabled: true}, {tag: "local-only", enabled: false}];
    }
    function test_automaticConnectionRespectsProfilePreference(data) {
        var c = app.controller;
        c.mutate({op: "settings", autoConnect: data.enabled});
        var bridge = createTemporaryObject(deliveryBridgeComponent, testCase);
        c.bridge = bridge;
        c.startupConnectionChecked = false;
        c.refresh();
        wait(0);
        compare(bridge.calls.join(","), data.enabled ? "getConnectionStatus,subscribe" : "");
        c.refresh();
        wait(0);
        compare(bridge.calls.join(","), data.enabled ? "getConnectionStatus,subscribe" : "");
        c.disconnect();
        c.mutate({op: "settings", autoConnect: true});
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
        var text = findChild(body, "body-text-0");
        text.select(0, 6);
        app.controller.draft(id, "Unfinished reply");
        app.controller.refresh();
        tryVerify(function () { return !app.controller.loading; });
        compare(findChild(app, "post-body-" + id), body);
        compare(text.selectedText, "Select");
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
        // The simplified profile fits at 540px; exercise overflow at a genuinely
        // constrained height instead of requiring unnecessary scrolling.
        app.height = 360;
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
        var discussions = findChild(app, "discussionsTab");
        var profile = findChild(app, "profileButton");
        var profileDialog = findChild(app, "identityDialog");
        mouseClick(profile, profile.width / 2, profile.height / 2);
        tryCompare(profileDialog, "opened", true);
        profileDialog.close();
        tryCompare(profileDialog, "visible", false);
        var general = findChild(app, "board-general");
        mouseClick(general, general.width / 2, general.height / 2);
        compare(app.board, "general");
        var sort = findChild(app, "sortFilter");
        sort.forceActiveFocus();
        keyClick(Qt.Key_Down);
        compare(app.sorting, "newest");
        mouseClick(discussions, discussions.width / 2, discussions.height / 2);
        compare(app.board, "all");
        var search = findChild(app, "headerSearch");
        search.forceActiveFocus();
        keyClick(Qt.Key_Z);
        compare(app.searchText, "z");
        mouseClick(profile, profile.width / 2, profile.height / 2);
        tryCompare(profileDialog, "opened", true);
        profileDialog.close();
        tryCompare(profileDialog, "visible", false);
        app.width = 400;
        tryCompare(app, "narrow", true);
        var board = findChild(app, "boardFilter");
        verify(waitForRendering(board));
        mouseClick(profile, profile.width / 2, profile.height / 2);
        tryCompare(profileDialog, "opened", true);
        profileDialog.close();
        tryCompare(profileDialog, "visible", false);
        board.forceActiveFocus();
        keyClick(Qt.Key_Down);
        compare(app.board, "general");
        tryCompare(profileDialog, "visible", false);
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
    function test_composeAttachmentPreviewAndRemoval() {
        var file;
        app.controller.call({op: "attachmentImport", file: Qt.resolvedUrl("../../forum/assets/icon.png").toString()}, function(r) { file = r.attachment; });
        app.compose();
        app.newAttachments = [file];
        var content = findChild(app, "composeDialog").contentItem;
        tryVerify(function() {
            var preview = findChild(content, "draft-attachment-" + file.id);
            return preview && preview.visible && preview.preview && preview.preview.pixels.length > 0;
        });
        var remove = findChild(content, "remove-draft-attachment-" + file.id);
        tryCompare(findChild(app, "composeDialog"), "opened", true);
        content.contentItem.contentY = Math.max(0, content.contentHeight - content.height);
        verify(waitForRendering(remove));
        mouseClick(remove, remove.width / 2, remove.height / 2);
        compare(app.newAttachments.length, 0);
    }
    function test_feedAttachmentPreviewAndTextAlignment() {
        var c = app.controller, plain = "", media = "", files = [];
        for (var i = 0; i < 3; i++)
            c.call({op: "attachmentImport", file: Qt.resolvedUrl("../../forum/assets/icon.png").toString()}, function(r) { files.push(r.attachment.id); });
        c.savePost("", "general", "Feed preview plain", "No media", function(r) { plain = r.id; });
        c.savePost("", "general", "Feed preview images", "Three images", function(r) { media = r.id; }, files);
        app.searchText = "Feed preview";
        tryVerify(function() { return !c.loading && app.visibleThreads.length === 2; });
        var preview, plainPreview, plainText, mediaText;
        tryVerify(function() {
            preview = findChild(app, "feed-preview-" + media);
            plainPreview = findChild(app, "feed-preview-" + plain);
            plainText = findChild(app, "feed-text-" + plain);
            mediaText = findChild(app, "feed-text-" + media);
            return preview && preview.item && preview.item.preview && plainPreview && plainText && mediaText;
        });
        compare(preview.item.count, 3);
        verify(findChild(preview.item, "attachment-count").visible);
        verify(!plainPreview.active && !plainPreview.visible);
        verify(Math.abs(plainText.mapToItem(app, 0, 0).x - preview.mapToItem(app, 0, 0).x) < 2);
        verify(mediaText.mapToItem(app, 0, 0).x > preview.mapToItem(app, preview.width, 0).x);
        app.width = 560;
        tryCompare(preview, "width", 80);
        verify(mediaText.mapToItem(app, mediaText.width, 0).x <= app.width);
        verify(waitForRendering(preview));
        mouseClick(preview, preview.width / 2, preview.height / 2);
        compare(app.selected, media);
    }
    function test_postImageHierarchy() {
        function imageFile() {
            var file;
            app.controller.call({op: "attachmentImport", file: Qt.resolvedUrl("../../forum/assets/icon.png").toString()}, function(r) { file = r.attachment; });
            return file.id;
        }
        function create(files) {
            var id;
            app.controller.savePost("", "general", "Image hierarchy", "A readable message beside or below its images.", function(r) { id = r.id; }, files);
            app.openThread(id);
            tryVerify(function() { return findChild(app, "post-text-" + id) !== null; });
            return id;
        }
        var id = create([imageFile()]);
        var card = findChild(app, "post-card-" + id);
        var images = findChild(app, "post-images-" + id);
        var text = findChild(app, "post-text-" + id);
        tryCompare(card, "sideImage", true);
        tryVerify(function() { return text.mapToItem(card, 0, 0).x >= images.mapToItem(card, images.width, 0).x; });
        verify(Math.abs(text.mapToItem(card, 0, 0).y - images.mapToItem(card, 0, 0).y) < 2);
        app.width = 560;
        tryCompare(card, "sideImage", false);
        tryVerify(function() { return text.mapToItem(card, 0, 0).y >= images.mapToItem(card, 0, images.height).y; });
        app.width = 1100;
        id = create([imageFile(), imageFile()]);
        card = findChild(app, "post-card-" + id);
        images = findChild(app, "post-images-" + id);
        text = findChild(app, "post-text-" + id);
        compare(card.sideImage, false);
        tryVerify(function() { return text.mapToItem(card, 0, 0).y >= images.mapToItem(card, 0, images.height).y; });
        verify(text.width > 700);
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
        var badge = findChild(app, "post-status-" + id);
        verify(badge !== null);
        compare(badge.symbol, "device");
        verify(badge.description.indexOf("not published") >= 0);
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
    function test_postAvatarsFollowSigningIdentity() {
        var firstIdentity = app.controller.state.active;
        app.controller.mutate({op: "settings", mode: "alias", rotate: false});
        var rootId = "", replyId = "", otherId = "", anonymousId = "";
        app.controller.savePost("", "general", "Profile photos in discussions", "A post written before choosing a photo.", function(r) { rootId = r.id; });
        app.controller.savePost(rootId, "general", "", "A reply from the same identity.", function(r) { replyId = r.id; });
        app.openThread(rootId);
        var rootAvatar, replyAvatar;
        tryVerify(function() {
            rootAvatar = findChild(app, "post-avatar-" + rootId);
            replyAvatar = findChild(app, "post-avatar-" + replyId);
            return rootAvatar !== null && replyAvatar !== null;
        });
        app.controller.mutate({op: "avatar", file: Qt.resolvedUrl("../../forum/assets/icon.png").toString()});
        tryVerify(function() { return !!rootAvatar.avatar && !!replyAvatar.avatar; });
        compare(rootAvatar.avatar.pixels.length, 4096);
        compare(JSON.stringify(rootAvatar.avatar), JSON.stringify(replyAvatar.avatar));
        app.beginReply();
        var composerAvatar = findChild(app, "replyIdentityAvatar");
        compare(JSON.stringify(composerAvatar.avatar), JSON.stringify(rootAvatar.avatar));

        var alias = app.controller.activeAlias();
        app.controller.mutate({op: "identity", alias: alias});
        app.controller.savePost(rootId, "general", "", "Same name, another identity.", function(r) { otherId = r.id; });
        tryVerify(function() { return !!findChild(app, "post-avatar-" + otherId); });
        verify(!findChild(app, "post-avatar-" + otherId).avatar);
        verify(!composerAvatar.avatar);
        rootAvatar = findChild(app, "post-avatar-" + rootId);
        verify(!!rootAvatar.avatar); // Historical posts keep the first identity's photo.

        app.controller.mutate({op: "settings", active: firstIdentity, mode: "anonymous"});
        verify(!composerAvatar.avatar);
        app.controller.savePost(rootId, "general", "", "An anonymous reply.", function(r) { anonymousId = r.id; });
        tryVerify(function() { return !!findChild(app, "post-avatar-" + anonymousId); });
        verify(!findChild(app, "post-avatar-" + anonymousId).avatar);
        compare(findChild(app, "post-avatar-" + anonymousId).initial, "·");
        app.controller.mutate({op: "settings", mode: "uid"});
        verify(!!composerAvatar.avatar);
        app.controller.mutate({op: "avatar", remove: true});
        tryVerify(function() { return !findChild(app, "post-avatar-" + rootId).avatar; });
        verify(!composerAvatar.avatar);
        app.controller.mutate({op: "settings", mode: "alias"});
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
    }
    function test_quoteHoverAndRootNavigationPreserveDraft() {
        var origin = "", discussion = "";
        app.controller.savePost("", "general", "The original discussion", "The original post has more context than the excerpt.", function(r) { origin = r.id; });
        app.controller.savePost("", "general", "A quoted discussion", ">>" + origin.substring(0, 8) + "\n> Short excerpt\n\nMy response", function(r) { discussion = r.id; });
        app.openThread(discussion);
        tryVerify(function() { return !!findChild(app, "post-body-" + discussion); });
        app.beginReply();
        findChild(app, "replyInput").text = "Keep my unfinished response";
        app.minimizeReply();
        tryCompare(findChild(app, "replyArea"), "progress", 0);
        var link = findChild(findChild(app, "post-body-" + discussion), "quote-reference-0");
        mouseMove(link, link.width / 2, link.height / 2);
        tryVerify(function() { return link.targetPost !== null; });
        var preview = findChild(link, "quotePreview");
        tryCompare(preview, "opened", true);
        compare(findChild(preview.contentItem, "quotePreviewBody").text, "The original post has more context than the excerpt.");
        compare(app.selected, discussion); // Hover never navigates.
        app.width = 400;
        tryVerify(function() { return preview.width <= app.width - 32; });
        mouseClick(link, link.width / 2, link.height / 2);
        tryCompare(app, "selected", origin);
        tryCompare(app, "highlightedPost", origin);
        compare(app.replyDraftCache[discussion], "Keep my unfinished response");
        tryVerify(function() { return findChild(app, "postsView").atYBeginning; });
    }
    function test_quoteNavigatesToReplyOutsideLoadedPage() {
        var rootId = "", target = "", source = "";
        app.controller.call({op: "post", board: "general", title: "Long reference discussion", body: "Opening"}, function(r) { rootId = r.id; });
        for (var n = 0; n < 55; ++n)
            app.controller.call({op: "post", board: "general", thread: rootId, body: "Earlier reply " + n});
        wait(2); // Keep the target after all timestamp/hash ties in the first page.
        app.controller.call({op: "post", board: "general", thread: rootId, body: "Referenced reply"}, function(r) { target = r.id; });
        app.controller.savePost("", "general", "Reference from another thread", ">>" + target.substring(0, 8) + "\n> Referenced reply\n\nA new thought.", function(r) { source = r.id; });
        app.openThread(source);
        tryVerify(function() { return !!findChild(app, "post-body-" + source); });
        var link = findChild(findChild(app, "post-body-" + source), "quote-reference-0");
        link.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        tryCompare(app, "highlightedPost", target);
        compare(app.selected, rootId);
        verify(app.replyHistory.length > 0);
        verify(app.findPost(target) !== null);
        var card = findChild(app, "post-card-" + target);
        var list = findChild(app, "postsView");
        verify(card !== null);
        tryVerify(function() { var y = card.mapToItem(list, 0, 0).y; return y >= -1 && y < list.height; });
    }
    function test_missingQuoteDoesNotNavigate() {
        var id = "";
        app.controller.savePost("", "general", "Missing reference", ">>ffffffff\n> Unavailable original", function(r) { id = r.id; });
        app.openThread(id);
        tryVerify(function() { return !!findChild(app, "post-body-" + id); });
        var link = findChild(findChild(app, "post-body-" + id), "quote-reference-0");
        mouseClick(link, link.width / 2, link.height / 2);
        tryVerify(function() { return link.issue.indexOf("not available") >= 0; });
        compare(app.selected, id);
        compare(app.pendingQuoteJump, "");
        compare(app.controller.error, "");
    }
    function test_publishedQuoteSeparatesExcerptFromReply() {
        var id = "", replyId = "";
        app.controller.savePost("", "general", "What are you building this week?", "I am working on a small local-first reading list. The hardest part is keeping sync understandable.", function(r) { id = r.id; });
        app.openThread(id);
        tryVerify(function() { return app.current !== null && !app.controller.loading; });
        var button = findChild(app, "beginReplyButton");
        mouseClick(button, button.width / 2, button.height / 2);
        var input = findChild(app, "replyInput");
        input.text += "Same here. I would start with a clear offline state and let people see what is waiting to sync.";
        var raw = input.text;
        app.controller.savePost(id, "general", "", raw, function(r) { replyId = r.id; });
        app.replyExpanded = false;
        var body;
        tryVerify(function() { body = findChild(app, "post-body-" + replyId); return body !== null; });
        compare(body.text, raw);
        compare(findChild(body, "quote-reference-0").text, ">>" + id.substring(0, 8));
        compare(findChild(body, "body-text-0").text, app.current.body);
        compare(findChild(body, "body-text-1").text, "Same here. I would start with a clear offline state and let people see what is waiting to sync.");
        app.width = 400;
        var quote = findChild(body, "body-segment-0");
        var reply = findChild(body, "body-segment-1");
        tryVerify(function() { return quote.width <= 350 && reply.y >= quote.y + quote.height + 16; });
        verify(quote.mapToItem(app, quote.width, 0).x < app.width);
        compare(app.findPost(replyId).body, raw);
    }
    function test_threadReadingColumnAndPostReply() {
        var id = "";
        app.controller.savePost("", "general", "A readable discussion", "Opening paragraph.\\n\\nA second thought.", function (r) { id = r.id; });
        app.width = 2200; app.height = 1000;
        app.openThread(id);
        tryVerify(function () { return !app.controller.loading && app.current !== null; });
        var input = findChild(app, "replyInput");
        var composer = findChild(app, "replyComposer");
        compare(findChild(app, "replyDock"), null);
        var prompt = findChild(app, "beginReplyButton");
        var title = findChild(app, "threadTitle");
        var body = findChild(app, "post-body-" + id);
        var card = findChild(app, "post-card-" + id);
        var posts = findChild(app, "postsView");
        verify(waitForRendering(prompt));
        verify(!composer.visible);
        verify(prompt.visible && prompt.width <= 100);
        verify(Math.abs(prompt.mapToItem(card, prompt.width, 0).x - (card.width - app.rowInset - card.contentPadding)) < 2);
        compare(findChild(app, "replyArea").visible, false);
        verify(Math.abs(title.mapToItem(app, 0, 0).x + card.contentPadding - body.mapToItem(app, 0, 0).x) < 2);
        tryVerify(function () { return title.mapToItem(posts, 0, 0).y >= -1; });
        compare(findChild(app, "quote-" + id), null);
        mouseClick(prompt, prompt.width / 2, prompt.height / 2);
        tryCompare(input, "activeFocus", true);
        var quoteText = ">>" + id.substring(0, 8) + "\n> " + app.current.body.split("\n").slice(0, 3).join("\n> ") + "\n\n";
        compare(input.text, quoteText);
        tryCompare(findChild(app, "replyArea"), "progress", 1);
        verify(composer.visible);
        verify(waitForRendering(composer));
        verify(composer.width <= 880);
        tryVerify(function () { return Math.abs(composer.mapToItem(app, composer.width / 2, 0).x - app.width / 2) < 2; });
        input.text = "A visible draft";
        tryCompare(app, "replyDraftStatus", "Draft saved");
        for (var width of [400, 640, 1440]) {
            app.width = width; app.height = width === 400 ? 540 : 900;
            var submit = findChild(app, "submitReplyButton");
            tryVerify(function () {
                var edge = submit.mapToItem(app, submit.width, submit.height);
                return edge.x <= app.width && edge.y <= app.height
                    && posts.mapToItem(app, 0, posts.height).y <= composer.mapToItem(app, 0, 0).y;
            });
            verify(submit.enabled);
            tryVerify(function () { return title.mapToItem(posts, 0, 0).y >= -1; });
        }
        var minimize = findChild(app, "minimizeReplyButton");
        mouseClick(minimize, minimize.width / 2, minimize.height / 2);
        tryCompare(app, "replyExpanded", false);
        compare(prompt.text, "Reply");
        tryCompare(prompt, "activeFocus", true);
        keyClick(Qt.Key_Space);
        tryCompare(input, "activeFocus", true);
        compare(input.text, "A visible draft\n\n" + quoteText);
        app.leaveThread();
        app.openThread(id);
        compare(input.text, "A visible draft\n\n" + quoteText);
        tryCompare(input, "visible", false);
        tryVerify(function () { return findChild(app, "beginReplyButton") !== null; });
    }
    function test_replyEditorAttachmentsIdentityAndSubmit() {
        var id = "", file = null;
        app.controller.savePost("", "general", "Reply workflow", "A discussion opener", function (r) { id = r.id; });
        app.controller.call({op: "attachmentImport", file: Qt.resolvedUrl("../../forum/assets/icon.png").toString()}, function (r) { file = r.attachment; });
        app.openThread(id);
        tryVerify(function () { return !app.controller.loading && app.current !== null; });
        app.beginReply();
        var input = findChild(app, "replyInput");
        input.text = "A reply with an attachment";
        app.replyAttachments = [file];
        app.saveReplyDraft();
        app.minimizeReply();
        app.beginReply();
        compare(app.replyAttachments[0].id, file.id);
        app.width = 400; app.height = 540;
        tryCompare(findChild(app, "replyArea"), "progress", 1);
        var action = findChild(app, "submitReplyButton");
        tryVerify(function () {
            var edge = action.mapToItem(app, action.width, action.height);
            return edge.x <= app.width && edge.y <= app.height;
        });
        var remove = null;
        tryVerify(function () { remove = findChild(app, "removeReplyAttachment-0"); return remove !== null; });
        verify(waitForRendering(findChild(app, "replyAttachmentTray")));
        remove = findChild(app, "removeReplyAttachment-0");
        verify(remove !== null, "Attachment removal control exists after layout");
        mouseClick(remove, remove.width / 2, remove.height / 2);
        compare(app.replyAttachments.length, 0);
        app.replyAttachments = [file];
        app.saveReplyDraft();
        var identity = findChild(app, "replyIdentityButton");
        verify(identity !== null, "Identity selector exists");
        verify(waitForRendering(identity));
        mouseClick(identity, identity.width / 2, identity.height / 2);
        var dialog = findChild(app, "identityDialog");
        tryCompare(dialog, "opened", true);
        dialog.close();
        var submit = findChild(app, "submitReplyButton");
        verify(submit !== null, "Post reply exists");
        tryCompare(dialog, "visible", false);
        verify(waitForRendering(submit));
        tryCompare(submit, "enabled", true);
        mouseClick(submit, submit.width / 2, submit.height / 2);
        tryCompare(app, "replyExpanded", false);
        tryVerify(function () { return !app.controller.loading && app.replies(id).length === 1; });
        var posted = app.replies(id)[0];
        compare(posted.body, "A reply with an attachment");
        compare(posted.attachments[0].id, file.id);
        compare(posted.status, "local");
        compare(input.text, "");
        compare(app.replyAttachments.length, 0);
        compare(findChild(app, "beginReplyButton").text, "Reply");
        app.controller.refresh();
        tryVerify(function () { return !app.controller.loading; });
        verify(!app.controller.state.drafts[id]);
    }
    Component {
        id: failingDraftBackend
        QtObject {
            property var actual
            function dispatch(command) {
                if (JSON.parse(command).op === "draft") return JSON.stringify({ok: false, error: "Draft write failed"});
                return actual.dispatch(command);
            }
        }
    }
    function test_replyDraftFailureDoesNotClaimSaved() {
        var id = "";
        app.controller.savePost("", "general", "Draft failure", "Opening", function (r) { id = r.id; });
        app.openThread(id);
        tryVerify(function () { return !app.controller.loading; });
        app.beginReply();
        var input = findChild(app, "replyInput");
        var backend = app.controller.backend;
        app.controller.backend = createTemporaryObject(failingDraftBackend, testCase, {actual: backend});
        input.text = "Keep my draft if persistence fails";
        app.saveReplyDraft();
        compare(app.replyDraftStatus, "Draft not saved");
        compare(input.text, "Keep my draft if persistence fails");
        app.controller.backend = backend;
        app.controller.error = "";
        app.saveReplyDraft();
        compare(app.replyDraftStatus, "Draft saved");
    }
    function test_ctrlEnterSubmitsOnlyValidFocusedReply() {
        var id = "";
        app.controller.savePost("", "general", "Keyboard reply", "Opening", function (r) { id = r.id; });
        app.openThread(id);
        tryVerify(function () { return !app.controller.loading && app.current !== null; });
        app.beginReply();
        var input = findChild(app, "replyInput");
        keyClick(Qt.Key_Return, Qt.ControlModifier);
        compare(input.text, "");
        compare(app.replies(id).length, 0);

        input.text = "x".repeat(12001);
        keyClick(Qt.Key_Return, Qt.ControlModifier);
        compare(input.text.length, 12001);
        compare(app.replies(id).length, 0);

        input.text = "A keyboard reply";
        app.controller.posting = true;
        keyClick(Qt.Key_Return, Qt.ControlModifier);
        compare(app.replies(id).length, 0);
        app.controller.posting = false;
        input.cursorPosition = input.length;
        keyClick(Qt.Key_Return);
        compare(input.text, "A keyboard reply\n");
        keyClick(Qt.Key_Return, Qt.ControlModifier);
        tryCompare(app, "replyExpanded", false);
        tryVerify(function () { return !app.controller.loading && app.replies(id).length === 1; });
        compare(app.replies(id)[0].body, "A keyboard reply");
        compare(input.text, "");

        app.beginReply();
        input.text = "Numpad reply";
        findChild(app, "postsView").forceActiveFocus();
        keyClick(Qt.Key_Enter, Qt.ControlModifier | Qt.KeypadModifier);
        compare(app.replies(id).length, 1);
        compare(input.text, "Numpad reply");
        input.forceActiveFocus();
        keyClick(Qt.Key_Enter, Qt.ControlModifier | Qt.KeypadModifier);
        tryCompare(app, "replyExpanded", false);
        tryVerify(function () { return !app.controller.loading && app.replies(id).length === 2; });
        compare(input.text, "");
    }
    function test_footerFillsShortPage() {
        var id = "";
        var title = "Footer short-page fixture";
        app.controller.savePost("", "general", title, "A short post.", function (r) { id = r.id; });
        app.openThread(id);
        var posts = findChild(app, "postsView");
        tryVerify(function () { return !app.controller.loading && posts.footerItem !== null; });
        for (var size of [[1440, 900], [400, 650], [1200, 800]]) {
            app.width = size[0]; app.height = size[1];
            posts.positionViewAtBeginning();
            tryVerify(function () {
                var footer = posts.footerItem;
                return Math.abs(footer.mapToItem(posts, 0, footer.height).y - posts.height) < 2;
            });
        }
        app.searchText = title;
        app.leaveThread();
        var feed = findChild(app, "threadListView");
        tryVerify(function () { return !app.controller.loading && app.visibleThreads.length === 1 && feed.footerItem !== null; });
        feed.positionViewAtBeginning();
        tryVerify(function () {
            var footer = feed.footerItem;
            return Math.abs(footer.mapToItem(feed, 0, footer.height).y - feed.height) < 2;
        });
    }
    function test_scrollFooterAndReplyToMessage() {
        var id = "", replyId = "";
        app.width = 640; app.height = 600;
        app.controller.savePost("", "general", "Scrollable discussion", Array(45).fill("A longer discussion paragraph.").join("\n\n"), function (r) { id = r.id; });
        app.controller.savePost(id, "general", "", "A response to discuss", function (r) { replyId = r.id; });
        app.openThread(id);
        var posts = findChild(app, "postsView");
        tryVerify(function () { return !app.controller.loading && app.discussionPosts.length === 2 && posts.footerItem !== null; });
        posts.positionViewAtBeginning();
        var footer = posts.footerItem;
        tryVerify(function () { return footer.mapToItem(posts, 0, 0).y >= posts.height; });
        posts.positionViewAtEnd();
        var logo = findChild(footer, "logosReference");
        tryVerify(function () {
            var point = logo.mapToItem(posts, 0, 0);
            return point.y >= 0 && point.y + logo.height <= posts.height + 1;
        });
        var action = null;
        tryVerify(function () { action = findChild(app, "reply-" + replyId); return action !== null; });
        verify(waitForRendering(posts));
        posts.positionViewAtEnd();
        tryVerify(function () { action = findChild(app, "reply-" + replyId); return action !== null; });
        var actionPoint = action.mapToItem(posts, action.width / 2, action.height / 2);
        mouseClick(posts, actionPoint.x, actionPoint.y);
        var input = findChild(app, "replyInput");
        tryCompare(input, "activeFocus", true);
        verify(input.text.indexOf(">>" + replyId.substring(0, 8)) >= 0);
        verify(input.text.indexOf("> A response to discuss") >= 0);
        input.text += "\nMy answer";
        app.minimizeReply();
        tryCompare(findChild(app, "replyArea"), "progress", 0);
        compare(input.text.indexOf("My answer") >= 0, true);
        app.leaveThread();
        var feed = findChild(app, "threadListView");
        tryVerify(function () { return feed.footerItem !== null; });
        compare(findChild(feed.footerItem, "logosReference") !== null, true);
    }
    function test_replyMotionCanReverseWithoutLosingDraft() {
        var id = "";
        app.controller.savePost("", "general", "Reply motion", "Opening", function (r) { id = r.id; });
        app.openThread(id);
        tryVerify(function () { return !app.controller.loading && app.current !== null; });
        var area = findChild(app, "replyArea");
        var composer = findChild(app, "replyComposer");
        compare(findChild(app, "replyDock"), null);
        var input = findChild(app, "replyInput");
        compare(area.progress, 0);
        var trigger = findChild(app, "beginReplyButton");
        verify(waitForRendering(trigger));
        mouseClick(trigger, trigger.width / 2, trigger.height / 2);
        compare(input.activeFocus, true);
        input.text = "Keep this draft through the transition";
        wait(70);
        verify(area.progress > 0 && area.progress < 1);
        verify(composer.enabled);
        var openingProgress = area.progress;
        app.minimizeReply();
        verify(!composer.enabled);
        wait(40);
        verify(area.progress < openingProgress);
        app.beginReply();
        tryCompare(area, "progress", 1);
        compare(input.activeFocus, true);
        compare(input.text, "Keep this draft through the transition");
        app.minimizeReply();
        tryCompare(area, "progress", 0);
        compare(composer.visible, false);
        compare(area.visible, false);
        tryCompare(findChild(app, "beginReplyButton"), "activeFocus", true);
        app.beginReply();
        wait(40);
        app.leaveThread();
        app.openThread(id);
        tryCompare(area, "progress", 0);
        compare(input.text, "Keep this draft through the transition");
        compare(composer.visible, false);
    }
    function test_replyCaretAtLineStart() {
        var id = "";
        app.controller.savePost("", "general", "Caret visibility", "Opening", function (r) { id = r.id; });
        app.openThread(id);
        tryVerify(function () { return !app.controller.loading && app.current !== null; });
        app.beginReply();
        var input = findChild(app, "replyInput");
        var viewport = findChild(app, "replyScroll");
        input.text = "First line\n\nThird line\nFourth line\nFifth line\nSixth line\nSeventh line";
        for (var theme of ["dark", "light"]) {
            app.controller.mutate({op: "settings", theme: theme});
            input.forceActiveFocus();
            input.cursorPosition = input.length;
            keyClick(Qt.Key_Home, Qt.ControlModifier);
            for (var position of [0, 11, 12]) {
                input.cursorPosition = position;
                verify(waitForRendering(viewport));
                var caret = findChild(app, "replyCaret");
                verify(caret !== null);
                tryCompare(caret, "visible", true);
                var point = caret.mapToItem(viewport, 0, caret.height / 2);
                verify(point.x >= 0 && point.x + 2 <= viewport.width);
                verify(point.y >= 0 && point.y < viewport.height);
                tryVerify(function () {
                    var rendered = caret.mapToItem(app, 0, caret.height / 2);
                    var pixels = grabImage(app);
                    return pixels.pixel(Math.round(rendered.x), Math.floor(rendered.y)).toString() === input.color.toString()
                        && pixels.pixel(Math.round(rendered.x) + 1, Math.floor(rendered.y)).toString() === input.color.toString();
                }, 1000, "Both caret pixels remain visible at the start of the line");
            }
        }
        app.minimizeReply();
        compare(findChild(app, "replyCaret").visible, false);
        app.beginReply();
        tryCompare(findChild(app, "replyCaret"), "visible", true);
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
        tryVerify(function () { return findChild(app, "beginReplyButton") !== null; });
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
        // Draft writes do not emit a snapshot refresh. Reopening must use the
        // current composer contents rather than the last server snapshot.
        app.compose();
        tryCompare(dialog, "opened", true);
        compare(findChild(app, "titleInput").text, "Immediate draft");
        compare(findChild(app, "bodyInput").text, "Close before debounce");
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
                if (method === "rlnState") {
                    done({success: true, value: {state: "Ready", registryId: "test-registry", rlnIdentifier: "test-scope"}});
                } else if (method === "get_membership_state") {
                    done({success: true, value: {state: "active"}});
                } else if (method === "createNode") {
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
    Component {
        id: readinessBridgeComponent
        QtObject {
            property var response: ({error: {kind: "ambiguous_selection"}})
            property var pending: null
            property bool deferred: false
            property int sends: 0
            property int checks: 0
            property var controller
            function onModuleEvent(module, name) {}
            function callModuleAsync(module, method, args, done, timeout) {
                if (method === "rlnState") {
                    done({success: true, value: {state: "Ready", registryId: "shared-registry", rlnIdentifier: "shared-scope"}});
                } else if (method === "get_membership_state") {
                    checks++;
                    compare(args.join(","), "shared-registry,shared-scope");
                    compare(timeout, 90000);
                    if (deferred) pending = done;
                    else done({success: true, value: JSON.stringify(response)});
                } else if (method === "send") {
                    sends++;
                    done({success: true, value: "gate-ack"});
                    controller.event("messageSent", ["gate-ack"]);
                } else done({success: true, value: method === "getConnectionStatus" ? "Connected" : true});
            }
        }
    }
    function test_membershipFailurePausesWithoutConsumingOutbox() {
        var c = app.controller;
        var b = createTemporaryObject(readinessBridgeComponent, testCase, {controller: c});
        c.bridge = b;
        c.connectNetwork();
        compare(c.publishingState, "blocked");
        verify(c.publishingDetail.indexOf("ambiguous_selection") >= 0);
        var id = "";
        c.savePost("", "general", "Readiness guard", "Retain exact envelope", function(r) { id = r.id; });
        for (var i = 0; i < 5; i++) c.pump();
        compare(b.sends, 0);
        compare(b.checks, 1);
        compare(app.findPost(id).status, "queued");
        compare(c.inFlight, "");
        b.response = {state: "active"};
        c.publishingCheckedAt = Date.now() - 31000;
        for (i = 0; i < 200 && app.findPost(id).status !== "sent"; i++) {
            c.pump();
            tryCompare(c, "inFlight", "");
        }
        compare(c.publishingState, "ready");
        compare(app.findPost(id).status, "sent");
        compare(app.findPost(id).body, "Retain exact envelope");
    }
    function test_membershipChecksRejectInactiveAndMalformedResults() {
        var c = app.controller;
        var b = createTemporaryObject(readinessBridgeComponent, testCase, {controller: c});
        c.bridge = b;
        c.connection = "online";
        var states = ["pending", "erased", "expired", "unknown", "failed"];
        for (var i = 0; i < states.length; i++) {
            b.response = {state: states[i]};
            c.checkPublishing();
            compare(c.publishingState, "blocked");
        }
        b.response = null;
        c.checkPublishing();
        compare(c.publishingState, "blocked");
        b.response = {state: "grace_period"};
        c.checkPublishing();
        compare(c.publishingState, "ready");
        compare(b.sends, 0);
    }
    function test_staleReadinessCannotSendOrReconnectOffline() {
        var c = app.controller;
        var b = createTemporaryObject(readinessBridgeComponent, testCase, {controller: c, response: {state: "active"}});
        c.bridge = b;
        c.connectNetwork();
        compare(c.publishingState, "ready");
        b.deferred = true;
        c.publishingCheckedAt = Date.now() - 61000;
        c.pump();
        verify(c.publishingCheckBusy);
        verify(!c.publishingReady);
        c.pump();
        compare(b.sends, 0);
        compare(b.checks, 2);
        c.disconnect();
        b.pending({success: true, value: {state: "active"}});
        compare(c.connection, "offline");
        verify(!c.publishingReady);
        verify(!c.publishingCheckBusy);
    }
    function test_readinessTimeoutIgnoresLateSuccess() {
        var c = app.controller;
        var b = createTemporaryObject(readinessBridgeComponent, testCase, {controller: c, deferred: true});
        c.bridge = b;
        c.connectNetwork();
        verify(c.publishingCheckBusy);
        c.publishingCheckStarted = Date.now() - 110001;
        c.pump();
        compare(c.publishingState, "blocked");
        verify(!c.publishingCheckBusy);
        b.pending({success: true, value: {state: "active"}});
        compare(c.publishingState, "blocked");
        compare(b.sends, 0);
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
    function test_deliveryStatusWaitsForMatchingAcknowledgement() {
        var c = app.controller, id = "";
        c.savePost("", "general", "Publication status", "Wait for a real acknowledgement", function (r) { id = r.id; });
        tryVerify(function () {
            var badge = findChild(app, "feed-status-" + id);
            return badge !== null && badge.visible && badge.symbol === "clock";
        });
        app.openThread(id);
        tryVerify(function () { return !c.loading && app.current !== null; });
        function statusIs(symbol) {
            var badge = findChild(app, "post-status-" + id);
            return badge !== null && badge.visible && badge.symbol === symbol;
        }
        tryVerify(function () { return statusIs("clock"); });
        c.inFlight = id;
        c.requestId = "expected-status-ack";
        c.started = Date.now();
        c.mutate({op: "delivery", id: id, status: "sending", request: c.requestId});
        tryVerify(function () { return statusIs("sending"); });
        c.event("messageSent", ["unrelated-ack"]);
        compare(app.findPost(id).status, "sending");
        verify(statusIs("sending"));
        c.event("messageSent", ["expected-status-ack"]);
        tryVerify(function () { return statusIs("check"); });
        compare(app.findPost(id).status, "sent");
        var badge = findChild(app, "post-status-" + id);
        compare(badge.description, "Delivered to network");
        app.leaveThread();
        tryVerify(function () {
            var feedBadge = findChild(app, "feed-status-" + id);
            return feedBadge !== null && feedBadge.symbol === "check";
        });
    }
    function test_deliveryWaitsForTransportRetryWindow() {
        var c = app.controller;
        function sending(request) {
            var id = "";
            c.savePost("", "general", "Transport window", "Keep the original envelope", function (r) { id = r.id; });
            c.inFlight = id;
            c.requestId = request;
            c.started = Date.now() - 65000;
            c.mutate({op: "delivery", id: id, status: "sending", request: request});
            return id;
        }
        var id = sending("slow-success");
        c.pump();
        compare(c.inFlight, id);
        compare(app.findPost(id).status, "sending");
        c.event("messageSent", ["slow-success"]);
        compare(app.findPost(id).status, "sent");

        id = sending("transport-failure");
        c.pump();
        c.event("messageError", ["transport-failure", "", "Unable to send within retry time window"]);
        compare(app.findPost(id).status, "failed");
        compare(app.findPost(id).error, "Unable to send within retry time window");
        compare(c.inFlight, "");

        id = sending("no-event");
        c.started = Date.now() - c.acknowledgementTimeoutMs - 1;
        c.pump();
        compare(app.findPost(id).status, "failed");
        verify(app.findPost(id).error.indexOf("acknowledgement timed out") >= 0);
        compare(c.inFlight, "");
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
    function test_failedPostHasScopedRetry() {
        var c = app.controller, id = "";
        c.savePost("", "general", "Retry action", "Keep this exact post", function(r) { id = r.id; });
        c.mutate({op: "delivery", id: id, status: "failed", error: "Transport timeout"});
        app.openThread(id);
        tryVerify(function() { var b = findChild(app, "retry-post-" + id); return b && b.visible; });
        var button = findChild(app, "retry-post-" + id);
        mouseClick(button, button.width / 2, button.height / 2);
        tryCompare(button, "visible", false);
        compare(app.findPost(id).status, "queued");
        compare(app.findPost(id).body, "Keep this exact post");
        compare(c.inFlight, ""); // Offline retry queues, never bypasses readiness.
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
        app.openThread(id);
        tryVerify(function () {
            var badge = findChild(app, "post-status-" + id);
            return badge !== null && badge.symbol === "warning" && badge.description.indexOf("peer refused") >= 0;
        });
    }
}
