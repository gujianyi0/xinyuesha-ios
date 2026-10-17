pragma Singleton
import QtQuick
QtObject {
  property var toasts: []
  function showToast(text) { toasts = toasts.concat([text]); }
}
