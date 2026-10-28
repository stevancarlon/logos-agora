import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Dialog {
    id: control
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 130 }
            NumberAnimation { property: "scale"; from: 0.98; to: 1; duration: 130; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 }
    }
    height: Math.min(implicitHeight, parent ? Math.max(160, parent.height - 32) : implicitHeight)
    padding: 22
    topPadding: 12
    font.family: "sans-serif"
    header: Item {
        implicitHeight: 62
        RowLayout {
            anchors.fill: parent
            spacing: 12
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 22
                text: control.title
                font.pixelSize: 21
                font.weight: Font.DemiBold
                color: control.palette.text
            }
            ForumButton {
                Layout.rightMargin: 14
                text: "×"
                font.pixelSize: 22
                implicitHeight: 40
                implicitWidth: 40
                flat: true
                Accessible.name: "Close dialog"
                onClicked: control.close()
            }
        }
    }
}
