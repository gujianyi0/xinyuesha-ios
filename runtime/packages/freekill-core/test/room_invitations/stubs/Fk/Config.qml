pragma Singleton
import QtQuick
QtObject {
  property bool titleServerSupported: false
  property string serverAddr: "139.196.92.71"
  property string lastLoginServer: ""
  function saveConf() {}
  function resetTitleSession() {}
  function requestTitleProfile() {}
  property bool consoleStartRequested: false
  property bool replaying: false
  property bool observing: false
  property bool hideUseless: false
  property bool rotateTableCard: false
  property bool autoTarget: false
  property bool noSelfNullification: false
  property bool enableSuperDrag: false
  property bool hideScreenName: false
  property bool banChangeSkin: false
}
