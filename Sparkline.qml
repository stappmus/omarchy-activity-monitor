import QtQuick
import qs.Commons
import qs.Commons as Commons

Canvas {
  id: root

  property var values: []
  property var times: []
  readonly property real span: times.length > 1 ? times[times.length - 1] - times[0] : 0
  readonly property int hoverIndex: {
    if (!hover.hovered || width <= 0 || !times.length || times.length !== values.length) return -1
    const target = times[0] + span * hover.point.position.x / width
    let index = 0
    while (index + 1 < times.length && target > (times[index] + times[index + 1]) / 2) ++index
    return index
  }
  function xFor(i) {
    return span > 0 ? width * (times[i] - times[0]) / span : width
  }
  HoverHandler { id: hover }
  Rectangle {
    visible: root.hoverIndex >= 0
    x: visible ? Math.min(root.width - width, root.xFor(root.hoverIndex)) : 0
    width: 1
    height: root.height
    color: root.lineColor
  }
  onTimesChanged: requestPaint()
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
    if (points.length !== times.length || points.length === 0 || width <= 0 || height <= 0) return

    var maximum = Number(ceiling)
    if (!isFinite(maximum) || maximum <= 0) {
      maximum = 1
      for (var i = 0; i < points.length; i++) {
        var candidate = Number(points[i])
        if (isFinite(candidate)) maximum = Math.max(maximum, candidate)
      }
      maximum *= 1.12
    }

    var yFor = function(value) {
      var normalized = Math.max(0, Math.min(1, Number(value || 0) / maximum))
      return height - normalized * Math.max(1, height - Style.spacing.hairline)
    }

    context.beginPath()
    context.moveTo(0, height)
    for (var j = 0; j < points.length; j++) {
      var x = xFor(j)
      context.lineTo(x, yFor(points[j]))
    }
    context.lineTo(width, height)
    context.closePath()
    context.fillStyle = fillColor
    context.fill()

    context.beginPath()
    for (var k = 0; k < points.length; k++) {
      var lineX = xFor(k)
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
