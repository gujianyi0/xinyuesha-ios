# SPDX-License-Identifier: GPL-3.0-or-later
"""Pointer regression for the actual generated room background shortcut."""
import os, re, json, tempfile, time
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
from PySide6.QtCore import QUrl, Qt, QPoint, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickItem, QQuickWindow
from PySide6.QtTest import QTest

source = (Path(os.environ['FK_TEST_UI']) / 'LunarLtk/Pages/RoomBase.qml').read_text(encoding='utf8')
shortcut = re.search(r'  MouseArea \{\n    objectName: "roomBackgroundChatShortcut".*?\n  \}', source, re.S)
assert shortcut, 'generated RoomBase contains the shortcut'
logs = []
qInstallMessageHandler(lambda kind, context, message: logs.append(message))
app = QGuiApplication([])
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / 'Main.qml').write_text('''import QtQuick
Window {id:win;width:800;height:500;visible:true
 property int chats:0;property int cardClicks:0;property int buttonClicks:0
 QtObject {id:Mediator;function notify(sender,command){win.chats++;}}
 QtObject {id:Command;property int IWantToChat:1}
 Item {id:roomScene;anchors.fill:parent
  property var infoPopup:({visible:false});property var popupItem:null;property var agItem:null
  REPLACE_SHORTCUT
  Rectangle {x:20;y:20;width:120;height:150;color:"tan"
   MouseArea {anchors.fill:parent;onClicked:win.cardClicks++;onDoubleClicked:win.cardClicks++;}}
  Rectangle {x:20;y:400;width:120;height:50;color:"green"
   MouseArea {anchors.fill:parent;onClicked:win.buttonClicks++;onDoubleClicked:win.buttonClicks++;}}
 }
 property alias scene:roomScene
}'''.replace('REPLACE_SHORTCUT', shortcut.group()), encoding='utf8')
    # QML IDs must start lowercase; the actual names are imported singletons.
    text = (root / 'Main.qml').read_text(encoding='utf8').replace('id:Mediator', 'id:mediator').replace('id:Command', 'id:command').replace('Mediator.notify', 'mediator.notify').replace('Command.IWantToChat', 'command.chatAction').replace('property int IWantToChat:1', 'property int chatAction:1')
    (root / 'Main.qml').write_text(text, encoding='utf8')
    engine = QQmlApplicationEngine(); engine.load(QUrl.fromLocalFile(str(root / 'Main.qml')))
    assert engine.rootObjects(), logs
    window = engine.rootObjects()[0]
    def pump():
        until = time.monotonic() + .08
        while time.monotonic() < until: app.processEvents(); time.sleep(.005)
    def double(x, y):
        QTest.mouseDClick(window, Qt.LeftButton, Qt.NoModifier, QPoint(x, y)); pump()
        QTest.mouseRelease(window, Qt.LeftButton, Qt.NoModifier, QPoint(x, y)); pump()
    pump()
    QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier, QPoint(400, 250)); pump()
    assert window.property('chats') == 0, 'single click does not open chat'
    double(400, 250)
    assert window.property('chats') == 1, 'background double-click opens existing chat action'
    double(60, 60); double(60, 425)
    assert window.property('chats') == 1, 'cards and buttons retain their pointer handling'
    assert window.property('cardClicks') > 0 and window.property('buttonClicks') > 0
    scene = window.property('scene')
    for name, value in [('infoPopup', {'visible': True}), ('popupItem', {'active': True}), ('agItem', {'active': True})]:
        scene.setProperty(name, value); pump(); double(400, 250)
        assert window.property('chats') == 1, 'skill/AG/info popup blocks the shortcut'
        scene.setProperty(name, {'visible': False} if name == 'infoPopup' else None); pump()
    QTest.mousePress(window, Qt.LeftButton, Qt.NoModifier, QPoint(400, 250))
    QTest.mouseMove(window, QPoint(450, 320), 60)
    QTest.mouseRelease(window, Qt.LeftButton, Qt.NoModifier, QPoint(450, 320)); pump()
    assert window.property('chats') == 1, 'dragging does not open chat'
    errors = [line for line in logs if any(s in line for s in ['TypeError', 'ReferenceError', 'SyntaxError', 'Binding loop', 'Cannot assign', 'Unable to assign'])]
    assert not errors, errors
    print(json.dumps({'chats': window.property('chats'), 'cardClicks': window.property('cardClicks'), 'buttonClicks': window.property('buttonClicks'), 'errors': errors}))
    window.close(); engine.deleteLater(); app.processEvents()
