import QtQuick
import "../Theme.js" as Theme

Item {
  id: root

  property string phase: "idle" // "idle" | "focus" | "paused" | "rest"
  property real progress: 0.0
  property color inkColor: "#ffffff"
  property int glyphSize: 16

  implicitWidth: glyphSize
  implicitHeight: glyphSize
  width: glyphSize
  height: glyphSize

  onPhaseChanged: canvas.requestPaint()
  onProgressChanged: canvas.requestPaint()
  onInkColorChanged: canvas.requestPaint()
  onGlyphSizeChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var s = Math.min(width, height) / 16.0
      ctx.save()
      ctx.scale(s, s)

      var col = root.inkColor
      var strokeHex = Qt.rgba(col.r, col.g, col.b, 1.0)
      var faintHex = Qt.rgba(col.r, col.g, col.b, 0.28)

      function roundedRectPath(x, y, w, h, r) {
        ctx.beginPath()
        ctx.moveTo(x + w / 2, y)
        ctx.arcTo(x + w, y, x + w, y + h, r)
        ctx.arcTo(x + w, y + h, x, y + h, r)
        ctx.arcTo(x, y + h, x, y, r)
        ctx.arcTo(x, y, x + w, y, r)
        ctx.closePath()
      }

      if (root.phase === "rest") {
        roundedRectPath(1.5, 1.5, 13.0, 13.0, 2.9)
        ctx.strokeStyle = strokeHex
        ctx.lineWidth = 1.5
        ctx.stroke()
      } else if (root.phase === "focus" || root.phase === "paused") {
        roundedRectPath(1.5, 1.5, 13.0, 13.0, 2.9)
        ctx.strokeStyle = faintHex
        ctx.lineWidth = 1.5
        ctx.stroke()

        // Clockwise perimeter stroke from top-center (8.0, 1.5)
        var p = Math.max(0.0, Math.min(1.0, Number(root.progress) || 0))
        if (p > 0.002) {
          var r = 2.9
          var straight = 13.0 - 2 * r
          var corner = 0.5 * Math.PI * r
          var totalLen = 4 * straight + 4 * corner
          var rem = p * totalLen

          ctx.beginPath()
          ctx.moveTo(8.0, 1.5)

          function segLine(x0, y0, x1, y1, len) {
            if (rem <= 0) return
            var take = Math.min(rem, len)
            var k = take / len
            ctx.lineTo(x0 + (x1 - x0) * k, y0 + (y1 - y0) * k)
            rem -= take
          }

          function segArc(cx, cy, startAng, sweepPos) {
            if (rem <= 0) return
            var take = Math.min(rem, corner)
            var dAng = (take / corner) * (Math.PI * 0.5) * (sweepPos ? 1 : -1)
            ctx.arc(cx, cy, r, startAng, startAng + dAng, !sweepPos)
            rem -= take
          }

          // Top-half right -> TR corner -> right -> BR corner -> bottom -> BL corner -> left -> TL corner -> top-half left
          segLine(8.0, 1.5, 14.5 - r, 1.5, straight * 0.5)
          segArc(14.5 - r, 1.5 + r, -Math.PI * 0.5, true)
          segLine(14.5, 1.5 + r, 14.5, 14.5 - r, straight)
          segArc(14.5 - r, 14.5 - r, 0, true)
          segLine(14.5 - r, 14.5, 1.5 + r, 14.5, straight)
          segArc(1.5 + r, 14.5 - r, Math.PI * 0.5, true)
          segLine(1.5, 14.5 - r, 1.5, 1.5 + r, straight)
          segArc(1.5 + r, 1.5 + r, Math.PI, true)
          segLine(1.5 + r, 1.5, 8.0, 1.5, straight * 0.5)

          ctx.strokeStyle = strokeHex
          ctx.lineWidth = 1.65
          ctx.lineCap = "round"
          ctx.lineJoin = "round"
          ctx.stroke()
        }
      } else {
        // idle: the app icon's nested rounded squares fading inward around a dot;
        // fewer rings than the icon's four so they stay apart at small sizes
        var rings = Math.min(width, height) >= 18
          ? [[0.0, 1.0, 1.3], [2.1, 0.75, 1.15], [4.0, 0.52, 1.1]]
          : [[0.0, 1.0, 1.3], [2.7, 0.62, 1.2]]
        for (var i = 0; i < rings.length; i++) {
          var side = 13.0 - 2 * rings[i][0]
          roundedRectPath(1.5 + rings[i][0], 1.5 + rings[i][0], side, side, side * 0.22)
          ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, rings[i][1])
          ctx.lineWidth = rings[i][2]
          ctx.stroke()
        }

        ctx.beginPath()
        ctx.arc(8.0, 8.0, 1.25, 0, Math.PI * 2)
        ctx.fillStyle = strokeHex
        ctx.fill()
      }

      ctx.restore()
    }
  }
}
