import QtQuick
import QtTest
import "../../forum/qml/QuoteText.js" as QuoteText
import "../../forum/qml" as Forum

TestCase {
    name: "QuotePresentation"
    width: 600
    height: 600
    visible: true
    when: windowShown
    Component { id: bodyComponent; Forum.PostBody { width: 500 } }
    Component { id: referenceComponent; Forum.QuoteReference {} }
    Component {
        id: delayedController
        QtObject {
            property var completions: []
            function call(command, done, failed) { completions.push(done); }
        }
    }
    function test_staleReferencePreviewCannotReplaceNewTarget() {
        var controller = createTemporaryObject(delayedController, this);
        var link = createTemporaryObject(referenceComponent, this, {controller: controller, text: ">>c17dc191"});
        link.resolve(false);
        link.text = ">>abcdef12";
        link.resolve(false);
        compare(controller.completions.length, 2);
        controller.completions[1]({state: "found", post: {id: "abcdef12", body: "New target", author: "reader", mode: "alias", title: "", attachments: []}, threadAvailable: true});
        controller.completions[0]({state: "found", post: {id: "c17dc191", body: "Old target"}, threadAvailable: true});
        compare(link.targetPost.id, "abcdef12");
        link.text = ">>12345678";
        link.resolve(false);
        var completion = controller.completions[2];
        link.destroy();
        wait(0);
        completion({state: "missing"}); // A closed page ignores its delayed lookup.
    }

    function test_parse_data() {
        return [
            {tag: "plain", body: "\n  Plain <b>text</b>\n> not a post quote\n", expected: [
                {reference: "", text: "\n  Plain <b>text</b>\n> not a post quote\n"}]},
            {tag: "quoted-reply", body: ">>c17dc191\n> First line\n> \n> Last line\n\nMy reply", expected: [
                {reference: ">>c17dc191", text: "First line\n\nLast line"}, {reference: "", text: "My reply"}]},
            {tag: "multiple-and-nested", body: "Before\n\n>>c17dc191\n> >>abcdef12\n> > Older quote\nBetween\n>>abcdef12\n> Another quote\n\nAfter", expected: [
                {reference: "", text: "Before"}, {reference: ">>c17dc191", text: ">>abcdef12\n> Older quote"},
                {reference: "", text: "Between"}, {reference: ">>abcdef12", text: "Another quote"}, {reference: "", text: "After"}]},
            {tag: "malformed-reference", body: ">>not-a-post\n> Keep this literal\n>>c17dc191\nNo quote follows", expected: [
                {reference: "", text: ">>not-a-post\n> Keep this literal\n>>c17dc191\nNo quote follows"}]},
            {tag: "windows-lines", body: ">>C17DC191\r\n> Quoted\r\n\r\nReply", expected: [
                {reference: ">>C17DC191", text: "Quoted"}, {reference: "", text: "Reply"}]}
        ];
    }
    function test_parse(data) {
        compare(JSON.stringify(QuoteText.segments(data.body)), JSON.stringify(data.expected));
    }
    function test_selectablePlainTextAndNarrowWrapping() {
        var raw = ">>c17dc191\n> <b>This is literal text</b>, with a longer excerpt that must wrap inside the quote.\n\nMy reply stays outside the inset.";
        var body = createTemporaryObject(bodyComponent, this, {text: raw});
        verify(body !== null);
        verify(waitForRendering(body));
        var quote = findChild(body, "body-segment-0");
        var label = findChild(body, "quote-reference-0");
        var quoted = findChild(body, "body-text-0");
        var reply = findChild(body, "body-segment-1");
        compare(label.text, ">>c17dc191");
        compare(label.contentItem.truncated, false);
        compare(quoted.textFormat, TextEdit.PlainText);
        quoted.select(0, 3);
        compare(quoted.selectedText, "<b>");
        verify(quote.quoted && !reply.quoted);
        var wideHeight = quote.height;
        body.width = 240;
        tryVerify(function() { return quote.height > wideHeight; });
        verify(quoted.mapToItem(body, quoted.width, 0).x <= body.width);
        verify(reply.y >= quote.y + quote.height + 16);
        compare(body.text, raw);
    }
}
