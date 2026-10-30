import QtQuick

Canvas {
    id: icon
    property string name: "general"
    property color ink: "#bcbcbc"
    implicitWidth: 24
    implicitHeight: 24
    onNameChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var c = getContext("2d");
        c.reset();
        c.scale(width / 24, height / 24);
        c.strokeStyle = ink;
        c.lineWidth = 1.6;
        c.lineCap = "round";
        c.lineJoin = "round";
        function line(points) {
            c.beginPath();
            c.moveTo(points[0], points[1]);
            for (var i = 2; i < points.length; i += 2)
                c.lineTo(points[i], points[i + 1]);
            c.stroke();
        }
        function circle(x, y, r) {
            c.beginPath();
            c.arc(x, y, r, 0, Math.PI * 2);
            c.stroke();
        }
        if (name === "clock") {
            circle(12, 12, 9);
            line([12, 6, 12, 12, 16, 14]);
        } else if (name === "check") {
            line([4, 12, 9, 17, 20, 6]);
        } else if (name === "sending") {
            c.beginPath();
            c.arc(12, 12, 9, -Math.PI / 2, Math.PI * 0.85);
            c.stroke();
        } else if (name === "warning") {
            circle(12, 12, 9);
            line([12, 6, 12, 13]);
            line([12, 17, 12, 17.2]);
        } else if (name === "device") {
            line([6, 3, 18, 3, 18, 21, 6, 21, 6, 3]);
            line([10, 17, 14, 17]);
        } else if (name === "minus") {
            line([5, 12, 19, 12]);
        } else if (name === "trash") {
            line([4, 6, 20, 6]);
            line([9, 6, 9, 3, 15, 3, 15, 6]);
            line([6, 6, 7, 21, 17, 21, 18, 6]);
            line([10, 10, 10, 17]);
            line([14, 10, 14, 17]);
        } else if (name === "close") {
            line([7, 7, 17, 17]); line([17, 7, 7, 17]);
        } else if (name === "chevron-down") {
            line([6, 9, 12, 15, 18, 9]);
        } else if (name === "attach") {
            c.beginPath();
            c.moveTo(9, 12);
            c.lineTo(14, 7);
            c.bezierCurveTo(17, 4, 21, 8, 18, 11);
            c.lineTo(10, 19);
            c.bezierCurveTo(5, 24, -1, 18, 4, 13);
            c.lineTo(13, 4);
            c.bezierCurveTo(19, -2, 27, 6, 21, 12);
            c.lineTo(13, 20);
            c.stroke();
        } else if (name === "reply") {
            line([9, 5, 3, 11, 9, 17]);
            c.beginPath();
            c.moveTo(3, 11);
            c.lineTo(13, 11);
            c.bezierCurveTo(18, 11, 21, 14, 21, 19);
            c.stroke();
        } else if (name === "back") {
            line([14, 5, 7, 12, 14, 19]);
            line([7, 12, 21, 12]);
        } else if (name === "sun") {
            circle(12, 12, 4);
            line([12, 2, 12, 4]); line([12, 20, 12, 22]);
            line([2, 12, 4, 12]); line([20, 12, 22, 12]);
            line([5, 5, 6.5, 6.5]); line([17.5, 17.5, 19, 19]);
            line([5, 19, 6.5, 17.5]); line([17.5, 6.5, 19, 5]);
        } else if (name === "moon") {
            c.beginPath();
            c.arc(12, 12, 8.5, 0.25, 4.45);
            c.bezierCurveTo(6, 14, 15, 18, 20.2, 14.1);
            c.stroke();
        } else if (name === "privacy") {
            c.strokeRect(5.5, 10, 13, 11);
            c.beginPath();
            c.moveTo(8, 10);
            c.lineTo(8, 6.5);
            c.bezierCurveTo(8, 1, 16, 1, 16, 6.5);
            c.lineTo(16, 10);
            c.stroke();
            line([12, 14, 12, 17]);
        } else if (name === "saved") {
            line([6, 3, 18, 3, 18, 22, 12, 17, 6, 22, 6, 3]);
        } else if (name === "governance") {
            line([2, 8, 12, 3, 22, 8, 2, 8]);
            line([3, 21, 21, 21]);
            line([5, 18, 19, 18]);
            for (var x = 6; x <= 18; x += 4)
                line([x, 10, x, 17]);
        } else if (name === "circles") {
            circle(9, 7, 3);
            circle(18, 8, 2.4);
            c.beginPath();
            c.moveTo(2, 21);
            c.lineTo(2, 18);
            c.bezierCurveTo(2, 11, 16, 11, 16, 18);
            c.lineTo(16, 21);
            c.closePath();
            c.stroke();
            c.beginPath();
            c.moveTo(17, 14);
            c.bezierCurveTo(22, 14, 23, 17, 22, 21);
            c.lineTo(19, 21);
            c.stroke();
        } else if (name === "building") {
            line([14, 3, 11, 6, 12, 10, 16, 11, 20, 7]);
            c.beginPath();
            c.moveTo(14, 3);
            c.bezierCurveTo(5, 1, 5, 8, 7, 11);
            c.lineTo(2, 17);
            c.bezierCurveTo(0, 20, 4, 23, 6, 20);
            c.lineTo(12, 14);
            c.bezierCurveTo(19, 17, 23, 11, 20, 7);
            c.stroke();
        } else if (name === "search") {
            circle(10, 10, 7);
            line([15, 15, 22, 22]);
        } else if (name === "profile") {
            circle(12, 7, 4);
            c.beginPath();
            c.moveTo(4, 22);
            c.bezierCurveTo(4, 11, 20, 11, 20, 22);
            c.stroke();
        } else {
            c.beginPath();
            c.moveTo(5, 18);
            c.bezierCurveTo(-2, 11, 3, 3, 12, 3);
            c.bezierCurveTo(25, 3, 25, 19, 12, 19);
            c.lineTo(8, 18);
            c.lineTo(4, 22);
            c.lineTo(5, 18);
            c.stroke();
            if (name === "discussions") {
                line([7, 10, 8, 10]);
                line([11, 10, 12, 10]);
                line([15, 10, 16, 10]);
            }
        }
    }
}
