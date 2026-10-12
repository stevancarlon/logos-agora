pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
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
        readonly property color canvas: root.darkTheme ? "#101815" : "#f5f5ef"
        readonly property color sidebar: root.darkTheme ? "#121b17" : "#ecefe5"
        readonly property color surface: root.darkTheme ? "#1a221d" : "#fafbf5"
        readonly property color alternate: root.darkTheme ? "#1e2821" : "#eef0e7"
        readonly property color selection: root.darkTheme ? "#233128" : "#dce7db"
        readonly property color border: root.darkTheme ? "#2c3931" : "#cdd8c4"
        readonly property color text: root.darkTheme ? "#e6e8df" : "#2e4632"
        readonly property color muted: root.darkTheme ? "#a7b2a9" : "#66765f"
        readonly property color accent: root.darkTheme ? "#b3d0b7" : "#366144"
        readonly property color quote: root.darkTheme ? "#e5b77f" : "#9b603c"
        readonly property color error: root.darkTheme ? "#ffc3ac" : "#8b422d"
        readonly property color errorSurface: root.darkTheme ? "#442e25" : "#f6e7d8"
    }
    implicitWidth: 1160
    implicitHeight: 760
    property alias controller: forum
    property string board: "all"
    property string selected: ""
    property string pendingReplyScroll: ""
    property string searchText: ""
    property string sorting: "activity"
    property bool replyExpanded: false
    property var newAttachments: []
    property var replyAttachments: []
    property var replyAttachmentCache: ({})
    property string attachmentTarget: "new"
    property string downloadingAttachment: ""
    property var replyDraftCache: ({})
    property bool showingSaved: false
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
    property bool narrow: width < 850
    readonly property real uiScale: narrow ? 1 : Math.max(0.82, Math.min(1, width / 1402))
    property string newBoard: board === "all" ? "general" : board
    property string feedCursor: ""
    property string replyCursor: ""
    property var feedHistory: []
    property var replyHistory: []
    onBoardChanged: resetFeedPages()
    onSearchTextChanged: resetFeedPages()
    onSortingChanged: resetFeedPages()
    onShowingSavedChanged: resetFeedPages()
    onSelectedChanged: { pendingReplyScroll = ""; replyCursor = ""; replyHistory = []; }
    function resetFeedPages() { feedCursor = ""; feedHistory = []; }
    function nextPage() {
        if (!forum.state.hasMore || forum.loading) return;
        if (selected) { replyHistory = replyHistory.concat([replyCursor]); replyCursor = forum.state.nextCursor; }
        else { feedHistory = feedHistory.concat([feedCursor]); feedCursor = forum.state.nextCursor; }
        threadListView.positionViewAtBeginning(); postsView.positionViewAtBeginning();
    }
    function previousPage() {
        var history = (selected ? replyHistory : feedHistory).slice();
        if (!history.length || forum.loading) return;
        var cursor = history.pop();
        if (selected) { replyHistory = history; replyCursor = cursor; }
        else { feedHistory = history; feedCursor = cursor; }
        threadListView.positionViewAtBeginning(); postsView.positionViewAtBeginning();
    }
    property var visibleThreads: threadList()
    ForumController {
        id: forum
        onLoadingChanged: {
            if (!loading && root.pendingReplyScroll && root.findPost(root.pendingReplyScroll)) {
                root.pendingReplyScroll = "";
                Qt.callLater(function () { postsView.positionViewAtEnd(); });
            }
        }
        browseQuery: ({view: root.selected ? "thread" : "feed", thread: root.selected,
            board: root.selected ? "all" : root.board, search: root.selected ? "" : root.searchText,
            sort: root.selected ? "activity" : root.sorting, saved: root.selected ? false : root.showingSaved,
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
        return status === "sent" ? "Network confirmed" : status === "received" ? "Received" : status === "sending" ? "Sending…" : status === "failed" ? "Retry pending" : "Saved locally · queued";
    }
    function threadList() {
        return forum.state.posts.filter(function (p) { return !p.thread; });
    }
    function saveReplyDraft() {
        replyDraftTimer.stop();
        if (selected) {
            replyDraftCache[selected] = replyInput.text;
            replyAttachmentCache[selected] = replyAttachments;
            forum.draft("files/" + selected, JSON.stringify(replyAttachments));
            forum.draft(selected, replyInput.text);
        }
    }
    function leaveThread() {
        saveReplyDraft();
        selected = "";
        replyExpanded = false;
    }
    function goBoard(id) {
        leaveThread();
        resetFeedPages();
        board = id;
        showingSaved = false;
    }
    function openThread(pid) {
        saveReplyDraft();
        selected = pid;
        replyInput.text = Object.prototype.hasOwnProperty.call(replyDraftCache, pid) ? replyDraftCache[pid] : forum.state.drafts[pid] || "";
        replyDraftTimer.stop();
        try {
            replyAttachments = replyAttachmentCache[pid] || JSON.parse(forum.state.drafts["files/" + pid] || "[]");
        } catch (e) {
            replyAttachments = [];
        }
        replyExpanded = false;
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
    function quote(p) {
        replyInput.text += (replyInput.text ? "\n\n" : "") + ">>" + shortId(p.id) + "\n> " + p.body.split("\n").slice(0, 3).join("\n> ") + "\n\n";
        beginReply();
    }
    function compose() {
        var d = {};
        try {
            d = JSON.parse(forum.state.drafts.new || "{}");
        } catch (e) {}
        newAttachments = d.attachments || [];
        titleInput.text = d.title || "";
        bodyInput.text = d.body || "";
        newBoard = d.board || (board === "all" ? "general" : board);
        composeDialog.open();
        titleInput.forceActiveFocus();
    }
    function saveNewDraft(force) {
        if (force || composeDialog.opened)
            forum.draft("new", JSON.stringify({
                title: titleInput.text,
                body: bodyInput.text,
                board: newBoard,
                attachments: newAttachments
            }));
    }
    Component.onCompleted: console.log("FORUM_UI_READY native discussion interface")

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.narrow ? 64 : 76 * root.uiScale
            color: "#141a17"
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: theme.border
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.narrow ? 16 : 26 * root.uiScale
                anchors.rightMargin: root.narrow ? 16 : 26 * root.uiScale
                spacing: 12
                Image {
                    source: "brand/agora-wordmark.png"
                    smooth: true
                    mipmap: true
                    sourceSize: Qt.size(544, 181)
                    sourceClipRect: Qt.rect(70, 11, 390, 147)
                    Layout.preferredWidth: 106
                    Layout.preferredHeight: 40
                    fillMode: Image.PreserveAspectFit
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
                        selected: root.board === "all" && !root.showingSaved
                        palette.text: "#e6e8df"
                        palette.placeholderText: "#a7b2a9"
                        onClicked: root.goBoard("all")
                    }
                    Repeater {
                        model: root.boards
                        NavigationTab {
                            required property var modelData
                            objectName: "board-" + modelData.id
                            text: "/" + modelData.id + "/"
                            selected: root.board === modelData.id && !root.showingSaved
                            palette.text: "#e6e8df"
                            palette.placeholderText: "#a7b2a9"
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
                    maximumLength: 200
                    objectName: "headerSearch"
                    visible: !root.narrow
                    Layout.fillWidth: true
                    Layout.maximumWidth: 248 * root.uiScale
                    Layout.minimumWidth: 160
                    implicitHeight: 36 * root.uiScale
                    leftPadding: 12
                    rightPadding: 36
                    font.pixelSize: 14 * root.uiScale
                    ForumIcon {
                        name: "search"
                        ink: "#a7b2a9"
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
                    palette.base: "#1a221d"
                    palette.text: "#e6e8df"
                    palette.placeholderText: "#a7b2a9"
                    palette.mid: "#2c3931"
                }
                Switch {
                    id: themeSwitch
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
                        color: themeSwitch.hovered ? "#233d30" : "#172a21"
                        border.color: themeSwitch.activeFocus ? "#b3d0b7" : "#587060"
                        border.width: themeSwitch.activeFocus ? 2 : 1
                        Rectangle {
                            x: themeSwitch.checked ? 20 : 2
                            y: 2
                            width: 18
                            height: 18
                            radius: 9
                            color: "#d9e7d7"
                            Behavior on x {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                        Image {
                            x: 5
                            y: 5
                            width: 12
                            height: 12
                            source: themeSwitch.checked ? "icons/sun-muted.png" : "icons/sun-active.png"
                        }
                        Image {
                            x: 23
                            y: 5
                            width: 12
                            height: 12
                            source: themeSwitch.checked ? "icons/moon-active.png" : "icons/moon-muted.png"
                        }
                    }
                }
                ProfileButton {
                    objectName: "profileButton"
                    Layout.preferredWidth: root.narrow ? 36 : 44 * root.uiScale
                    Layout.preferredHeight: root.narrow ? 36 : 44 * root.uiScale
                    palette.placeholderText: "#89978b"
                    palette.buttonText: "#b7c3b5"
                    palette.mid: "#344138"
                    palette.highlight: "#24332a"
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
                anchors.leftMargin: root.narrow ? 16 : 28 * root.uiScale
                anchors.rightMargin: root.narrow ? 16 : 28 * root.uiScale
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
                    implicitWidth: root.narrow ? 76 : 123 * root.uiScale
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
            Item {
                Layout.fillWidth: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.maximumWidth: 1600
                Layout.leftMargin: root.narrow ? 16 : 30 * root.uiScale
                Layout.rightMargin: root.narrow ? 16 : 30 * root.uiScale
                Layout.topMargin: 0
                Layout.bottomMargin: 12
                spacing: 12
                RowLayout {
                    visible: root.selected !== "" || root.showingSaved
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    ForumButton {
                        text: "← Threads"
                        onClicked: {
                            root.leaveThread();
                            root.showingSaved = false;
                        }
                    }
                    Text {
                        text: root.showingSaved ? "Saved threads" : root.boardName(root.current ? root.current.board : root.board)
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
                                height: threadContents.implicitHeight + (root.narrow ? 30 : 32 * root.uiScale)
                                color: rowHover.hovered ? theme.alternate : "transparent"
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
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 1
                                    color: theme.border
                                }
                                RowLayout {
                                    id: threadContents
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.topMargin: 16 * root.uiScale
                                    spacing: root.narrow ? 12 : 28 * root.uiScale
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        Layout.preferredWidth: 0
                                        Layout.maximumWidth: Math.max(150, threadContents.width - (root.narrow ? 86 : 280 * root.uiScale))
                                        spacing: 5 * root.uiScale
                                        Text {
                                            Layout.fillWidth: true
                                            text: row.modelData.title
                                            textFormat: Text.PlainText
                                            font.family: "Liberation Serif"
                                            font.pixelSize: root.narrow ? 22 : 25 * root.uiScale
                                            color: root.darkTheme ? "#e8e4d8" : theme.text
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "/" + row.modelData.board + "/  ·  by " + root.displayAuthor(row.modelData) + "  ·  #" + root.shortId(row.modelData.id) + "  ·  " + root.activityAge(row.modelData.created) + (row.modelData.status === "queued" ? "  ·  Pending" : row.modelData.status === "failed" ? "  ·  Retry pending" : row.modelData.status === "sending" ? "  ·  Sending…" : "")
                                            textFormat: Text.PlainText
                                            color: theme.muted
                                            font.family: "Adwaita Sans"
                                            font.pixelSize: root.narrow ? 11 : 14 * root.uiScale
                                            wrapMode: Text.Wrap
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.maximumWidth: root.narrow ? 10000 : 850 * root.uiScale
                                            text: row.modelData.body
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
                                            property var replyPosts: root.replies(row.modelData.id)
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
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: parent.parent.latestReply ? root.displayAuthor(parent.parent.latestReply) + "  #" + root.shortId(parent.parent.latestReply.id) + "  ·  " + root.activityAge(parent.parent.latestReply.created) : ""
                                                    textFormat: Text.PlainText
                                                    elide: Text.ElideRight
                                                    color: theme.accent
                                                    font.family: "Adwaita Sans"
                                                    font.pixelSize: root.narrow ? 11 : 14 * root.uiScale
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
                                    ColumnLayout {
                                        visible: !root.narrow
                                        Layout.minimumWidth: 170 * root.uiScale
                                        Layout.maximumWidth: 170 * root.uiScale
                                        Layout.alignment: Qt.AlignTop
                                        Layout.topMargin: 10
                                        spacing: 6
                                        Text {
                                            text: row.modelData.replyCount + (row.modelData.replyCount === 1 ? " reply" : " replies")
                                            color: theme.text
                                            font.family: "Adwaita Sans"
                                            font.pixelSize: 14 * root.uiScale
                                        }
                                        Text {
                                            text: "Last activity"
                                            color: theme.muted
                                            font.family: "Adwaita Sans"
                                            font.pixelSize: 14 * root.uiScale
                                        }
                                        Text {
                                            text: root.activityAge(row.modelData.lastActivity || row.modelData.created)
                                            color: theme.muted
                                            font.family: "Adwaita Sans"
                                            font.pixelSize: 14 * root.uiScale
                                        }
                                    }
                                    ForumButton {
                                        objectName: "reply-" + row.modelData.id
                                        Layout.alignment: Qt.AlignTop
                                        Layout.topMargin: 12
                                        implicitWidth: root.narrow ? 72 : 82 * root.uiScale
                                        implicitHeight: 40
                                        text: "Reply"
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                        onClicked: {
                                            root.openThread(row.modelData.id);
                                            root.beginReply();
                                        }
                                    }
                                }
                            }
                        }
                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 40, 460)
                            visible: root.visibleThreads.length === 0
                            spacing: 14
                            Text {
                                font.family: "Adwaita Sans"
                                text: root.searchText ? "No matching discussions." : root.showingSaved ? "Good threads are worth keeping." : "A good forum starts with a question."
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: 25
                                font.weight: Font.DemiBold
                                color: theme.text
                            }
                            Text {
                                font.family: "Adwaita Sans"
                                text: root.searchText ? "Try another phrase or change boards." : root.showingSaved ? "Save a thread from its discussion page to find it here." : "What are you working on? What do you disagree with? What would you like to understand better?"
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
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: threadTitle.implicitHeight + 22
                            color: "transparent"
                            radius: 4
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 11
                                Text {
                                    id: threadTitle
                                    font.family: "Liberation Serif"
                                    Layout.fillWidth: true
                                    text: root.current ? root.current.title : forum.refreshing ? "Loading discussion…" : "Thread not found"
                                    wrapMode: Text.Wrap
                                    font.pixelSize: root.narrow ? 25 : 34
                                    font.weight: Font.DemiBold
                                    color: theme.text
                                    textFormat: Text.PlainText
                                }
                                ForumButton {
                                    text: forum.state.saved.indexOf(root.selected) >= 0 ? "★ Saved" : "☆ Save"
                                    onClicked: forum.mutate({
                                        op: "bookmark",
                                        id: root.selected
                                    })
                                }
                            }
                        }
                        ListView {
                            id: postsView
                            objectName: "postsView"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 6
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar {}
                            model: root.current && forum.state.view === "thread" && forum.state.threadId === root.selected ? [root.current].concat(root.replies(root.selected)) : []
                            delegate: Rectangle {
                                id: post
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                height: postColumn.implicitHeight + 24
                                color: "transparent"
                                radius: 0
                                border.width: 0
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 1
                                    color: theme.border
                                }
                                ColumnLayout {
                                    id: postColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 12
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            font.family: "Adwaita Sans"
                                            text: root.displayAuthor(post.modelData)
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            color: theme.accent
                                            textFormat: Text.PlainText
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: 180
                                        }
                                        Text {
                                            font.family: "Adwaita Sans"
                                            text: post.index === 0 ? "OP" : ""
                                            font.pixelSize: 10
                                            color: theme.quote
                                        }
                                        Text {
                                            font.family: "Adwaita Sans"
                                            text: ">>" + root.shortId(post.modelData.id)
                                            font.pixelSize: 11
                                            color: theme.quote
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            font.family: "Adwaita Sans"
                                            text: root.age(post.modelData.created)
                                            font.pixelSize: 11
                                            color: theme.muted
                                        }
                                        ForumButton {
                                            text: "Quote"
                                            flat: true
                                            implicitHeight: 30
                                            implicitWidth: 65
                                            onClicked: root.quote(post.modelData)
                                        }
                                    }
                                    TextArea {
                                        Layout.fillWidth: true
                                        text: post.modelData.body
                                        readOnly: true
                                        selectByMouse: true
                                        wrapMode: TextEdit.Wrap
                                        textFormat: TextEdit.PlainText
                                        font.pixelSize: 15
                                        Layout.maximumWidth: 780
                                        color: theme.text
                                        padding: 0
                                        background: null
                                    }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 12
                                        Repeater {
                                            model: post.modelData.attachments || []
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
                                    Text {
                                        font.family: "Adwaita Sans"
                                        Layout.fillWidth: true
                                        text: root.statusLabel(post.modelData.status) + (post.modelData.error ? " · " + post.modelData.error : "")
                                        wrapMode: Text.Wrap
                                        font.pixelSize: 10
                                        color: post.modelData.status === "failed" ? theme.error : theme.muted
                                        textFormat: Text.PlainText
                                    }
                                }
                            }
                        }
                        ForumButton {
                            objectName: "beginReplyButton"
                            visible: !root.replyExpanded
                            Layout.fillWidth: true
                            text: replyInput.text.trim() ? "Continue your draft…" : "Write a reply…"
                            onClicked: root.beginReply()
                        }
                        Rectangle {
                            visible: root.replyExpanded
                            Layout.fillWidth: true
                            Layout.preferredHeight: replyBox.implicitHeight + 20
                            color: theme.surface
                            radius: 4
                            border.color: theme.border
                            ColumnLayout {
                                id: replyBox
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 7
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        font.family: "Adwaita Sans"
                                        Layout.fillWidth: true
                                        text: "Your reply"
                                        font.pixelSize: 12
                                        color: theme.muted
                                    }
                                    ForumButton {
                                        text: "Collapse"
                                        flat: true
                                        implicitHeight: 28
                                        onClicked: {
                                            root.saveReplyDraft();
                                            root.replyExpanded = false;
                                        }
                                    }
                                }
                                TextArea {
                                    id: replyInput
                                    objectName: "replyInput"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 64
                                    placeholderText: "Add a thought. Ask a follow-up. Challenge an idea."
                                    wrapMode: TextEdit.Wrap
                                    font.pixelSize: 14
                                    selectByMouse: true
                                    onTextChanged: replyDraftTimer.restart()
                                    Accessible.name: "Reply text"
                                }
                                AttachmentPickerRow {
                                    ink: theme.text
                                    muted: theme.muted
                                    Layout.fillWidth: true
                                    files: root.replyAttachments
                                    onAddRequested: {
                                        root.attachmentTarget = root.selected;
                                        attachmentPicker.open();
                                    }
                                    onRemoveRequested: function (index) {
                                        var f = root.replyAttachments.slice();
                                        f.splice(index, 1);
                                        root.replyAttachments = f;
                                        root.saveReplyDraft();
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    ForumButton {
                                        text: forum.state.mode === "anonymous" ? "Anonymous" : forum.state.mode === "uid" ? "Unique ID" : forum.activeAlias()
                                        onClicked: identityDialog.open()
                                    }
                                    Text {
                                        font.family: "Adwaita Sans"
                                        Layout.fillWidth: true
                                        text: (root.replyAttachments.length && !forum.state.storageEndpoint) || (root.current && root.current.status === "local") ? "Local only · not published" : "Saved locally · public when sent"
                                        font.pixelSize: 10
                                        color: theme.muted
                                        wrapMode: Text.Wrap
                                    }
                                    ForumButton {
                                        text: forum.posting ? "Uploading…" : (root.replyAttachments.length && !forum.state.storageEndpoint) || (root.current && root.current.status === "local") ? "Save reply" : forum.connection === "online" ? "Post reply →" : "Queue reply →"
                                        primary: true
                                        enabled: forum.ready && !forum.posting && replyInput.text.trim().length > 0 && replyInput.text.length <= 12000
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
                                                    root.replyExpanded = false;
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
                RowLayout {
                    visible: true
                    Layout.fillWidth: true
                    ForumButton {
                        objectName: "savedTab"
                        text: "Saved"
                        flat: true
                        implicitHeight: 28
                        onClicked: {
                            root.goBoard("all");
                            root.showingSaved = true;
                        }
                    }
                    ForumButton {
                        objectName: "networkStatus"
                        text: forum.connection === "online" ? "● Connected" : "○ Offline"
                        flat: true
                        implicitHeight: 28
                        onClicked: networkDialog.open()
                        Accessible.name: "Network and delivery settings"
                    }
                    Text {
                        font.family: "Adwaita Sans"
                        Layout.fillWidth: true
                        text: forum.notice || (forum.connection === "online" ? "" : "Pending posts are saved until connected")
                        elide: Text.ElideRight
                        font.pixelSize: 11
                        color: theme.muted
                    }
                    Text {
                        font.family: "Adwaita Sans"
                        text: forum.ready ? "Saved on this device" : "Connecting…"
                        font.pixelSize: 10
                        color: theme.muted
                    }
                }
            }
            Item {
                Layout.fillWidth: true
            }
        }
    }
    Shortcut {
        sequence: StandardKey.Find
        enabled: !composeDialog.visible && !identityDialog.visible && !networkDialog.visible
        onActivated: {
            root.leaveThread();
            (root.narrow ? compactSearch : headerSearch).forceActiveFocus();
        }
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
        contentItem: ColumnLayout {
            spacing: 12
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
            ForumField {
                id: titleInput
                objectName: "titleInput"
                Layout.fillWidth: true
                placeholderText: "A question, an idea, a work in progress…"
                maximumLength: 160
                font.pixelSize: 15
                selectByMouse: true
                onTextChanged: newDraftTimer.restart()
                Accessible.name: "Thread title"
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 200
                TextArea {
                    id: bodyInput
                    objectName: "bodyInput"
                    placeholderText: "What is the context? What would you like others to weigh in on?"
                    wrapMode: TextEdit.Wrap
                    font.pixelSize: 14
                    selectByMouse: true
                    onTextChanged: newDraftTimer.restart()
                    Accessible.name: "Thread message"
                }
            }
            Text {
                font.family: "Adwaita Sans"
                text: bodyInput.length + " / 12000 · Draft stored on this device"
                font.pixelSize: 11
                color: bodyInput.length > 12000 ? theme.error : theme.muted
            }
            AttachmentPickerRow {
                ink: theme.text
                muted: theme.muted
                Layout.fillWidth: true
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
            RowLayout {
                Layout.fillWidth: true
                ForumButton {
                    text: forum.state.mode === "anonymous" ? "Anonymous" : forum.activeAlias()
                    onClicked: identityDialog.open()
                }
                Item {
                    Layout.fillWidth: true
                }
                ForumButton {
                    text: "Keep draft"
                    onClicked: {
                        root.saveNewDraft();
                        composeDialog.close();
                    }
                }
                ForumButton {
                    text: forum.posting ? "Uploading…" : root.newAttachments.length && !forum.state.storageEndpoint ? "Save locally" : forum.connection === "online" ? "Publish thread" : "Queue thread"
                    primary: true
                    enabled: forum.ready && !forum.posting && titleInput.text.trim().length > 0 && bodyInput.text.trim().length > 0 && bodyInput.length <= 12000
                    onClicked: {
                        newDraftTimer.stop();
                        if (forum.posting) return;
                        forum.savePost("", root.newBoard, titleInput.text, bodyInput.text, function (r) {
                            composeDialog.submitted = true;
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
        contentItem: ColumnLayout {
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
                text: forum.error || "PNG or JPEG · up to 8 MB. Saved on this device for this identity."
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
            Text {
                font.family: "Adwaita Sans"
                Layout.fillWidth: true
                text: "Keys remain in your local database. Aliases are not unique: use the public ID to verify continuity. Identity rotation does not conceal network metadata."
                wrapMode: Text.Wrap
                font.pixelSize: 11
                color: theme.muted
            }
            ForumButton {
                text: "Done"
                Layout.alignment: Qt.AlignRight
                onClicked: identityDialog.close()
            }
        }
    }
    ForumDialog {
        id: networkDialog
        objectName: "networkDialog"
        palette: root.palette
        background: Rectangle {
            color: theme.surface
            border.color: theme.border
            radius: 10
        }
        title: "Network & delivery"
        property bool advanced: false
        modal: true
        anchors.centerIn: parent
        width: Math.min(root.width - 30, 520)
        contentItem: ColumnLayout {
            spacing: 14
            Text {
                font.family: "Adwaita Sans"
                text: forum.connectionDetail
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: 14
                color: theme.accent
            }
            Text {
                font.family: "Adwaita Sans"
                Layout.fillWidth: true
                text: "Your posts are saved on this device before sending. Delivery confirmation means the network acknowledged the post."
                wrapMode: Text.Wrap
                font.pixelSize: 12
                color: theme.muted
            }
            Text {
                font.family: "Adwaita Sans"
                Layout.fillWidth: true
                text: "Connect using Basecamp’s Delivery node, or start one here. Going offline keeps your drafts and queued posts."
                wrapMode: Text.Wrap
                font.pixelSize: 12
                color: theme.muted
            }
            Text {
                font.family: "Adwaita Sans"
                Layout.fillWidth: true
                visible: networkDialog.advanced
                text: "Content topic: " + forum.contentTopic
                wrapMode: Text.Wrap
                font.pixelSize: 11
                color: theme.muted
            }
            ForumField {
                id: storageEndpoint
                objectName: "storageEndpoint"
                visible: networkDialog.advanced
                Layout.fillWidth: true
                placeholderText: "Local Logos Storage URL (optional)"
                text: forum.state.storageEndpoint || ""
                Accessible.name: "Local Logos Storage endpoint"
            }
            ForumButton {
                visible: networkDialog.advanced
                text: "Save media connection"
                onClicked: forum.mutate({op: "settings", storageEndpoint: storageEndpoint.text})
            }
            Text {
                visible: networkDialog.advanced
                Layout.fillWidth: true
                text: "Use http://127.0.0.1:PORT/api/storage/v1 for your own Storage node. New attachments are published when you post. Without this connection, attachments stay local."
                wrapMode: Text.Wrap
                color: theme.muted
                font.pixelSize: 11
            }
            ForumField {
                id: storePeer
                visible: networkDialog.advanced
                Layout.fillWidth: true
                placeholderText: "Store peer multiaddress (optional)"
                text: forum.state.historyPeer || ""
                Accessible.name: "Store peer"
            }
            ForumButton {
                visible: networkDialog.advanced
                text: "Recover next history page"
                enabled: storePeer.text.length > 0 && typeof logos !== "undefined"
                onClicked: forum.loadHistory(storePeer.text)
            }
            Text {
                font.family: "Adwaita Sans"
                Layout.fillWidth: true
                visible: networkDialog.advanced
                text: "Manual recovery is paginated and resumes from its saved cursor. Invalid signatures and duplicate messages are rejected. Peer retention determines how far back history is available."
                wrapMode: Text.Wrap
                font.pixelSize: 11
                color: theme.muted
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8
                ForumButton {
                    Layout.fillWidth: true
                    text: forum.connection === "online" ? "Go offline" : "Connect"
                    primary: true
                    enabled: typeof logos !== "undefined"
                    onClicked: forum.connection === "online" ? forum.disconnect() : forum.connectNetwork()
                }
                ForumButton {
                    Layout.fillWidth: true
                    text: "Start node"
                    enabled: forum.connection !== "online" && typeof logos !== "undefined"
                    onClicked: forum.startNode()
                }
                ForumButton {
                    Layout.fillWidth: true
                    text: "Retry failed posts"
                    onClicked: forum.mutate({
                        op: "retry"
                    })
                }
                ForumButton {
                    Layout.fillWidth: true
                    text: networkDialog.advanced ? "Hide advanced settings" : "Advanced"
                    onClicked: networkDialog.advanced = !networkDialog.advanced
                }
            }
        }
    }
}
