pragma Singleton
import QtQuick
QtObject {
  property var calls: []
  property string quickStartMode: ""
  function notifyServer(command, data) { calls = calls.concat([{command: command, data: data}]); }
}
