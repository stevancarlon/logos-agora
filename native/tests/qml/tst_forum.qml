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
    function init() {
        app = createTemporaryObject(appComponent, testCase);
        verify(app !== null);
        tryCompare(app.controller, "ready", true);
    }
    function test_headerNavigation() {
        var saved = findChild(app, "savedTab"), discussions = findChild(app, "discussionsTab");
        verify(waitForRendering(saved));
        mouseClick(saved, saved.width / 2, saved.height / 2);
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
        var status = findChild(app, "networkStatus");
        mouseClick(status, status.width / 2, status.height / 2);
        tryCompare(findChild(app, "networkDialog"), "opened", true);
        findChild(app, "networkDialog").close();
        app.width = 400;
        tryCompare(app, "narrow", true);
        var board = findChild(app, "boardFilter");
        verify(waitForRendering(board));
        mouseClick(saved, saved.width / 2, saved.height / 2);
        compare(app.showingSaved, true);
        board.forceActiveFocus();
        keyClick(Qt.Key_Down);
        compare(app.board, "general");
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
        compare(app.visibleThreads.length, 0);
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
            signal moduleEventReceived(string moduleName, string eventName, var data)
            function onModuleEvent(module, event) {
            }
            function callModuleAsync(module, method, args, done, timeout) {
                if (method === "send") {
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
