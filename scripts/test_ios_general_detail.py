# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise marked-general descriptions with the real popup and rich text."""
import os, json, tempfile, shutil, time
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
from PySide6.QtCore import QUrl, QMetaObject, Q_RETURN_ARG, Qt, QPoint, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickItem, QQuickWindow
from PySide6.QtTest import QTest

ui = Path(os.environ['FK_TEST_UI'])
logs = []
qInstallMessageHandler(lambda kind, context, message: logs.append(message))
app = QGuiApplication([])
with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    def put(name, value):
        path = base / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value, encoding='utf8')
    put('Fk/qmldir', 'module Fk\nsingleton Config 1.0 Config.qml\nsingleton Lua 1.0 Lua.qml\n')
    put('Fk/Config.qml', 'pragma Singleton\nimport QtQuick\nQtObject {property real winScale:0.7}')
    put('Fk/Lua.qml', 'pragma Singleton\nimport QtQuick\nQtObject {function tr(s){return s;}}')
    put('LunarLtk/qmldir', 'module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n')
    put('LunarLtk/Ltk.qml', '''pragma Singleton
import QtQuick
QtObject {function getGeneralDetail(n){return {kingdom:"吴",hp:3,maxHp:3,headnote:"",endnote:"",companions:[],skill:[{name:"玄注",description:"转换技，每回合限一次，阳：你可以将一张牌交给其他角色。".repeat(80)}]};}}''')
    put('LunarLtk/Components/qmldir', 'module LunarLtk.Components\nDescriptionText 1.0 DescriptionText.qml\n')
    for source, target in [('Fk/Widgets/PopupItem.qml', 'PopupItem.qml'),
                           ('LunarLtk/Pages/InfoPopups/GeneralDetail.qml', 'GeneralDetail.qml'),
                           ('LunarLtk/Components/DescriptionText.qml', 'LunarLtk/Components/DescriptionText.qml')]:
        shutil.copyfile(ui / source, base / target)
    put('Main.qml', '''import QtQuick
Window {id:win;width:1100;height:600;visible:true
 PopupItem {id:popup;width:650;height:400;x:20;y:20}
 function setup(){popup.setSourceComponent(Qt.createComponent("GeneralDetail.qml"),{generals:["陆凯","访客"]});popup.open();}
 function state(){return popup.item;}
 function resizePanel(w){popup.width=w;}
}''')
    engine = QQmlApplicationEngine()
    engine.addImportPath(str(base))
    engine.load(QUrl.fromLocalFile(str(base / 'Main.qml')))
    assert engine.rootObjects(), logs
    window = engine.rootObjects()[0]
    def pump():
        end = time.monotonic() + .15
        while time.monotonic() < end:
            app.processEvents(); time.sleep(.005)
    QMetaObject.invokeMethod(window, 'setup', Qt.DirectConnection); pump()
    root = QMetaObject.invokeMethod(window, 'state', Qt.DirectConnection, Q_RETURN_ARG('QVariant'))
    if hasattr(root, 'toQObject'): root = root.toQObject()
    def items(item):
        result = [item]
        for child in item.childItems(): result.extend(items(child))
        return result
    results = []
    for panel_width in [650, 400, 900]:
        # Resize the real popup to catch width bindings after orientation/scale changes.
        window.setWidth(panel_width + 50)
        from PySide6.QtCore import Q_ARG
        QMetaObject.invokeMethod(window, 'resizePanel', Qt.DirectConnection, Q_ARG('QVariant', panel_width))
        pump()
        description = next(item for item in items(root) if item.property('readOnly') is True and '玄注' in str(item.property('text')))
        results.append({'panel': panel_width, 'rootWidth': root.width(), 'textWidth': description.width(),
                        'textHeight': description.height(), 'scrollHeight': root.property('contentHeight'),
                        'contentWidth': root.property('contentWidth')})
        assert description.width() >= root.width() - 45, results
        assert abs(root.property('contentWidth') - root.width()) < 1, results
        assert root.property('contentHeight') > root.height(), results
        root.setProperty('contentY', 0); pump()
        QTest.mousePress(window, Qt.LeftButton, Qt.NoModifier, QPoint(200, 280))
        for y in range(260, 79, -20): QTest.mouseMove(window, QPoint(200, y), 16)
        QTest.mouseRelease(window, Qt.LeftButton, Qt.NoModifier, QPoint(200, 80)); pump()
        assert root.property('contentY') > 40, ('description drag must scroll', results, logs)
    errors = [line for line in logs if any(s in line for s in ['TypeError', 'ReferenceError', 'Binding loop', 'Cannot assign', 'Unable to assign'])]
    assert not errors, errors
    print(json.dumps({'geometry': results, 'errors': errors}, ensure_ascii=False))
    window.close(); engine.deleteLater(); app.processEvents()
