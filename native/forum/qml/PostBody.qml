pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "QuoteText.js" as QuoteText

ColumnLayout {
    id: body
    property string text: ""
    property color ink: "#ededed"
    property color quoteInk: "#cccccc"
    property color muted: "#a3a3a3"
    property color quoteSurface: "#222222"
    property color quoteOutline: "#2b2b2b"
    property var controller
    signal postActivated(var post)
    readonly property var segments: QuoteText.segments(text)
    spacing: 16

    Repeater {
        model: body.segments
        Rectangle {
            id: segment
            required property var modelData
            required property int index
            readonly property bool quoted: modelData.reference.length > 0
            objectName: "body-segment-" + index
            Layout.fillWidth: true
            implicitHeight: content.implicitHeight + (quoted ? 28 : 0)
            radius: 8
            color: quoted ? body.quoteSurface : "transparent"
            border.width: quoted ? 1 : 0
            border.color: body.quoteOutline

            ColumnLayout {
                id: content
                x: segment.quoted ? 16 : 0
                y: segment.quoted ? 14 : 0
                width: parent.width - 2 * x
                spacing: 8
                QuoteReference {
                    objectName: "quote-reference-" + segment.index
                    visible: segment.quoted
                    Layout.maximumWidth: content.width
                    text: segment.modelData.reference
                    controller: body.controller
                    previewWidth: Math.min(420, body.width)
                    ink: body.ink
                    muted: body.muted
                    surface: body.quoteSurface
                    outline: body.quoteOutline
                    onPostActivated: function(post) { body.postActivated(post); }
                }
                TextArea {
                    objectName: "body-text-" + segment.index
                    Layout.fillWidth: true
                    text: segment.modelData.text
                    textFormat: TextEdit.PlainText
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    font.family: "Adwaita Sans"
                    font.pixelSize: 15
                    color: segment.quoted ? body.quoteInk : body.ink
                    padding: 0
                    background: null
                }
            }
        }
    }
}
