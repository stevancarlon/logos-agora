import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: control
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
                implicitWidth: 32
                flat: true
                Accessible.name: "Close dialog"
                onClicked: control.close()
            }
        }
    }
}
