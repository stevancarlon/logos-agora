import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: control
    property var files: []
    required property var controller
    property bool uploadAvailable: false
    property color ink: "#ededed"
    property color muted: "#a3a3a3"
    signal addRequested
    signal removeRequested(int index)
    spacing: 4
    RowLayout {
        ForumButton {
            text: "+ Attach file"
            palette.buttonText: hovered || visualFocus ? control.ink : control.muted
            flat: true
            enabled: control.files.length < 4
            onClicked: control.addRequested()
        }
        Text {
            Layout.fillWidth: true
            visible: !control.files.length
            text: "Images, video or PDF · up to 64 MB"
            color: control.muted
            font.pixelSize: 10
            wrapMode: Text.Wrap
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 12
        Repeater {
            model: control.files
            Column {
                id: selectedFile
                required property var modelData
                required property int index
                width: Math.min(180, parent.width)
                spacing: 4
                AttachmentCard {
                    objectName: "draft-attachment-" + selectedFile.modelData.id
                    width: parent.width
                    previewOnly: true
                    attachment: selectedFile.modelData
                    controller: control.controller
                    ink: control.ink
                    muted: control.muted
                    ForumButton {
                        id: removeAttachment
                        objectName: "remove-draft-attachment-" + selectedFile.modelData.id
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 4
                        width: 40
                        height: 40
                        z: 2
                        padding: 0
                        Accessible.name: "Remove attachment " + selectedFile.modelData.name
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: "Remove attachment"
                        contentItem: Item {
                            ForumIcon {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                name: "trash"
                                ink: "#ededed"
                            }
                        }
                        background: Item {
                            Rectangle {
                                anchors.centerIn: parent
                                width: 28
                                height: 28
                                radius: 7
                                color: removeAttachment.hovered || removeAttachment.down ? "#333333" : "#181818"
                                opacity: 0.95
                                border.width: removeAttachment.visualFocus ? 1 : 0
                                border.color: "#ededed"
                                Behavior on color { ColorAnimation { duration: 110 } }
                            }
                        }
                        onClicked: control.removeRequested(selectedFile.index)
                    }
                }
                Text {
                    width: parent.width
                    text: selectedFile.modelData.name
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    color: control.ink
                    font.pixelSize: 11
                }
            }
        }
    }
}
