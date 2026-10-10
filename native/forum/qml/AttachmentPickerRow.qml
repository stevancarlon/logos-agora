import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: control
    property var files: []
    property color ink: "#e6e8df"
    property color muted: "#a7b2a9"
    signal addRequested
    signal removeRequested(int index)
    spacing: 4
    RowLayout {
        ForumButton {
            text: "+ Attach file"
            flat: true
            enabled: control.files.length < 4
            onClicked: control.addRequested()
        }
        Text {
            Layout.fillWidth: true
            text: control.files.length ? "Attachments stay on this device" : "Images, video or PDF · up to 64 MB"
            color: control.muted
            font.pixelSize: 10
            wrapMode: Text.Wrap
        }
    }
    Repeater {
        model: control.files
        RowLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: modelData.name
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: control.ink
                font.pixelSize: 11
            }
            ForumButton {
                text: "Remove"
                flat: true
                implicitHeight: 28
                onClicked: control.removeRequested(parent.index)
            }
        }
    }
}
