import QtQuick
import qs.Commons
import qs.Commons as Commons

Canvas {
  id: root

  property var values: []
  property color lineColor: Commons.Color.accent
  property color fillColor: Util.alpha(lineColor, 0.12)
  property real ceiling: 0

  antialiasing: true

  onValuesChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onFillColorChanged: requestPaint()
  onCeilingChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var context = getContext("2d")
    context.clearRect(0, 0, width, height)

    var points = Array.isArray(values) ? values : []
    if (points.length === 0 || width <= 0 || height <= 0) return

    var maximum = Number(ceiling)
    if (!isFinite(maximum) || maximum <= 0) {
      maximum = 1
      for (var i = 0; i < points.length; i++) {
        var candidate = Number(points[i])
        if (isFinite(candidate)) maximum = Math.max(maximum, candidate)
      }
      maximum *= 1.12
    }

    var step = points.length > 1 ? width / (points.length - 1) : width
    var yFor = function(value) {
      var normalized = Math.max(0, Math.min(1, Number(value || 0) / maximum))
      return height - normalized * Math.max(1, height - Style.spacing.hairline)
    }

    context.beginPath()
    context.moveTo(0, height)
    for (var j = 0; j < points.length; j++) {
      var x = points.length > 1 ? j * step : width
      context.lineTo(x, yFor(points[j]))
    }
    context.lineTo(width, height)
    context.closePath()
    context.fillStyle = fillColor
    context.fill()

    context.beginPath()
    for (var k = 0; k < points.length; k++) {
      var lineX = points.length > 1 ? k * step : width
      var lineY = yFor(points[k])
      if (k === 0) context.moveTo(lineX, lineY)
      else context.lineTo(lineX, lineY)
    }
    context.strokeStyle = lineColor
    context.lineWidth = Math.max(1, Style.spaceReal(1.25))
    context.lineJoin = "round"
    context.lineCap = "round"
    context.stroke()
  }
}
