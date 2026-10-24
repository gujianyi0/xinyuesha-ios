# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise native-overlay QML: repeated quit, photo routing and note preedit."""
import json, os, re, tempfile
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
os.environ.setdefault('QT_QUICK_BACKEND','software')
from PySide6.QtCore import QObject,QUrl,QMetaObject,Qt,Q_RETURN_ARG,QEventLoop,QTimer,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication,QInputMethodEvent
from PySide6.QtQml import QQmlApplicationEngine

ui=Path(os.environ['FK_TEST_UI']);logs=[]
qInstallMessageHandler(lambda kind,ctx,msg:logs.append(msg));app=QGuiApplication([])
room=(ui/'Fk/Pages/Common/RoomPage.qml').read_text(encoding='utf8')
quit_dialog=re.search(r'  Dialog \{\s*id: quitDialog.*?\n  \}',room,re.S)
assert quit_dialog and 'offlineQuitConfirmation' in quit_dialog.group(), 'adapted quit dialog missing'
dialogs = {m.group(1):m.group() for m in re.finditer(r'  Dialog \{\s*id: (\w+).*?\n  \}',room,re.S)}
expected = ['quitDialog','surrenderDialog']
for name in ['surrenderNegotiationDialog','surrenderNegotiationRequestDialog']:
 if 'id: '+name in room: expected.append(name)
assert all(name in dialogs and 'parent: Overlay.overlay' in dialogs[name] for name in expected), expected
controls='\n'.join(dialogs[name] for name in expected)
helpers='\n'.join('function open_'+n+'(){'+n+'.open();} function cancel_'+n+'(){'+n+'.reject();} function accept_'+n+'(){'+n+'.accept();}' for n in expected)

note=(ui/'Fk/Pages/Replay/ReplayRecordingFile.qml').read_text(encoding='utf8')
note_prefix=re.search(r'TextField \{\s*id: commentEdit.*?(?=\s*enabled: list.currentIndex)',note,re.S)
assert note_prefix and 'replayNoteField' in note_prefix.group(), 'adapted note input missing'
bg=(ui/'Fk/Pages/Lobby/BGSetting.qml').read_text(encoding='utf8')
routes=re.findall(r'onClicked: \{(.*?fdialog\.open\(\);)\s*\}',bg,re.S)
assert len(routes)==4, routes
with tempfile.TemporaryDirectory() as temp:
 base=Path(temp)
 def put(name,s):
  p=base/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf8')
 put('Fk/qmldir','module Fk\nsingleton Lua 1.0 Lua.qml\nsingleton Cpp 1.0 Cpp.qml\nsingleton Backend 1.0 Backend.qml\n')
 put('Fk/Lua.qml','pragma Singleton\nimport QtQuick\nQtObject {property bool allowed:true;function tr(s){return s;}function checkSurrenderAvailable(){return [{passed:allowed}];}function checkSurrenderNegotiationAvailable(){return [{passed:allowed}];}}')
 put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject {property var packets:[];function notifyServer(c,d){packets=packets.concat([{command:c,data:d}]);}}')
 put('Fk/Backend.qml','pragma Singleton\nimport QtQuick\nQtObject {property var selected:[];function pickBackground(k){selected=selected.concat([k]);}}')
 buttons='\n'.join('Button {id:bg'+str(i)+';onClicked:{'+s+'}}' for i,s in enumerate(routes))
 put('Main.qml','''import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Fk
Window {
 id:root;property string surrenderNegotiationId:"test-negotiation"
 width:700;height:400;visible:true
 QUIT
 HELPERS
 function denySurrender(){Lua.allowed=false;}
 function allowSurrender(){Lua.allowed=true;}
 function clearPackets(){Cpp.packets=[];}
 ColumnLayout {width:500;NOTE_PREFIX }
 QtObject {id:fdialog;property string configKey;property var nameFilters;property int opened:0;function open(){opened++;}}
 Row {y:100;BUTTONS}
 function openQuit(){quitDialog.open();}
 function cancelQuit(){quitDialog.reject();}
 function acceptQuit(){quitDialog.accept();}
 function chooseBackgrounds(){bg0.clicked();bg1.clicked();bg2.clicked();bg3.clicked();}
 function focusNote(){commentEdit.forceActiveFocus();}
 function state(){return JSON.stringify({visible:quitDialog.visible,packets:Cpp.packets,selected:Backend.selected,fileDialogs:fdialog.opened,noteText:commentEdit.text,preedit:commentEdit.preeditText,placeholder:commentEdit.children.find(c=>c.text==="Note").visible,cursorY:commentEdit.cursorRectangle.y,cursorHeight:commentEdit.cursorRectangle.height,height:commentEdit.height});}
}'''.replace('QUIT',controls).replace('HELPERS',helpers).replace('NOTE_PREFIX',note_prefix.group()+'}').replace('BUTTONS',buttons))
 engine=QQmlApplicationEngine();engine.addImportPath(str(base));engine.load(QUrl.fromLocalFile(str(base/'Main.qml')))
 assert engine.rootObjects(),logs
 win=engine.rootObjects()[0]
 def pump():
  loop=QEventLoop();QTimer.singleShot(300,loop.quit);loop.exec()
 def call(name):QMetaObject.invokeMethod(win,name,Qt.DirectConnection);pump()
 def state():return json.loads(QMetaObject.invokeMethod(win,'state',Qt.DirectConnection,Q_RETURN_ARG('QVariant')))
 call('openQuit');assert state()['visible'] and state()['packets']==[]
 call('cancelQuit');assert not state()['visible'] and state()['packets']==[]
 call('openQuit');assert state()['visible'] and state()['packets']==[]
 call('acceptQuit');assert state()['packets']==[{'command':'QuitRoom','data':'[]'}]
 # Every current-core confirmation must reopen, preserve permission checks,
 # and emit exactly the original command on accept/cancel.
 call('clearPackets')
 for name in expected[1:]:
  call('open_'+name);call('cancel_'+name)
  expected_packets=[]
  if name=='surrenderNegotiationRequestDialog':
   expected_packets=[{'command':'PushRequest','data':'reply_surrender_negotiation,test-negotiation,false'}]
  assert state()['packets']==expected_packets,(name,state())
  call('clearPackets')
  if name!='surrenderNegotiationRequestDialog':
   call('denySurrender');call('open_'+name);call('accept_'+name)
   assert state()['packets']==[],(name,state())
   call('allowSurrender');call('open_'+name);call('accept_'+name)
   command='surrender' if name=='surrenderDialog' else 'surrender_negotiation'
   assert state()['packets']==[{'command':'PushRequest','data':command+',true'}],(name,state())
   call('clearPackets')
 call('chooseBackgrounds');s=state();assert s['selected']==['lobbyBg','roomBg','ladyImg'] and s['fileDialogs']==1,s
 call('focusNote');assert state()['placeholder'] is True
 app.sendEvent(app.focusObject(),QInputMethodEvent('beizhu',[]));pump();s=state()
 assert s['preedit']=='beizhu' and not s['placeholder'],s
 assert s['cursorY']>=0 and s['cursorY']+s['cursorHeight']<=s['height'],s
 committed=QInputMethodEvent();committed.setCommitString('备注');app.sendEvent(app.focusObject(),committed);pump()
 s=state();assert s['noteText']=='备注' and not s['placeholder'] and not s['preedit'],s
 errors=[m for m in logs if any(k in m for k in ['TypeError','ReferenceError','SyntaxError','Cannot assign','Unable to assign','Binding loop'])]
 assert not errors,errors
 print(json.dumps({'quit_cancel_reopen_accept':True,'dialog_callbacks_checked':expected,'photo_routes':s['selected'],'music_file_dialog':s['fileDialogs'],'note_preedit_and_cursor':True,'errors':errors},ensure_ascii=False))
 win.close();engine.deleteLater();app.processEvents()
