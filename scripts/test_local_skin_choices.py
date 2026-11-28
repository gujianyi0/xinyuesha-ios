"""Local display integration; deterministic skin registry, not native animation QA."""
import argparse,json,os,shutil,tempfile
from pathlib import Path
os.environ.update(QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QT_QUICK_CONTROLS_STYLE='Basic')
from PySide6.QtCore import QUrl,QMetaObject,Q_RETURN_ARG,Q_ARG,QEventLoop,QTimer,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m));app=QGuiApplication([])
with tempfile.TemporaryDirectory(dir=a.output) as tmp:
 d=Path(tmp)
 def put(name,value):
  path=d/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(value,'utf8')
 put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Config','Lua','Backend']))
 put('Fk/Backend.qml','pragma Singleton\nimport QtQuick\nQtObject{property string saved:"{}";property bool fail:false;function readFileFromAssets(p){return saved;}function writeFileToAssets(p,s){if(fail)return false;saved=s;return true;}}')
 put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property var enabledSkins:({});property bool banChangeSkin:false;property string saved:"";function saveConf(){saved=JSON.stringify(enabledSkins);}}')
 put('Fk/Lua.qml',r'''pragma Singleton
import QtQuick
QtObject{
 property bool ready:true
 function ev(s){
  if(s.includes("skin_packages"))return ["lingju"];
  if(!ready)return {};
  const match=s.match(/Fk.generals\[("[^"]+")\]/);if(!match)return null;
  const general=JSON.parse(match[1]);
  if(!["lingju","ol__lingju","mobile__lingju","international__lingju","god__lingju","liubei"].includes(general))return null;
  return {trueName:general.split("__").pop(),kingdom:general.startsWith("god__")?"god":"qun"};
 }
 function tr(s){return s;}
}''')
 put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n')
 put('LunarLtk/Ltk.qml','pragma Singleton\nimport QtQuick\nQtObject{function getSkinByName(g,n){return g==="lingju"&&["portraitA","portraitB"].includes(n)?{name:n}:null;}function getSkinNamesByGeneral(g){return g==="lingju"?["portraitA","portraitB"]:[];}}')
 shutil.copyfile(a.payload/'card-counter/LocalSkinChoices.qml',d/'LocalSkinChoices.qml')
 put('PhotoFixture.qml','''import QtQuick
Item{id:photo;width:120;height:180;property string general:"lingju";property string deputyGeneral:"";property string serverSkin:"serverDefault";property alias area:area
 Item{id:area;property var skelData:({});property string general:photo.general;property string skinName:photo.serverSkin}}
''')
 put('Main.qml','''import QtQuick
import Fk
Window{id:win;width:800;height:500;visible:true
 Item{id:owner;property var currentScene:scene;function openNaishaSettings(){}}
 Item{id:scene;anchors.fill:parent;property var dataModel:({players:[{photoItem:self},{photoItem:enemy},{photoItem:variant},{photoItem:god},{photoItem:other}]})
  PhotoFixture{id:self}PhotoFixture{id:enemy}PhotoFixture{id:variant;general:"ol__lingju"}PhotoFixture{id:god;general:"god__lingju"}PhotoFixture{id:other;general:"liubei"}
 }
 LocalSkinChoices{id:manager;owner:owner}
 function select(g,name){const next=Object.assign({},Config.enabledSkins);next[g]=name;Config.enabledSkins=next;manager.sync();}
 function ready(value){Lua.ready=value;manager.sync();}
 function variantId(g){variant.general=g;manager.sync();}
 function ban(value){Config.banChangeSkin=value;manager.sync();}
 function serverSkin(value){enemy.serverSkin=value;}
 function clear(){Config.enabledSkins=({});manager.localChoices=({});manager.sync();}
 function leave(){owner.currentScene=null;}
 function enter(){owner.currentScene=scene;}
 function open(){manager.openSettings();}
 function pickerSelect(){manager.saveSelection(false);}
 function serverPreferences(){Config.enabledSkins=({lingju:"portraitB"});manager.sync();}
 function reloadSaved(){manager.localChoices=({});manager.readChoices();manager.sync();}
 function failSave(){Backend.fail=true;}
 function snapshot(){manager.sync();return JSON.stringify({skins:[self,enemy,variant,god,other].map(p=>({general:p.general,renderGeneral:p.area.general,skin:p.area.skinName})),choices:Config.enabledSkins,saved:Config.saved,targets:manager.targets,available:manager.availableSkins});}
}''')
 engine=QQmlApplicationEngine();engine.addImportPath(str(d));engine.load(QUrl.fromLocalFile(str(d/'Main.qml')));assert engine.rootObjects(),logs;win=engine.rootObjects()[0]
 def pump(ms=70):loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
 def act(name,*args):QMetaObject.invokeMethod(win,name,*[Q_ARG('QVariant',x) for x in args]);pump()
 def state():return json.loads(QMetaObject.invokeMethod(win,'snapshot',Q_RETURN_ARG('QVariant')))
 pump();assert all(row['skin']=='serverDefault' for row in state()['skins'])
 act('ready',False);act('select','lingju','portraitA');s=state();assert s['skins'][1]['skin']=='portraitA' and s['skins'][2]['skin']=='serverDefault',s
 act('ready',True);s=state();assert [r['skin'] for r in s['skins']]==['portraitA']*3+['serverDefault']*2,s
 assert s['skins'][2]['general']=='ol__lingju' and s['skins'][2]['renderGeneral']=='lingju',s
 for general in ['mobile__lingju','international__lingju','ol__lingju']:
  act('variantId',general);assert state()['skins'][2]['skin']=='portraitA'
 act('select','ol__lingju','portraitB');assert state()['skins'][2]['skin']=='portraitB'
 act('select','ol__lingju','');assert state()['skins'][2]['skin']=='serverDefault'
 act('serverSkin','newServerSkin');assert state()['skins'][1]['skin']=='portraitA','Saved choice must survive server broadcasts'
 act('ban',True);assert state()['skins'][1]['skin']=='newServerSkin'
 act('ban',False);assert state()['skins'][1]['skin']=='portraitA'
 act('open');s=state();assert len(s['available'])==2 and any(t['id']=='ol__lingju' for t in s['targets']),s
 act('pickerSelect');assert json.loads(state()['saved'])['lingju']=='portraitA'
 act('serverPreferences');assert state()['skins'][1]['skin']=='portraitA','Server preference broadcasts must not erase local choices'
 act('reloadSaved');assert state()['skins'][1]['skin']=='portraitA','Local file must restore the saved choice'
 before=state()['choices'];act('failSave');act('pickerSelect');assert state()['choices']==before
 win.grabWindow().save(str(a.output/'in-game-picker.png'))
 act('leave');pump();assert state()['skins'][1]['skin']=='newServerSkin'
 act('enter');pump();assert state()['skins'][1]['skin']=='portraitA'
 act('clear');assert state()['skins'][1]['skin']=='newServerSkin' and state()['skins'][2]['renderGeneral']=='ol__lingju'
 errors=[m for m in logs if any(s in m for s in ['TypeError','ReferenceError','Binding loop','Cannot assign','Unable to assign','non-existent'])];assert not errors,errors
 report=dict(passed=True,sameNameEnemyInherits=True,taggedVariants=['OL','mobile','international'],stockBindingsRestored=True,explicitVersionChoice=True,transientMissingRegistryRecovers=True,normalDivineSeparated=True,inGamePickerSaved=True,savedFileReloadsAndSurvivesServerPreferenceUpdates=True,failedSavePreservesChoice=True,fixtureRegistry=True,physicalDevice=False)
 (a.output/'result.json').write_text(json.dumps(report,indent=2),'utf8');print(json.dumps(report));win.close()
