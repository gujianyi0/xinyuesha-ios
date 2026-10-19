// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

Item {
  id: viewport
  objectName: "counterViewport"
  anchors.fill: parent
  readonly property real logicalWidth: Math.max(1200, 540 * width / Math.max(height, 1))
  readonly property real logicalHeight: Math.max(540, 1200 * height / Math.max(width, 1))
  readonly property real contentScale: Math.max(width / logicalWidth, height / logicalHeight)
  default property alias contentData: canvas.data
  readonly property alias contentItem: canvas
  property Item canvasItem: Item {
    id: canvas
    objectName: "counterViewportCanvas"
    parent: viewport
    anchors.centerIn: parent
    anchors.alignWhenCentered: false
    width: viewport.logicalWidth
    height: viewport.logicalHeight
    scale: viewport.contentScale
  }
}
