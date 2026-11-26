// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls

// Keep routing/lifetime in the scene, but draw above room and Quick dialogs.
Item {
  id: surface
  required property Item sourceItem
  parent: sourceItem.Overlay.overlay || sourceItem
  z: 100000 + sourceItem.z
  enabled: false
  visible: sourceItem.visible
  width: sourceItem.width
  height: sourceItem.height
  property matrix4x4 sceneMatrix: Qt.matrix4x4()
  transform: Matrix4x4 { matrix: surface.sceneMatrix }

  function syncGeometry() {
    if (!parent || !sourceItem) return;
    const p = sourceItem.mapToItem(parent, 0, 0);
    const u = sourceItem.mapToItem(parent, 1, 0);
    const v = sourceItem.mapToItem(parent, 0, 1);
    sceneMatrix = Qt.matrix4x4(u.x-p.x, v.x-p.x, 0, p.x,
                              u.y-p.y, v.y-p.y, 0, p.y,
                              0, 0, 1, 0, 0, 0, 0, 1);
    let alpha = 1;
    for (let item=sourceItem; item && item!==parent; item=item.parent)
      alpha *= item.opacity;
    opacity = alpha;
  }
  // Ancestor transforms are not dependencies of mapToItem. Only track the
  // short-lived effect; include viewport scaling/rotation without moving UI.
  FrameAnimation { running: surface.visible; onTriggered: surface.syncGeometry() }
  onParentChanged: syncGeometry()
  onWidthChanged: syncGeometry()
  onHeightChanged: syncGeometry()
  Component.onCompleted: syncGeometry()
}
