pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs as NativeDialogs

Pane {
    id: root
    padding: 0
    FontLoader {
        id: appFont
        source: "fonts/AdwaitaSans-Regular.ttf"
    }
    FontLoader {
        source: "fonts/LiberationSerif-Regular.ttf"
    }
    font.family: "Adwaita Sans"
    font.pixelSize: 13
    property bool darkTheme: forum.state.theme !== "light"
    palette.window: theme.canvas
    palette.windowText: theme.text
    palette.base: theme.surface
    palette.alternateBase: theme.alternate
    palette.text: theme.text
    palette.button: theme.surface
    palette.buttonText: theme.text
    palette.highlight: theme.selection
    palette.highlightedText: theme.text
    palette.placeholderText: theme.muted
    palette.mid: theme.border
    palette.dark: theme.border
    palette.light: theme.border
    palette.accent: theme.accent
    background: Rectangle {
        color: theme.canvas
    }
    QtObject {
        id: theme
        readonly property color canvas: root.darkTheme ? "#0c0c0c" : "#ffffff"
        readonly property color sidebar: root.darkTheme ? "#101010" : "#f5f5f5"
        readonly property color surface: root.darkTheme ? "#181818" : "#fafafa"
        readonly property color alternate: root.darkTheme ? "#202020" : "#f0f0f0"
        readonly property color selection: root.darkTheme ? "#2a2a2a" : "#e5e5e5"
        readonly property color border: root.darkTheme ? "#333333" : "#d4d4d4"
        readonly property color text: root.darkTheme ? "#ededed" : "#171717"
        readonly property color muted: root.darkTheme ? "#a3a3a3" : "#666666"
        readonly property color accent: root.darkTheme ? "#eeeeee" : "#222222"
        readonly property color quote: root.darkTheme ? "#cccccc" : "#444444"
        readonly property color error: root.darkTheme ? "#f5f5f5" : "#171717"
        readonly property color errorSurface: root.darkTheme ? "#242424" : "#eeeeee"
    }
    implicitWidth: 1160
    implicitHeight: 760
    property alias controller: forum
    property string board: "all"
    property string selected: ""
    property string pendingReplyScroll: ""
    property string pendingQuoteJump: ""
    property string highlightedPost: ""
    property int quoteNavigationEpoch: 0
    Timer { id: quoteHighlightTimer; interval: 1800; onTriggered: root.highlightedPost = "" }
    property string searchText: ""
    property string sorting: "activity"
    property bool replyExpanded: false
    property var replyTrigger: null
    property string replyDraftStatus: ""
    property int replyDraftGeneration: 0
    readonly property bool hasReplyDraft: replyInput.text.trim().length > 0 || replyAttachments.length > 0
    readonly property string replyIdentity: forum.state.mode === "anonymous" ? "Anonymous" : forum.state.mode === "uid" ? "Unique ID" : forum.activeAlias()
    readonly property bool replyLocalOnly: (replyAttachments.length > 0 && !forum.state.storageEndpoint) || (!!current && current.status === "local")
    property var newAttachments: []
    property var newDraftCache: null
    property var replyAttachments: []
    property var replyAttachmentCache: ({})
    property string attachmentTarget: "new"
    property string downloadingAttachment: ""
    property var replyDraftCache: ({})
    property var boards: [
        {
            id: "general",
            label: "General",
            hint: "Anything worth discussing"
        },
        {
            id: "privacy",
            label: "Privacy",
            hint: "Tools, rights, and open questions"
        },
        {
            id: "building",
            label: "Building",
            hint: "Show your work. Ask for help."
        },
        {
            id: "circles",
            label: "Circles",
            hint: "Organise locally, learn together"
        },
        {
            id: "governance",
            label: "Governance",
            hint: "How we make decisions"
        }
    ]
    property var current: findPost(selected)
    property bool narrow: width < 1080
    readonly property real rowInset: narrow ? 12 : 16
    readonly property real contentGutter: Math.max(narrow ? 16 : 28, (width - 1600) / 2)
    // Qt handles display scaling; resizing the window should not shrink text.
    readonly property real uiScale: 1
    property string newBoard: board === "all" ? "general" : board
    property string feedCursor: ""
    property string replyCursor: ""
    property var feedHistory: []
    property var replyHistory: []
    onBoardChanged: resetFeedPages()
    onSearchTextChanged: resetFeedPages()
    onSortingChanged: resetFeedPages()
    onSelectedChanged: {
        pendingReplyScroll = ""; replyCursor = ""; replyHistory = [];
        pendingQuoteJump = ""; highlightedPost = ""; ++quoteNavigationEpoch;
    }
    function resetFeedPages() {
        feedCursor = ""; feedHistory = []; feedScrollY = 0; restoreFeedScroll = false;
        threadListView.positionViewAtBeginning();
    }
    function nextPage() {
        if (!forum.state.hasMore || forum.loading) return;
        pendingQuoteJump = ""; ++quoteNavigationEpoch;
        if (selected) { replyHistory = replyHistory.concat([replyCursor]); replyCursor = forum.state.nextCursor; }
        else { feedHistory = feedHistory.concat([feedCursor]); feedCursor = forum.state.nextCursor; }
        threadListView.positionViewAtBeginning(); postsView.positionViewAtBeginning();
    }
    function previousPage() {
        var history = (selected ? replyHistory : feedHistory).slice();
        if (!history.length || forum.loading) return;
        pendingQuoteJump = ""; ++quoteNavigationEpoch;
        var cursor = history.pop();
        if (selected) { replyHistory = history; replyCursor = cursor; }
        else { feedHistory = history; feedCursor = cursor; }
        threadListView.positionViewAtBeginning(); postsView.positionViewAtBeginning();
    }
    // Keep view data separate from settings/draft snapshots. Unchanged posts
    // must not recreate delegates, reset selection, or interrupt inline video.
    property var feedPosts: []
    property var discussionPosts: []
    property real feedScrollY: 0
    property bool restoreFeedScroll: false
    property string feedFingerprint: ""
    property string discussionFingerprint: ""
    property var visibleThreads: feedPosts.filter(function (p) { return !p.thread; })
    function syncViewData() {
        var data = forum.state.posts;
        var fingerprint = JSON.stringify(data);
        if (forum.state.view === "feed" && !selected) {
            if (feedFingerprint !== fingerprint) {
                var y = restoreFeedScroll ? feedScrollY : threadListView.contentY;
                feedFingerprint = fingerprint;
                feedPosts = data;
                Qt.callLater(function () {
                    if (root && !root.selected) threadListView.contentY = Math.max(0, Math.min(y, Math.max(0, threadListView.contentHeight - threadListView.height)));
                });
            }
            if (restoreFeedScroll) {
                restoreFeedScroll = false;
                Qt.callLater(function () { if (root) threadListView.contentY = root.feedScrollY; });
            }
        } else if (forum.state.view === "thread" && forum.state.threadId === selected && discussionFingerprint !== fingerprint) {
            var firstSnapshot = discussionFingerprint === "";
            var postY = postsView.contentY;
            discussionFingerprint = fingerprint;
            discussionPosts = data;
            Qt.callLater(function () {
                if (root && root.pendingQuoteJump) root.finishQuoteJump();
                else if (root && !root.pendingReplyScroll) {
                    if (firstSnapshot) postsView.positionViewAtBeginning();
                    else {
                        var start = postsView.originY;
                        postsView.contentY = Math.max(start, Math.min(postY, Math.max(start, postsView.originY + postsView.contentHeight - postsView.height)));
                    }
                }
            });
        }
    }
    ForumController {
        id: forum
        onStateChanged: root.syncViewData()
        onLoadingChanged: {
            if (!loading) loadingIndicator.visible = false;
            if (!loading && root.pendingQuoteJump) Qt.callLater(root.finishQuoteJump);
            if (!loading && root.pendingReplyScroll && root.findPost(root.pendingReplyScroll)) {
                root.pendingReplyScroll = "";
                Qt.callLater(function () { postsView.positionViewAtEnd(); });
            }
        }
        browseQuery: ({view: root.selected ? "thread" : "feed", thread: root.selected,
            board: root.selected ? "all" : root.board, search: root.selected ? "" : root.searchText,
            sort: root.selected ? "activity" : root.sorting,
            cursor: root.selected ? root.replyCursor : root.feedCursor, limit: root.selected ? 50 : 30})
    }
    function findPost(pid) {
        for (var i = 0; i < forum.state.posts.length; i++)
            if (forum.state.posts[i].id === pid)
                return forum.state.posts[i];
        return null;
    }
    function replies(pid) {
        return forum.state.posts.filter(function (p) {
            return p.thread === pid && (!findPost(pid) || p.board === findPost(pid).board);
        });
    }
    function shortId(pid) {
        return pid ? pid.substring(0, 8) : "";
    }
    function authorName(p) {
        return p.mode === "anonymous" ? "Anonymous" : p.mode === "uid" ? shortId(p.author) : p.author;
    }
    function displayAuthor(p) {
        return p.mode === "anonymous" ? "Anonymous" : p.mode === "uid" ? shortId(p.author) : p.author + " · " + shortId(p.authorId);
    }
    function boardName(id) {
        for (var i = 0; i < boards.length; i++)
            if (boards[i].id === id)
                return boards[i].label;
        return "All discussions";
    }
    function age(ms) {
        var mins = Math.max(0, Math.floor((Date.now() - ms) / 60000));
        return mins < 1 ? "now" : mins < 60 ? mins + "m" : mins < 1440 ? Math.floor(mins / 60) + "h" : Math.floor(mins / 1440) + "d";
    }
    function activityAge(ms) {
        var value = age(ms);
        return value === "now" ? "now" : value + " ago";
    }
    function statusLabel(status) {
        if (status === "local")
            return "Local only · attachments are not published";
        return status === "sent" ? "Sent to network" : status === "received" ? "Received" : status === "sending" ? "Sending…" : status === "failed" ? "Retry pending" : "Saved locally · queued";
    }
    function threadList() {
        return forum.state.posts.filter(function (p) { return !p.thread; });
    }
    function saveReplyDraft() {
        replyDraftTimer.stop();
        if (selected) {
            var threadId = selected, body = replyInput.text, files = JSON.stringify(replyAttachments);
            var generation = ++replyDraftGeneration, remaining = 2;
            replyDraftCache[threadId] = body;
            replyAttachmentCache[threadId] = replyAttachments;
            replyDraftStatus = "Saving draft…";
            function stillCurrent() { return root.selected === threadId && root.replyDraftGeneration === generation; }
            function saved() {
                remaining--;
                if (remaining === 0 && stillCurrent()) root.replyDraftStatus = root.hasReplyDraft ? "Draft saved" : "";
            }
            function failed(message) {
                remaining = -1;
                if (stillCurrent()) root.replyDraftStatus = "Draft not saved";
                forum.error = message;
            }
            forum.draft("files/" + threadId, files, saved, failed);
            forum.draft(threadId, body, saved, failed);
        }
    }
    function leaveThread() {
        saveReplyDraft();
        if (selected) restoreFeedScroll = true;
        selected = "";
        discussionPosts = [];
        discussionFingerprint = "";
        replyExpanded = false;
    }
    function goBoard(id) {
        leaveThread();
        resetFeedPages();
        board = id;
    }
    function openThread(pid) {
        saveReplyDraft();
        if (!selected) feedScrollY = threadListView.contentY;
        discussionFingerprint = "";
        discussionPosts = [];
        selected = pid;
        replyInput.text = Object.prototype.hasOwnProperty.call(replyDraftCache, pid) ? replyDraftCache[pid] : forum.state.drafts[pid] || "";
        replyDraftTimer.stop();
        try {
            replyAttachments = replyAttachmentCache[pid] || JSON.parse(forum.state.drafts["files/" + pid] || "[]");
        } catch (e) {
            replyAttachments = [];
        }
        replyExpanded = false;
        replyDraftStatus = "";
        // Reconfirm restored drafts, including any cached write that failed earlier.
        if (hasReplyDraft) saveReplyDraft();
        postsView.positionViewAtBeginning();
    }
    function showPostedReply(threadId, replyId) {
        forum.call({op: "replyPage", id: replyId}, function (page) {
            if (root.selected !== threadId) return;
            root.pendingReplyScroll = replyId;
            if (root.replyCursor !== page.pageCursor) {
                root.replyHistory = root.replyHistory.concat([root.replyCursor]);
                root.replyCursor = page.pageCursor;
            } else forum.refresh();
        });
    }
    function beginReply() {
        replyExpanded = true;
        replyInput.forceActiveFocus();
    }
    function finishQuoteJump() {
        if (!pendingQuoteJump || forum.loading) return;
        var index = discussionPosts.findIndex(function(p) { return p.id === root.pendingQuoteJump; });
        if (index < 0) return;
        postsView.forceLayout();
        if (index === 0) postsView.positionViewAtBeginning();
        else postsView.positionViewAtIndex(index, ListView.Beginning);
        highlightedPost = pendingQuoteJump;
        pendingQuoteJump = "";
        quoteHighlightTimer.restart();
        postsView.forceActiveFocus();
    }
    function navigateToQuotedPost(post) {
        var threadId = post.thread || post.id;
        if (selected !== threadId) openThread(threadId);
        var epoch = ++quoteNavigationEpoch;
        pendingReplyScroll = "";
        pendingQuoteJump = post.id;
        if (discussionPosts.some(function(p) { return p.id === post.id; })) {
            Qt.callLater(root.finishQuoteJump);
            return;
        }
        if (!post.thread) { forum.refresh(); return; }
        forum.call({op: "replyPage", id: post.id}, function(page) {
            if (root.quoteNavigationEpoch !== epoch || root.selected !== threadId) return;
            root.replyHistory = page.pageCursor ? [""] : [];
            if (root.replyCursor !== page.pageCursor) root.replyCursor = page.pageCursor;
            else forum.refresh();
        }, function(message) {
            if (root.quoteNavigationEpoch !== epoch) return;
            root.pendingQuoteJump = "";
            forum.error = message;
        });
    }
    function minimizeReply() {
        saveReplyDraft();
        replyExpanded = false;
        if (replyTrigger && replyTrigger.visible)
            replyTrigger.forceActiveFocus(Qt.TabFocusReason);
        else
            postsView.forceActiveFocus(Qt.TabFocusReason);
    }
    function quote(p) {
        replyInput.text += (replyInput.text ? "\n\n" : "") + ">>" + shortId(p.id) + "\n> " + p.body.split("\n").slice(0, 3).join("\n> ") + "\n\n";
        beginReply();
    }
    function compose() {
        forum.error = "";
        var d = {};
        try {
            d = root.newDraftCache !== null ? root.newDraftCache : JSON.parse(forum.state.drafts.new || "{}");
        } catch (e) {}
        newAttachments = d.attachments || [];
        titleInput.text = d.title || "";
        bodyInput.text = d.body || "";
        newBoard = d.board || (board === "all" ? "general" : board);
        composeDialog.open();
        titleInput.forceActiveFocus();
    }
    function saveNewDraft(force) {
        if (force || composeDialog.opened) {
            root.newDraftCache = {
                title: titleInput.text,
                body: bodyInput.text,
                board: newBoard,
                attachments: newAttachments
            };
            forum.draft("new", JSON.stringify(root.newDraftCache));
        }
    }
    Component.onCompleted: console.log("FORUM_UI_READY native discussion interface")

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.narrow ? 64 : 76
            color: theme.sidebar
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: theme.border
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.contentGutter + root.rowInset
                anchors.rightMargin: root.contentGutter + root.rowInset
                spacing: 12
                Canvas {
                    id: wordmark
                    property url artwork: Qt.resolvedUrl("brand/agora-wordmark.png")
                    property color ink: theme.text
                    Layout.preferredWidth: 106
                    Layout.preferredHeight: 40
                    Component.onCompleted: loadImage(artwork)
                    onImageLoaded: requestPaint()
                    onInkChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        if (!isImageLoaded(artwork)) return;
                        var c = getContext("2d");
                        c.clearRect(0, 0, width, height);
                        c.drawImage(artwork, 280, 44, 1560, 588, 0, 0, width, height);
                        // Use the original lettering as a mask, removing its baked-in
                        // forest background. Works with software and GPU rendering.
                        var pixels = c.getImageData(0, 0, width, height).data;
                        c.clearRect(0, 0, width, height);
                        c.fillStyle = ink;
                        for (var y = 0; y < height; y++) {
                            for (var x = 0; x < width; x++) {
                                var i = (y * width + x) * 4;
                                var luminance = (pixels[i] + pixels[i + 1] + pixels[i + 2]) / 3;
                                c.globalAlpha = Math.max(0, Math.min(1, (luminance - 35) / 185));
                                c.fillRect(x, y, 1, 1);
                            }
                        }
                        c.globalAlpha = 1;
                    }
                    Accessible.name: "Agora"
                    Accessible.role: Accessible.Graphic
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.searchText = "";
                            root.goBoard("all");
                        }
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                RowLayout {
                    visible: !root.narrow
                    spacing: 4 * root.uiScale
                    NavigationTab {
                        objectName: "discussionsTab"
                        text: "/all/"
                        selected: root.board === "all"
                        palette.text: theme.text
                        palette.placeholderText: theme.muted
                        onClicked: root.goBoard("all")
                    }
                    Repeater {
                        model: root.boards
                        NavigationTab {
                            required property var modelData
                            objectName: "board-" + modelData.id
                            text: "/" + modelData.id + "/"
                            selected: root.board === modelData.id
                            palette.text: theme.text
                            palette.placeholderText: theme.muted
                            onClicked: root.goBoard(modelData.id)
                        }
                    }
                }
                Item {
                    Layout.fillWidth: true
                    visible: !root.narrow
                }
                ForumField {
                    id: headerSearch
                    clearable: true
                    maximumLength: 200
                    objectName: "headerSearch"
                    visible: !root.narrow
                    Layout.fillWidth: true
                    Layout.maximumWidth: 248 * root.uiScale
                    Layout.minimumWidth: 160
                    implicitHeight: 36
                    leftPadding: 12
                    rightPadding: 36
                    font.pixelSize: 14 * root.uiScale
                    ForumIcon {
                        name: "search"
                        visible: !headerSearch.text.length
                        ink: theme.muted
                        x: parent.width - width - 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20 * root.uiScale
                        height: width
                    }
                    placeholderText: "Search discussions…"
                    text: root.searchText
                    onTextEdited: {
                        root.searchText = text;
                        root.leaveThread();
                    }
                    selectByMouse: true
                    Accessible.name: "Search discussions"
                    palette.base: theme.surface
                    palette.text: theme.text
                    palette.placeholderText: theme.muted
                    palette.mid: theme.border
                }
                Switch {
                    id: themeSwitch
                    HoverHandler { enabled: themeSwitch.enabled; cursorShape: Qt.PointingHandCursor }
                    objectName: "themeToggle"
                    implicitWidth: 40
                    implicitHeight: 40
                    padding: 0
                    hoverEnabled: true
                    checked: root.darkTheme
                    enabled: forum.ready
                    Accessible.name: "Dark theme"
                    ToolTip.visible: hovered
                    ToolTip.delay: 600
                    ToolTip.text: checked ? "Dark theme" : "Light theme"
                    onToggled: forum.mutate({
                        op: "settings",
                        theme: checked ? "dark" : "light"
                    })
                    contentItem: Item {}
                    indicator: Rectangle {
                        x: 0
                        y: 9
                        width: 40
                        height: 22
                        radius: 11
                        color: themeSwitch.hovered ? "#303030" : "#202020"
                        border.color: themeSwitch.visualFocus ? "#eeeeee" : "#666666"
                        border.width: themeSwitch.visualFocus ? 2 : 1
                        Rectangle {
                            x: themeSwitch.checked ? 20 : 2
                            y: 2
                            width: 18
                            height: 18
                            radius: 9
                            color: "#eeeeee"
                            Behavior on x {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                        ForumIcon {
                            x: 5
                            y: 5
                            width: 12
                            height: 12
                            name: "sun"
                            ink: themeSwitch.checked ? "#aaaaaa" : "#222222"
                        }
                        ForumIcon {
                            x: 23
                            y: 5
                            width: 12
                            height: 12
                            name: "moon"
                            ink: themeSwitch.checked ? "#222222" : "#aaaaaa"
                        }
                    }
                }
                ProfileButton {
                    objectName: "profileButton"
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    palette.placeholderText: theme.muted
                    palette.buttonText: theme.muted
                    palette.mid: theme.border
                    palette.highlight: theme.selection
                    avatar: forum.state.avatar || ""
                    enabled: forum.ready
                    onClicked: identityDialog.open()
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            visible: root.selected === ""
            Layout.preferredHeight: root.narrow ? 60 : 72 * root.uiScale
            color: theme.canvas
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.contentGutter + root.rowInset
                anchors.rightMargin: root.contentGutter + root.rowInset
                spacing: root.narrow ? 8 : 16
                ForumSelect {
                    objectName: "boardFilter"
                    visible: root.narrow
                    fitOptions: true
                    Layout.minimumWidth: implicitWidth
                    Layout.preferredWidth: implicitWidth
                    implicitHeight: 36
                    model: [
                        {
                            id: "all",
                            label: "All boards"
                        }
                    ].concat(root.boards)
                    textRole: "label"
                    valueRole: "id"
                    currentIndex: model.findIndex(function (item) {
                        return item.id === root.board;
                    })
                    onActivated: {
                        root.board = currentValue;
                        root.leaveThread();
                    }
                    Accessible.name: "Choose board"
                }
                ForumSelect {
                    objectName: "sortFilter"
                    quiet: !root.narrow
                    fitOptions: true
                    Layout.minimumWidth: implicitWidth
                    Layout.preferredWidth: implicitWidth
                    implicitHeight: 36
                    model: root.narrow ? ["Latest", "Newest", "Most replies"] : ["Latest activity", "Newest threads", "Most replies"]
                    currentIndex: ["activity", "newest", "replies"].indexOf(root.sorting)
                    onActivated: root.sorting = ["activity", "newest", "replies"][currentIndex]
                    Accessible.name: "Sort threads"
                }
                Item {
                    Layout.fillWidth: true
                }
                ForumButton {
                    objectName: "newThreadButton"
                    text: root.narrow ? "+ New" : "+ New thread"
                    implicitWidth: root.narrow ? 76 : 123
                    implicitHeight: 38
                    primary: true
                    enabled: forum.ready
                    onClicked: root.compose()
                }
            }
        }
        Rectangle {
            visible: forum.error !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: errorText.implicitHeight + 20
            color: theme.errorSurface
            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                Text {
                    id: errorText
                    font.family: "Adwaita Sans"
                    Layout.fillWidth: true
                    text: forum.error
                    wrapMode: Text.Wrap
                    color: theme.error
                    font.pixelSize: 12
                }
                ForumButton {
                    text: "Dismiss"
                    onClicked: forum.error = ""
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: root.contentGutter
                Layout.rightMargin: root.contentGutter
                Layout.topMargin: 0
                Layout.bottomMargin: 12
                spacing: 12
                RowLayout {
                    visible: root.selected !== ""
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    Layout.leftMargin: root.rowInset
                    Layout.rightMargin: root.rowInset
                    spacing: 12
                    AbstractButton {
                        id: backToDiscussions
                        objectName: "backToDiscussions"
                        implicitWidth: backContent.implicitWidth
                        implicitHeight: 40
                        hoverEnabled: true
                        Accessible.name: "Back to discussions"
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        background: Item {}
                        contentItem: RowLayout {
                            id: backContent
                            spacing: 8
                            ForumIcon {
                                name: "back"
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                ink: backToDiscussions.hovered || backToDiscussions.visualFocus ? theme.text : theme.muted
                            }
                            Text {
                                text: "Back to discussions"
                                font.family: "Adwaita Sans"
                                font.pixelSize: 13
                                color: backToDiscussions.hovered || backToDiscussions.visualFocus ? theme.text : theme.muted
                                font.underline: backToDiscussions.visualFocus
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }
                        }
                        onClicked: root.leaveThread()
                    }
                    Text {
                        text: "/"
                        color: theme.border
                        font.pixelSize: 13
                    }
                    Text {
                        text: root.boardName(root.current ? root.current.board : root.board)
                        color: theme.muted
                        font.family: "Adwaita Sans"
                        font.pixelSize: 14
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
                ForumField {
                    id: compactSearch
                    objectName: "compactSearchField"
                    clearable: true
                    Layout.leftMargin: root.rowInset
                    Layout.rightMargin: root.rowInset
                    maximumLength: 200
                    visible: root.narrow && root.selected === ""
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    placeholderText: "Search discussions…"
                    text: root.searchText
                    onTextEdited: root.searchText = text
                    Accessible.name: "Search discussions"
                }
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.selected === "" ? 0 : 1
                    Item {
                        ListView {
                            id: threadListView
                            footer: LogosFooter { view: threadListView; rightInset: root.rowInset }
                            objectName: "threadListView"
                            anchors.fill: parent
                            clip: true
                            spacing: 0
                            model: root.visibleThreads
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar {}
                            delegate: Rectangle {
                                id: row
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                height: threadContents.implicitHeight + 32
                                color: rowHover.hovered ? theme.alternate : "transparent"
                                Behavior on color { ColorAnimation { duration: 110 } }
                                HoverHandler {
                                    id: rowHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.title
                                Accessible.onPressAction: root.openThread(row.modelData.id)
                                Keys.onReturnPressed: root.openThread(modelData.id)
                                Keys.onSpacePressed: root.openThread(modelData.id)
                                border.width: activeFocus ? 1 : 0
                                border.color: theme.accent
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.openThread(row.modelData.id)
                                    cursorShape: Qt.PointingHandCursor
                                }
                                RowLayout {
                                    id: threadContents
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: root.rowInset
                                    anchors.rightMargin: root.rowInset
                                    anchors.top: parent.top
                                    anchors.topMargin: 16
                                    spacing: root.narrow ? 12 : 28 * root.uiScale
                                    Loader {
                                        objectName: "feed-preview-" + row.modelData.id
                                        active: (row.modelData.attachments || []).length > 0
                                        visible: active
                                        Layout.preferredWidth: root.narrow ? 80 : 136
                                        Layout.preferredHeight: root.narrow ? 72 : 106
                                        Layout.alignment: Qt.AlignTop
                                        sourceComponent: FeedAttachmentPreview {
                                            attachment: (row.modelData.attachments || [])[0] || null
                                            count: (row.modelData.attachments || []).length
                                            controller: forum
                                            ink: theme.text
                                            muted: theme.muted
                                            surface: theme.surface
                                            outline: theme.border
                                        }
                                    }
                                    ColumnLayout {
                                        objectName: "feed-text-" + row.modelData.id
                                        Layout.alignment: Qt.AlignTop
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        Layout.preferredWidth: 0
                                        spacing: 5 * root.uiScale
                                        Text {
                                            Layout.fillWidth: true
                                            text: row.modelData.title
                                            textFormat: Text.PlainText
                                            font.family: "Liberation Serif"
                                            font.pixelSize: root.narrow ? 22 : 25 * root.uiScale
                                            color: rowHover.hovered ? (root.darkTheme ? "#ffffff" : "#000000") : theme.text
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                        }
                                        Row {
                                            id: feedMetadata
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Text {
                                                width: Math.min(implicitWidth, Math.max(0, feedMetadata.width - (feedDelivery.visible ? feedDelivery.width + 6 : 0)))
                                                text: "/" + row.modelData.board + "/  ·  " + (row.modelData.mode === "anonymous" ? "Anonymous" : row.modelData.mode === "uid" ? root.shortId(row.modelData.author) : row.modelData.author) + "  ·  " + root.activityAge(row.modelData.created) + (row.modelData.replyCount > 0 ? "  ·  " + row.modelData.replyCount + (row.modelData.replyCount === 1 ? " reply" : " replies") : "")
                                                textFormat: Text.PlainText
                                                color: theme.muted
                                                font.family: "Adwaita Sans"
                                                font.pixelSize: root.narrow ? 11 : 14 * root.uiScale
                                                wrapMode: Text.Wrap
                                            }
                                            DeliveryStatus {
                                                publishingDetail: forum.connection === "online" && !forum.publishingReady ? forum.publishingDetail : ""
                                                id: feedDelivery
                                                y: Math.round((feedMetadata.height - height) / 2)
                                                objectName: "feed-status-" + row.modelData.id
                                                status: row.modelData.status || ""
                                                error: row.modelData.error || ""
                                                ink: theme.muted
                                                surface: theme.surface
                                                outline: theme.border
                                                textColor: theme.text
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.maximumWidth: root.narrow ? 10000 : 850 * root.uiScale
                                            text: row.modelData.body.replace(/\s+/g, " ").trim()
                                            textFormat: Text.PlainText
                                            color: theme.muted
                                            font.family: "Adwaita Sans"
                                            font.pixelSize: root.narrow ? 13 : 15 * root.uiScale
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                            lineHeight: 1.3
                                        }
                                        Rectangle {
                                            id: latestPreview
                                            property var replyPosts: root.feedPosts.filter(function (p) { return p.thread === row.modelData.id; })
                                            property var latestReply: replyPosts.length ? replyPosts[replyPosts.length - 1] : null
                                            visible: latestReply !== null
                                            Layout.fillWidth: true
                                            Layout.topMargin: 12 * root.uiScale
                                            implicitHeight: previewColumn.implicitHeight + 4
                                            color: "transparent"
                                            Rectangle {
                                                width: 1
                                                height: parent.height
                                                color: theme.accent
                                                opacity: 0.6
                                            }
                                            ColumnLayout {
                                                id: previewColumn
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.leftMargin: 20 * root.uiScale
                                                spacing: 6
                                                Row {
                                                    id: previewMetadata
                                                    Layout.fillWidth: true
                                                    spacing: 6
                                                    Text {
                                                        width: Math.min(implicitWidth, Math.max(0, previewMetadata.width - (previewDelivery.visible ? previewDelivery.width + 6 : 0)))
                                                        text: latestPreview.latestReply ? (latestPreview.latestReply.mode === "anonymous" ? "Anonymous" : latestPreview.latestReply.mode === "uid" ? root.shortId(latestPreview.latestReply.author) : latestPreview.latestReply.author) + "  ·  " + root.activityAge(latestPreview.latestReply.created) : ""
                                                        textFormat: Text.PlainText
                                                        elide: Text.ElideRight
                                                        color: theme.accent
                                                        font.family: "Adwaita Sans"
                                                        font.pixelSize: root.narrow ? 11 : 14 * root.uiScale
                                                    }
                                                    DeliveryStatus {
                                                publishingDetail: forum.connection === "online" && !forum.publishingReady ? forum.publishingDetail : ""
                                                        id: previewDelivery
                                                        y: Math.round((previewMetadata.height - height) / 2)
                                                        objectName: "preview-status-" + (latestPreview.latestReply ? latestPreview.latestReply.id : "")
                                                        status: latestPreview.latestReply ? latestPreview.latestReply.status : ""
                                                        error: latestPreview.latestReply ? latestPreview.latestReply.error || "" : ""
                                                        ink: theme.muted
                                                        surface: theme.surface
                                                        outline: theme.border
                                                        textColor: theme.text
                                                    }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: parent.parent.latestReply ? parent.parent.latestReply.body.replace(/\n/g, " ") : ""
                                                    textFormat: Text.PlainText
                                                    elide: Text.ElideRight
                                                    color: theme.muted
                                                    font.family: "Adwaita Sans"
                                                    font.pixelSize: root.narrow ? 12 : 15 * root.uiScale
                                                }
                                            }
                                        }
                                    }
                                    RowLayout {
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 0
                                        PostAction {
                                            id: replyAction
                                            objectName: "reply-" + row.modelData.id
                                            text: "Reply"
                                            ink: theme.muted
                                            activeInk: theme.text
                                            Accessible.name: "Reply to " + row.modelData.title
                                            onClicked: {
                                                root.openThread(row.modelData.id);
                                                root.beginReply();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 40, 460)
                            visible: !forum.loading && root.visibleThreads.length === 0
                            spacing: 14
                            Text {
                                font.family: "Adwaita Sans"
                                text: root.searchText ? "No matching discussions." : "A good forum starts with a question."
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: 25
                                font.weight: Font.DemiBold
                                color: theme.text
                            }
                            Text {
                                font.family: "Adwaita Sans"
                                text: root.searchText ? "Try another phrase or change boards." : "What are you working on? What do you disagree with? What would you like to understand better?"
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: 14
                                lineHeight: 1.4
                                color: theme.muted
                            }
                            ForumButton {
                                text: root.searchText ? "Clear search" : "+ Start a thread"
                                primary: true
                                onClicked: root.searchText ? root.searchText = "" : root.compose()
                            }
                            Text {
                                font.family: "Adwaita Sans"
                                text: "Threads you create will appear here, even while offline."
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: 11
                                color: theme.muted
                            }
                        }
                    }
                    ColumnLayout {
                        spacing: 10
                        ListView {
                            id: postsView
                            footer: LogosFooter { view: postsView; rightInset: root.rowInset }
                            objectName: "postsView"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 40
                            clip: true
                            spacing: 12
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar {}
                            model: root.discussionPosts
                            header: Item {
                                width: postsView.width
                                height: threadTitle.implicitHeight + 16
                                property real previousHeight: 0
                                onHeightChanged: {
                                    // Keep the title's first line visible when a top-of-thread
                                    // viewport gets narrower and the heading wraps.
                                    var wasAtTop = postsView.contentY <= postsView.originY + height - previousHeight + 1;
                                    previousHeight = height;
                                    if (wasAtTop)
                                        Qt.callLater(function () { postsView.forceLayout(); postsView.positionViewAtBeginning(); });
                                }
                                Text {
                                    id: threadTitle
                                    objectName: "threadTitle"
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: root.rowInset
                                    anchors.rightMargin: root.rowInset
                                    font.family: "Liberation Serif"
                                    text: root.current ? root.current.title : forum.loading ? "Loading discussion…" : "Thread not found"
                                    wrapMode: Text.Wrap
                                    font.pixelSize: root.width < 600 ? 26 : 30
                                    font.weight: Font.Normal
                                    color: theme.text
                                    textFormat: Text.PlainText
                                }
                            }
                            delegate: Item {
                                id: post
                                required property var modelData
                                required property int index
                                objectName: "post-card-" + modelData.id
                                readonly property bool originalPost: modelData.id === root.selected
                                readonly property var imageAttachments: (modelData.attachments || []).filter(function(a) { return a.mime.indexOf("image/") === 0; })
                                readonly property var otherAttachments: (modelData.attachments || []).filter(function(a) { return a.mime.indexOf("image/") !== 0; })
                                readonly property bool sideImage: imageAttachments.length === 1 && postColumn.width >= 800
                                readonly property real contentPadding: root.width < 600 ? 16 : 20
                                width: ListView.view.width
                                height: postColumn.implicitHeight + 2 * contentPadding
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.leftMargin: root.rowInset
                                    anchors.rightMargin: root.rowInset
                                    color: root.highlightedPost === post.modelData.id ? theme.alternate : post.originalPost ? theme.surface : root.darkTheme ? "#131313" : "#fcfcfc"
                                    radius: 12
                                    border.width: 1
                                    border.color: root.highlightedPost === post.modelData.id ? theme.muted : root.darkTheme ? "#292929" : "#e3e3e3"
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    Behavior on border.color { ColorAnimation { duration: 180 } }
                                }
                                GridLayout {
                                    id: postColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.topMargin: post.contentPadding
                                    anchors.leftMargin: root.rowInset + post.contentPadding
                                    anchors.rightMargin: root.rowInset + post.contentPadding
                                    columns: post.sideImage ? 2 : 1
                                    columnSpacing: 24
                                    rowSpacing: 18
                                    Flow {
                                        objectName: "post-images-" + post.modelData.id
                                        Layout.fillWidth: !post.sideImage
                                        Layout.preferredWidth: post.sideImage ? 260 : -1
                                        Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                                        visible: post.imageAttachments.length > 0
                                        spacing: 12
                                        Repeater {
                                            model: post.imageAttachments
                                            AttachmentCard {
                                                required property var modelData
                                                width: Math.min(260, parent ? parent.width : 260)
                                                imageOnly: true
                                                imageHeight: post.imageAttachments.length === 1 ? 220 : 180
                                                attachment: modelData
                                                controller: forum
                                                ink: theme.text
                                                muted: theme.muted
                                                surface: theme.surface
                                                outline: theme.border
                                                onDownloadRequested: function(aid, filename) {
                                                    root.downloadingAttachment = aid;
                                                    attachmentSaver.open();
                                                }
                                            }
                                        }
                                    }
                                    ColumnLayout {
                                        objectName: "post-text-" + post.modelData.id
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 10
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 10
                                            PostAvatar {
                                                objectName: "post-avatar-" + post.modelData.id
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 28
                                                color: theme.alternate
                                                ink: theme.muted
                                                initial: post.modelData.mode === "anonymous" ? "·" : root.authorName(post.modelData).substring(0, 1).toUpperCase()
                                                avatar: forum.avatarForPost(post.modelData)
                                            }
                                            Text {
                                                Layout.maximumWidth: Math.max(40, parent.width - 240)
                                                text: root.authorName(post.modelData)
                                                font.family: "Adwaita Sans"
                                                font.pixelSize: 14
                                                font.weight: Font.DemiBold
                                                color: theme.text
                                                textFormat: Text.PlainText
                                                elide: Text.ElideRight
                                                HoverHandler { id: authorHover }
                                                ToolTip.visible: authorHover.hovered
                                                ToolTip.delay: 500
                                                ToolTip.text: root.displayAuthor(post.modelData) + "\nPost >>" + root.shortId(post.modelData.id) + " · " + root.statusLabel(post.modelData.status)
                                                Accessible.description: root.displayAuthor(post.modelData) + ". Post " + root.shortId(post.modelData.id) + ". " + root.statusLabel(post.modelData.status)
                                            }
                                            Text {
                                                text: root.activityAge(post.modelData.created)
                                                font.family: "Adwaita Sans"
                                                font.pixelSize: 13
                                                color: theme.muted
                                            }
                                            DeliveryStatus {
                                                    publishingDetail: forum.connection === "online" && !forum.publishingReady ? forum.publishingDetail : ""
                                                id: postDeliveryStatus
                                                objectName: "post-status-" + post.modelData.id
                                                status: post.modelData.status || ""
                                                error: post.modelData.error || ""
                                                ink: theme.muted
                                                surface: theme.surface
                                                outline: theme.border
                                                textColor: theme.text
                                            }
                                            ForumButton {
                                                objectName: "retry-post-" + post.modelData.id
                                                visible: post.modelData.status === "failed"
                                                text: "Retry sending"
                                                implicitHeight: 40
                                                palette.buttonText: postDeliveryStatus.ink
                                                Accessible.description: "Retry this post without creating a duplicate. Publishing checks still apply."
                                                onClicked: forum.retryPost(post.modelData.id)
                                            }
                                            Item { Layout.fillWidth: true }
                                            RowLayout {
                                                spacing: 0
                                                PostAction {
                                                    id: postReplyButton
                                                    objectName: post.originalPost ? "beginReplyButton" : "reply-" + post.modelData.id
                                                    text: "Reply"
                                                    ink: theme.muted
                                                    activeInk: theme.text
                                                    Accessible.name: "Reply to " + root.authorName(post.modelData)
                                                    Accessible.description: "Reply with this message quoted for context"
                                                    onClicked: {
                                                        root.replyTrigger = postReplyButton;
                                                        root.quote(post.modelData);
                                                    }
                                                }
                                            }
                                        }
                                        PostBody {
                                            objectName: "post-body-" + post.modelData.id
                                            Layout.fillWidth: true
                                            text: post.modelData.body
                                            controller: forum
                                            onPostActivated: function(target) { root.navigateToQuotedPost(target); }
                                            ink: theme.text
                                            quoteInk: theme.quote
                                            muted: theme.muted
                                            quoteSurface: root.darkTheme ? "#222222" : "#eeeeee"
                                            quoteOutline: root.darkTheme ? "#2b2b2b" : "#e1e1e1"
                                        }
                                        Flow {
                                            Layout.fillWidth: true
                                            visible: post.otherAttachments.length > 0
                                            spacing: 12
                                            Repeater {
                                                model: post.otherAttachments
                                                AttachmentCard {
                                                    required property var modelData
                                                    attachment: modelData
                                                    controller: forum
                                                    ink: theme.text
                                                    muted: theme.muted
                                                    surface: theme.surface
                                                    outline: theme.border
                                                    onDownloadRequested: function (aid, filename) {
                                                        root.downloadingAttachment = aid;
                                                        attachmentSaver.open();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Item {
                            id: replyArea
                            objectName: "replyArea"
                            visible: !!root.current && (root.replyExpanded || progress > 0)
                            Layout.fillWidth: true
                            Layout.topMargin: 12 * progress
                            Layout.preferredHeight: replyComposer.height * progress
                            clip: true
                            property real progress: root.replyExpanded ? 1 : 0
                            Behavior on progress {
                                enabled: !!root.current
                                NumberAnimation {
                                    duration: root.replyExpanded ? 220 : 160
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Rectangle {
                                id: replyComposer
                                objectName: "replyComposer"
                                visible: root.replyExpanded || replyArea.progress > 0
                                enabled: root.replyExpanded
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                width: Math.min(880, parent.width - 2 * root.rowInset)
                                height: replyBox.implicitHeight + 40
                                opacity: Math.max(0, (replyArea.progress - 0.2) / 0.8)
                                transform: Translate { y: 12 * (1 - replyArea.progress) }
                                color: theme.surface
                                radius: 20
                                border.width: 1
                                border.color: theme.border
                                ColumnLayout {
                                    id: replyBox
                                    anchors.fill: parent
                                    anchors.margins: root.width < 600 ? 16 : 20
                                    spacing: 14
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        ForumButton {
                                            id: replyIdentityButton
                                            objectName: "replyIdentityButton"
                                            Layout.maximumWidth: replyBox.width - 48
                                            implicitWidth: identityContents.implicitWidth + 12
                                            implicitHeight: 40
                                            flat: true
                                            padding: 0
                                            cornerRadius: 14
                                            enabled: !forum.posting
                                            Accessible.name: "Replying as " + root.replyIdentity + ". Change posting identity"
                                            onClicked: identityDialog.open()
                                            contentItem: RowLayout {
                                                id: identityContents
                                                spacing: 10
                                                PostAvatar {
                                                    objectName: "replyIdentityAvatar"
                                                    Layout.preferredWidth: 32
                                                    Layout.preferredHeight: 32
                                                    color: theme.alternate
                                                    ink: theme.text
                                                    initial: forum.state.mode === "anonymous" ? "·" : root.replyIdentity.substring(0, 1).toUpperCase()
                                                    avatar: forum.state.mode === "anonymous" ? null : forum.state.avatar || null
                                                }
                                                Text {
                                                    visible: replyComposer.width >= 380
                                                    text: "Replying as"
                                                    font.family: "Adwaita Sans"
                                                    font.pixelSize: 14
                                                    color: theme.muted
                                                }
                                                Text {
                                                    Layout.maximumWidth: Math.max(60, replyComposer.width - (replyComposer.width >= 380 ? 250 : 170))
                                                    text: root.replyIdentity
                                                    elide: Text.ElideRight
                                                    textFormat: Text.PlainText
                                                    font.family: "Adwaita Sans"
                                                    font.pixelSize: 14
                                                    font.weight: Font.Medium
                                                    color: theme.text
                                                }
                                                ForumIcon {
                                                    name: "chevron-down"
                                                    ink: theme.muted
                                                    Layout.preferredWidth: 16
                                                    Layout.preferredHeight: 16
                                                }
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        ForumButton {
                                            id: minimizeReplyButton
                                            objectName: "minimizeReplyButton"
                                            implicitWidth: 40
                                            implicitHeight: 40
                                            padding: 10
                                            cornerRadius: 12
                                            flat: true
                                            Accessible.name: "Minimize reply"
                                            ToolTip.visible: hovered
                                            ToolTip.delay: 600
                                            ToolTip.text: "Minimize · Esc"
                                            contentItem: ForumIcon {
                                                name: "minus"
                                                ink: minimizeReplyButton.hovered || minimizeReplyButton.visualFocus ? theme.text : theme.muted
                                            }
                                            onClicked: root.minimizeReply()
                                        }
                                    }
                                    ScrollView {
                                        id: replyScroll
                                        objectName: "replyScroll"
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.height < 650 ? 64 : 112
                                        clip: true
                                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                        TextArea {
                                            id: replyInput
                                            objectName: "replyInput"
                                            width: replyScroll.availableWidth
                                            placeholderText: "What would you like to share?"
                                            wrapMode: TextEdit.Wrap
                                            font.family: "Adwaita Sans"
                                            font.pixelSize: 16
                                            color: theme.text
                                            placeholderTextColor: theme.muted
                                            padding: 4
                                            background: null
                                            selectByMouse: true
                                            readOnly: forum.posting
                                            Keys.onPressed: function (event) {
                                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                                        && (event.modifiers & ~Qt.KeypadModifier) === Qt.ControlModifier) {
                                                    event.accepted = true;
                                                    if (!event.isAutoRepeat && submitReplyButton.enabled)
                                                        submitReplyButton.clicked();
                                                }
                                            }
                                            cursorDelegate: Rectangle {
                                                objectName: "replyCaret"
                                                width: 2
                                                height: replyInput.cursorRectangle.height
                                                color: theme.text
                                                // A steady, high-contrast caret is easier to find at
                                                // column zero, including on an otherwise empty line.
                                                visible: replyInput.activeFocus && !replyInput.readOnly && replyInput.selectionStart === replyInput.selectionEnd
                                            }
                                            onTextChanged: {
                                                root.replyDraftGeneration++;
                                                root.replyDraftStatus = "Saving draft…";
                                                replyDraftTimer.restart();
                                            }
                                            Accessible.name: "Reply text"
                                            Accessible.description: "Your draft is saved on this device. Ctrl+Enter posts your reply. Escape minimizes the editor."
                                        }
                                    }
                                    ListView {
                                        objectName: "replyAttachmentTray"
                                        visible: root.replyAttachments.length > 0
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        orientation: ListView.Horizontal
                                        clip: true
                                        spacing: 8
                                        boundsBehavior: Flickable.StopAtBounds
                                        model: root.replyAttachments
                                        delegate: Rectangle {
                                            id: attachedFile
                                            required property var modelData
                                            required property int index
                                            width: Math.min(replyBox.width, fileName.implicitWidth + 64)
                                            height: 40
                                            radius: 10
                                            color: theme.alternate
                                            Text {
                                                id: fileName
                                                anchors.left: parent.left
                                                anchors.leftMargin: 12
                                                anchors.right: removeFile.left
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: attachedFile.modelData.name
                                                elide: Text.ElideMiddle
                                                textFormat: Text.PlainText
                                                font.family: "Adwaita Sans"
                                                font.pixelSize: 12
                                                color: theme.text
                                            }
                                            ForumButton {
                                                id: removeFile
                                                objectName: "removeReplyAttachment-" + attachedFile.index
                                                anchors.right: parent.right
                                                implicitWidth: 40
                                                implicitHeight: 40
                                                padding: 12
                                                flat: true
                                                enabled: !forum.posting
                                                Accessible.name: "Remove " + attachedFile.modelData.name
                                                contentItem: ForumIcon { name: "close"; ink: theme.muted }
                                                onClicked: {
                                                    var files = root.replyAttachments.slice();
                                                    files.splice(attachedFile.index, 1);
                                                    root.replyAttachments = files;
                                                    root.saveReplyDraft();
                                                }
                                            }
                                        }
                                    }
                                    Text {
                                        visible: root.replyLocalOnly || replyInput.text.length > 12000
                                        Layout.fillWidth: true
                                        text: replyInput.text.length > 12000 ? "Reply is too long. Use 12,000 characters or fewer." : "Local only · this reply will stay on this device"
                                        font.family: "Adwaita Sans"
                                        font.pixelSize: 12
                                        wrapMode: Text.Wrap
                                        color: theme.muted
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 14
                                        ForumButton {
                                            id: attachReplyButton
                                            objectName: "attachReplyButton"
                                            flat: true
                                            padding: 2
                                            implicitWidth: 74
                                            implicitHeight: 44
                                            cornerRadius: 12
                                            enabled: !forum.posting && root.replyAttachments.length < 4
                                            Accessible.name: "Attach an image, video or PDF"
                                            ToolTip.visible: hovered
                                            ToolTip.delay: 600
                                            ToolTip.text: "Images, video or PDF · up to 64 MB"
                                            contentItem: RowLayout {
                                                spacing: 8
                                                ForumIcon {
                                                    name: "attach"
                                                    ink: attachReplyButton.hovered || attachReplyButton.visualFocus ? theme.text : theme.muted
                                                    Layout.preferredWidth: 20
                                                    Layout.preferredHeight: 20
                                                }
                                                Text {
                                                    text: "Attach"
                                                    color: attachReplyButton.hovered || attachReplyButton.visualFocus ? theme.text : theme.muted
                                                    font.family: "Adwaita Sans"
                                                    font.pixelSize: 13
                                                }
                                            }
                                            onClicked: {
                                                root.attachmentTarget = root.selected;
                                                attachmentPicker.open();
                                            }
                                        }
                                        Rectangle {
                                            visible: draftStatus.visible && draftStatus.text.length > 0
                                            Layout.preferredWidth: 1
                                            Layout.preferredHeight: 18
                                            color: theme.border
                                        }
                                        Text {
                                            id: draftStatus
                                            objectName: "replyDraftStatus"
                                            visible: replyComposer.width >= 340
                                            text: root.replyDraftStatus
                                            font.family: "Adwaita Sans"
                                            font.pixelSize: 12
                                            color: theme.muted
                                            Accessible.name: text
                                        }
                                        Item { Layout.fillWidth: true }
                                        ForumButton {
                                            id: submitReplyButton
                                            objectName: "submitReplyButton"
                                            text: forum.posting ? (forum.transferBusy ? "Uploading…" : "Saving…") : "Post reply"
                                            primary: true
                                            implicitHeight: 44
                                            font.pixelSize: 14
                                            cornerRadius: 14
                                            ToolTip.visible: hovered
                                            ToolTip.delay: 600
                                            ToolTip.text: "Post reply · Ctrl+Enter"
                                            enabled: !!root.current && forum.ready && !forum.posting && replyInput.text.trim().length > 0 && replyInput.text.length <= 12000
                                            onClicked: {
                                                replyDraftTimer.stop();
                                                var threadId = root.selected;
                                                if (forum.posting) return;
                                                forum.savePost(threadId, root.current.board, "", replyInput.text, function (result) {
                                                    root.replyDraftCache[threadId] = "";
                                                    root.replyAttachmentCache[threadId] = [];
                                                    forum.draft("files/" + threadId, "[]");
                                                    if (root.selected === threadId) {
                                                        replyInput.text = "";
                                                        root.replyAttachments = [];
                                                        replyDraftTimer.stop();
                                                        root.replyDraftStatus = "";
                                                        root.replyExpanded = false;
                                                        postsView.forceActiveFocus();
                                                        root.showPostedReply(threadId, result.id);
                                                    }
                                                }, root.replyAttachments.map(function (f) {
                                                    return f.id;
                                                }));
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: forum.state.hasMore || (root.selected ? root.replyHistory.length : root.feedHistory.length) > 0
                    ForumButton {
                        objectName: "previousPage"
                        text: root.selected ? "Earlier replies" : "Newer discussions"
                        flat: true
                        enabled: !forum.loading && (root.selected ? root.replyHistory.length : root.feedHistory.length) > 0
                        onClicked: root.previousPage()
                    }
                    Item { Layout.fillWidth: true }
                    ForumButton {
                        objectName: "nextPage"
                        text: root.selected ? "More replies" : "Older discussions"
                        flat: true
                        enabled: !forum.loading && forum.state.hasMore
                        onClicked: root.nextPage()
                    }
                }

            }
        }
    }
    component LogosFooter: Item {
        id: footerRoot
        objectName: "logosFooter"
        required property ListView view
        property real rightInset: 16
        width: view.width
        height: 64
        // Measure after ListView lays out its items; a direct height/y binding
        // feeds back into ListView's own positioning during model changes.
        function fitPage() {
            var needed = Math.max(64, view.height - (y - view.originY));
            if (Math.abs(height - needed) > 0.5) height = needed;
        }
        onYChanged: Qt.callLater(fitPage)
        Component.onCompleted: Qt.callLater(fitPage)
        Connections {
            target: footerRoot.view
            function onHeightChanged() { Qt.callLater(footerRoot.fitPage); }
            function onOriginYChanged() { Qt.callLater(footerRoot.fitPage); }
            function onContentHeightChanged() { Qt.callLater(footerRoot.fitPage); }
        }
        AbstractButton {
            id: logosReference
            objectName: "logosReference"
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            anchors.right: parent.right
            anchors.rightMargin: footerRoot.rightInset
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            implicitWidth: 40
            implicitHeight: 40
            hoverEnabled: true
            Accessible.name: "Logos — open logos.co"
            ToolTip.visible: hovered
            ToolTip.delay: 700
            ToolTip.text: "Logos"
            background: Item {}
            contentItem: Item {
                Image {
                    anchors.centerIn: parent
                    source: "brand/logos-mark.png"
                    sourceSize: Qt.size(24, 24)
                    width: 24
                    height: 24
                    opacity: logosReference.hovered || logosReference.activeFocus ? 1 : 0.65
                }
            }
            onClicked: Qt.openUrlExternally("https://logos.co/")
        }
    }
    Timer {
        id: loadingDelay
        interval: 180
        running: forum.loading
        onTriggered: loadingIndicator.visible = forum.loading
    }
    BusyIndicator {
        id: loadingIndicator
        visible: false
        running: visible
        width: 24
        height: 24
        anchors.right: parent.right
        anchors.rightMargin: root.contentGutter + root.rowInset + 46
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        Accessible.name: "Loading discussions"
    }
    Shortcut {
        sequences: [StandardKey.Find]
        enabled: !composeDialog.visible && !identityDialog.visible
        onActivated: {
            root.leaveThread();
            (root.narrow ? compactSearch : headerSearch).forceActiveFocus();
        }
    }
    Shortcut {
        sequences: [StandardKey.Back]
        enabled: !!root.selected && !composeDialog.visible && !identityDialog.visible
        onActivated: root.leaveThread()
    }
    Shortcut {
        sequence: "Escape"
        enabled: root.replyExpanded && !composeDialog.visible && !identityDialog.visible
        onActivated: root.minimizeReply()
    }
    Timer {
        id: replyDraftTimer
        interval: 350
        onTriggered: root.saveReplyDraft()
    }
    Timer {
        id: newDraftTimer
        interval: 350
        onTriggered: root.saveNewDraft()
    }
    ForumDialog {
        id: composeDialog
        palette: root.palette
        background: Rectangle {
            color: theme.surface
            border.color: theme.border
            radius: 10
        }
        objectName: "composeDialog"
        title: "Start a thread"
        modal: true
        anchors.centerIn: parent
        width: Math.min(root.width - 30, 620)
        closePolicy: Popup.CloseOnEscape
        property bool submitted: false
        onOpened: submitted = false
        onAboutToHide: {
            if (!submitted)
                root.saveNewDraft(true);
        }
        contentItem: ScrollView {
            id: composeDialogScroll
            clip: true
            implicitHeight: composeDialogContents.implicitHeight
            contentWidth: availableWidth
            contentHeight: composeDialogContents.implicitHeight
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ColumnLayout {
                id: composeDialogContents
                width: composeDialogScroll.availableWidth

            spacing: 12
            Text {
                objectName: "composeError"
                visible: !!forum.error
                text: forum.error
                textFormat: Text.PlainText
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: 13
                color: theme.error
            }
            Text {
                font.family: "Adwaita Sans"
                text: "Make the title specific. Give people something to respond to."
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: theme.muted
                font.pixelSize: 12
            }
            ForumSelect {
                Layout.fillWidth: true
                model: root.boards
                textRole: "label"
                valueRole: "id"
                currentIndex: root.boards.findIndex(function (b) {
                    return b.id === root.newBoard;
                })
                onActivated: root.newBoard = currentValue
                Accessible.name: "Thread board"
            }
            Label { text: "Title"; color: theme.muted; font.pixelSize: 12 }
            ForumField {
                id: titleInput
                objectName: "titleInput"
                Layout.fillWidth: true
                placeholderText: "Thread title"
                maximumLength: 160
                font.pixelSize: 15
                selectByMouse: true
                onTextChanged: newDraftTimer.restart()
                Accessible.name: "Thread title"
            }
            Label { text: "Message"; color: theme.muted; font.pixelSize: 12 }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(100, Math.min(180, root.height * 0.24))
                TextArea {
                    id: bodyInput
                    objectName: "bodyInput"
                    placeholderText: "Write your post…"
                    wrapMode: TextEdit.Wrap
                    font.pixelSize: 14
                    selectByMouse: true
                    onTextChanged: newDraftTimer.restart()
                    Accessible.name: "Thread message"
                }
            }
            Text {
                font.family: "Adwaita Sans"
                text: bodyInput.length + " / 12000" + (root.newAttachments.length && !forum.state.storageEndpoint ? " · Local-only thread · attachments stay here" : forum.connection === "online" ? "" : " · Offline · saved here, sent when connected")
                font.pixelSize: 11
                color: bodyInput.length > 12000 ? theme.error : theme.muted
            }
            AttachmentPickerRow {
                controller: forum
                ink: theme.text
                muted: theme.muted
                Layout.fillWidth: true
                uploadAvailable: !!forum.state.storageEndpoint
                files: root.newAttachments
                onAddRequested: {
                    root.attachmentTarget = "new";
                    attachmentPicker.open();
                }
                onRemoveRequested: function (index) {
                    var f = root.newAttachments.slice();
                    f.splice(index, 1);
                    root.newAttachments = f;
                    root.saveNewDraft();
                }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: root.narrow ? 2 : 4
                columnSpacing: 8
                rowSpacing: 8
                ForumButton {
                    Layout.columnSpan: root.narrow ? 2 : 1
                    Layout.fillWidth: !root.narrow
                    text: forum.state.mode === "anonymous" ? "Anonymous" : forum.activeAlias()
                    Layout.maximumWidth: 110
                    onClicked: identityDialog.open()
                }
                Item {
                    visible: !root.narrow
                    Layout.fillWidth: true
                }
                ForumButton {
                    Layout.fillWidth: root.narrow
                    Layout.alignment: Qt.AlignRight
                    text: "Keep draft"
                    onClicked: {
                        root.saveNewDraft();
                        composeDialog.close();
                    }
                }
                ForumButton {
                    objectName: "submitThreadButton"
                    Layout.fillWidth: root.narrow
                    text: forum.posting ? (forum.transferBusy ? "Uploading…" : "Saving…") : root.newAttachments.length && !forum.state.storageEndpoint ? "Save locally" : "Create thread"
                    primary: true
                    enabled: forum.ready && !forum.posting && titleInput.text.trim().length > 0 && bodyInput.text.trim().length > 0 && bodyInput.length <= 12000
                    onClicked: {
                        newDraftTimer.stop();
                        if (forum.posting) return;
                        forum.savePost("", root.newBoard, titleInput.text, bodyInput.text, function (r) {
                            composeDialog.submitted = true;
                            root.newDraftCache = {};
                            composeDialog.close();
                            root.openThread(r.id);
                        }, root.newAttachments.map(function (f) {
                            return f.id;
                        }));
                    }
                }
            }
                    }
        }
    }
    NativeDialogs.FileDialog {
        id: attachmentPicker
        title: "Attach an image, video or PDF"
        nameFilters: ["Supported files (*.png *.jpg *.jpeg *.mp4 *.webm *.pdf)"]
        fileMode: NativeDialogs.FileDialog.OpenFile
        onAccepted: {
            var target = root.attachmentTarget;
            forum.call({
                op: "attachmentImport",
                file: selectedFile.toString()
            }, function (r) {
                if (target === "new") {
                    root.newAttachments = root.newAttachments.concat([r.attachment]);
                    root.saveNewDraft(true);
                } else if (root.selected === target) {
                    root.replyAttachments = root.replyAttachments.concat([r.attachment]);
                    root.saveReplyDraft();
                } else {
                    var list = root.replyAttachmentCache[target] || [];
                    list = list.concat([r.attachment]);
                    root.replyAttachmentCache[target] = list;
                    forum.draft("files/" + target, JSON.stringify(list));
                }
            });
        }
    }
    NativeDialogs.FileDialog {
        id: attachmentSaver
        title: "Save attachment as a new file"
        fileMode: NativeDialogs.FileDialog.SaveFile
        onAccepted: forum.call({
            op: "attachmentExport",
            id: root.downloadingAttachment,
            file: selectedFile.toString()
        }, function () {
            forum.notice = "Attachment saved.";
        })
    }
    NativeDialogs.FileDialog {
        id: avatarPicker
        title: "Choose a profile photo"
        nameFilters: ["Images (*.png *.jpg *.jpeg)"]
        fileMode: NativeDialogs.FileDialog.OpenFile
        onAccepted: forum.mutate({
            op: "avatar",
            file: selectedFile.toString()
        })
    }
    ForumDialog {
        id: identityDialog
        objectName: "identityDialog"
        palette: root.palette
        background: Rectangle {
            color: theme.surface
            border.color: theme.border
            radius: 10
        }
        title: "Profile"
        modal: true
        anchors.centerIn: parent
        width: Math.min(root.width - 30, 500)
        contentItem: ScrollView {
            id: identityDialogScroll
            clip: true
            implicitHeight: identityDialogContents.implicitHeight
            contentWidth: availableWidth
            contentHeight: identityDialogContents.implicitHeight
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ColumnLayout {
                id: identityDialogContents
                width: identityDialogScroll.availableWidth

            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                ProfileButton {
                    implicitWidth: 64
                    implicitHeight: 64
                    avatar: forum.state.avatar || ""
                    Accessible.name: "Change profile picture"
                    onClicked: avatarPicker.open()
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        font.family: "Adwaita Sans"
                        text: forum.activeAlias()
                        textFormat: Text.PlainText
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        color: theme.text
                    }
                    RowLayout {
                        ForumButton {
                            text: forum.state.avatar ? "Change photo" : "Upload photo"
                            onClicked: avatarPicker.open()
                        }
                        ForumButton {
                            visible: !!forum.state.avatar
                            text: "Remove"
                            flat: true
                            onClicked: forum.mutate({
                                op: "avatar",
                                remove: true
                            })
                        }
                    }
                }
            }
            Text {
                font.family: "Adwaita Sans"
                Layout.fillWidth: true
                text: forum.error || "PNG or JPEG · up to 8 MB"
                wrapMode: Text.Wrap
                font.pixelSize: 11
                color: forum.error ? theme.error : theme.muted
            }
            Text {
                font.family: "Adwaita Sans"
                Layout.fillWidth: true
                text: "Choose how you appear in a discussion. Keep a familiar alias, use a public ID, or post anonymously."
                wrapMode: Text.Wrap
                font.pixelSize: 12
                color: theme.muted
            }
            ForumSelect {
                Layout.fillWidth: true
                model: forum.state.identities
                textRole: "alias"
                valueRole: "id"
                currentIndex: forum.state.identities.findIndex(function (i) {
                    return i.id === forum.state.active;
                })
                onActivated: forum.mutate({
                    op: "settings",
                    active: currentValue
                })
                Accessible.name: "Active identity"
            }
            ForumSelect {
                Layout.fillWidth: true
                model: ["Alias + verifiable public key", "Unique public ID", "Anonymous · no identity"]
                currentIndex: ["alias", "uid", "anonymous"].indexOf(forum.state.mode)
                onActivated: forum.mutate({
                    op: "settings",
                    mode: ["alias", "uid", "anonymous"][currentIndex]
                })
                Accessible.name: "Posting mode"
            }
            CheckBox {
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                text: "New identity for each thread"
                checked: forum.state.rotate
                onToggled: forum.mutate({
                    op: "settings",
                    rotate: checked
                })
            }
            RowLayout {
                Layout.fillWidth: true
                ForumField {
                    id: aliasInput
                    Layout.fillWidth: true
                    placeholderText: "New alias"
                    maximumLength: 32
                    Accessible.name: "New alias"
                }
                ForumButton {
                    text: "Create identity"
                    enabled: aliasInput.text.trim().length > 0
                    onClicked: forum.mutate({
                        op: "identity",
                        alias: aliasInput.text
                    }, function () {
                        aliasInput.text = "";
                    })
                }
            }
            ForumButton {
                text: "Done"
                Layout.alignment: Qt.AlignRight
                onClicked: identityDialog.close()
            }
                    }
        }
    }
}
