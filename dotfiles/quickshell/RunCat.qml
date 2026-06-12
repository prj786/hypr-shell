import QtQuick

// RunCat — a little running cat (à la the GNOME/macOS RunCat). Drawn procedurally
// (no sprite assets); its run speed tracks CPU load: faster when busy, a slow trot
// when light, curls up to sleep when idle. CPU/mem come from Globals (shared with
// the Control Center). Colour = Theme.fg.
Item {
    id: root
    width: 30; height: 20
    readonly property real cpu: Globals.cpuUsage
    readonly property bool sleeping: cpu < 0.04

    Canvas {
        id: cv
        anchors.fill: parent
        property int frame: 0
        property color col: Theme.fg
        onFrameChanged: requestPaint()
        onColChanged: requestPaint()
        Connections { target: root; function onSleepingChanged() { cv.requestPaint() } }
        Component.onCompleted: requestPaint()

        function oval(c, cx, cy, rx, ry) { c.save(); c.translate(cx, cy); c.scale(rx / ry, 1); c.beginPath(); c.arc(0, 0, ry, 0, 2 * Math.PI); c.fill(); c.restore() }

        onPaint: {
            var c = getContext("2d"); c.reset()
            c.fillStyle = col; c.strokeStyle = col; c.lineWidth = 2.2; c.lineCap = "round"; c.lineJoin = "round"
            if (root.sleeping) {
                cv.oval(c, 14, 13, 9, 5)                                             // curled body
                c.beginPath(); c.moveTo(8, 9); c.lineTo(9.5, 4.5); c.lineTo(12, 9); c.closePath(); c.fill()  // ear
                c.beginPath(); c.arc(8, 13, 2.6, 0, 2 * Math.PI); c.fill()            // tucked head
                c.lineWidth = 2.2; c.beginPath(); c.moveTo(22, 13); c.quadraticCurveTo(27, 9, 21, 8); c.stroke() // tail curl
                c.fillText("z", 24, 5); c.fillText("z", 27, 2)
                return
            }
            var t = root.frame / 6 * 2 * Math.PI
            // tail (back/left), swaying
            c.lineWidth = 2.2; c.beginPath(); c.moveTo(5, 11); c.quadraticCurveTo(1, 8 + 2.5 * Math.sin(t), 2, 3 + Math.sin(t)); c.stroke()
            // legs (behind body) — running gait
            c.lineWidth = 2; var legs = [[9, 0], [13, Math.PI], [19, Math.PI], [23, 0]]
            for (var i = 0; i < legs.length; i++) { var a = Math.sin(t + legs[i][1]); c.beginPath(); c.moveTo(legs[i][0], 14); c.lineTo(legs[i][0] + 3 * a, 19); c.stroke() }
            // body
            cv.oval(c, 13, 11, 9, 4.5)
            // head (front/right)
            c.beginPath(); c.arc(23, 9, 4, 0, 2 * Math.PI); c.fill()
            // ears
            c.beginPath(); c.moveTo(20, 6); c.lineTo(20.8, 1.8); c.lineTo(23, 5.5); c.closePath(); c.fill()
            c.beginPath(); c.moveTo(23, 5.2); c.lineTo(25.2, 1.8); c.lineTo(26, 6); c.closePath(); c.fill()
        }
    }

    Timer {
        running: !root.sleeping
        repeat: true
        interval: { var u = Math.max(0, Math.min(1, (root.cpu - 0.04) / 0.96)); return Math.max(45, Math.round(210 - u * 165)) }
        onTriggered: cv.frame = (cv.frame + 1) % 6
    }
}
