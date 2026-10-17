// Native Spine is unrelated to invitations; this stub only permits offline room type loading.
import QtQuick
Item {
  property url atlasFile
  property url skeletonDataFile
  property real skeletonScale: 1
  property int spineVersion: 0
  property bool premultipliedAlapha: false
  property bool loadConcluded: true
  property bool loadOk: false
  signal skeletonLoadFinished(bool ok)
}
