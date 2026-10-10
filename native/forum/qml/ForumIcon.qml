import QtQuick

Canvas {
    id: icon
    property string name: "general"
    property color ink: "#b9c8bb"
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
        if (name === "privacy") {
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
