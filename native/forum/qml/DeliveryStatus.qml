import QtQuick
import QtQuick.Controls.Basic

Item {
    id: control
    property string status: ""
    property string error: ""
    property string publishingDetail: ""
    property color ink: "#a3a3a3"
    property color surface: "#181818"
    property color outline: "#333333"
    property color textColor: "#ededed"
    property real phase: 0
    readonly property string symbol: status === "sent" ? "check" : status === "sending" ? "sending" : status === "failed" ? "warning" : status === "local" ? "device" : "clock"
    readonly property string description: status === "sent" ? "Delivered to network"
        : status === "sending" ? "Sending to network…"
        : (status === "queued" || status === "failed") && publishingDetail ? publishingDetail
        : status === "queued" ? "Queued · waiting to send"
        : status === "failed" ? "Not sent · retry pending" + (error ? "\n" + error : "")
        : status === "local" ? "Only on this device · not published" : ""
    visible: ["queued", "sending", "sent", "failed", "local"].indexOf(status) >= 0
    implicitWidth: 20
    implicitHeight: 20
    Accessible.role: Accessible.StaticText
    Accessible.name: description
    HoverHandler { id: statusHover }
    ToolTip {
        id: statusTip
        visible: statusHover.hovered
        delay: 350
        text: control.description
        width: Math.min(320, implicitWidth)
        x: (control.width - width) / 2
        padding: 10
        contentItem: Text {
            text: statusTip.text
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.family: "Adwaita Sans"
            font.pixelSize: 12
            color: control.textColor
        }
        background: Rectangle {
            color: control.surface
            border.color: control.outline
            radius: 6
        }
    }
    ForumIcon {
        anchors.centerIn: parent
        width: 15
        height: 15
        name: control.symbol
        ink: control.ink
        rotation: control.status === "sending" ? control.phase : 0
        Accessible.ignored: true
    }
    NumberAnimation on phase {
        running: control.visible && control.status === "sending"
        from: 0
        to: 360
        duration: 1200
        loops: Animation.Infinite
    }
}
