# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise shipped QML with a real Qt engine and deterministic game fixtures."""
import base64, hashlib, json, os, re, shutil, tempfile, time
from pathlib import Path
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Material")
from PySide6.QtCore import QUrl, QMetaObject, Qt, Q_RETURN_ARG, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
SOURCE = Path(__file__).resolve().parents[1] / "runtime"
UI = Path(os.environ.get("FK_TEST_UI", str(SOURCE)))
logs = []
qInstallMessageHandler(lambda kind, context, message: logs.append(message))
app = QGuiApplication([])
workspace = tempfile.TemporaryDirectory()
base = Path(workspace.name)
def put(name, value):
    p = base / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(value, encoding="utf-8")
put("Fk/qmldir", "module Fk\nsingleton Config 1.0 Config.qml\nsingleton Lua 1.0 Lua.qml\nsingleton Backend 1.0 Backend.qml\nsingleton Cpp 1.0 Cpp.qml\nsingleton SkinBank 1.0 SkinBank.qml\n")
put("Fk/Config.qml", 'pragma Singleton\nimport QtQuick\nQtObject {property real winScale:0.7;property string li2Name:"sans-serif";property string libianName:"sans-serif";property string roomBg:"default";property string lobbyBg:"default";function saveConf(){}}')
put("Fk/Cpp.qml", 'pragma Singleton\nimport QtQuick\nQtObject {property string os:"iOS";}')
put("Fk/Lua.qml", 'pragma Singleton\nimport QtQuick\nQtObject {function ev(t){return true;}function tr(t){return t;}}')
put("Fk/Backend.qml", 'pragma Singleton\nimport QtQuick\nQtObject {function readFileFromAssets(p){return "{}";}function writeFileToAssets(p,t){return true;}}')
put("Fk/SkinBank.qml", 'pragma Singleton\nimport QtQuick\nQtObject {property string limitSkillDir:"' + base.as_uri() + '/icons/";}')
for name in ("switch", "switch-yin", "limit", "limit-used"):
    p=base/"icons"/name;p.parent.mkdir(exist_ok=True)
    p.write_bytes(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
put("LunarLtk/qmldir", "module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n")
put("LunarLtk/Ltk.qml", '''pragma Singleton
import QtQuick
QtObject {
 property var roomScene:null
 function getSkillData(n){return {switchSkillName:n};}
 function getGeneralDetail(n){return {kingdom:"wei",hp:4,maxHp:4,mainMaxHp:0,deputyMaxHp:0,headnote:"",endnote:"",companions:[],skill:[{name:"test skill",description:"A visible skill description with wrapping text."}]};}
 function createCardModel(id, props){return {cardId:id};}
}
''')
put("LunarLtk/Components/qmldir", "module LunarLtk.Components\nDescriptionText 1.0 DescriptionText.qml\nCardItem 1.0 CardItem.qml\nBigGlowText 1.0 BigGlowText.qml\n")
put("LunarLtk/Components/DescriptionText.qml", 'import QtQuick\nText {textFormat:Text.RichText;wrapMode:Text.Wrap;font.pixelSize:18}')
put("LunarLtk/Components/CardItem.qml", 'import QtQuick\nRectangle {width:93;height:130;property bool autoBack;property var dataModel;}')
put("LunarLtk/Components/BigGlowText.qml", 'import QtQuick\nText {}')
put("Fk/Widgets/qmldir", "module Fk.Widgets\nTapHandler 1.0 TapHandler.qml\n")
shutil.copyfile(SOURCE / "Fk/Widgets/TapHandler.qml", base / "Fk/Widgets/TapHandler.qml")
for source, target in [("Fk/Widgets/PopupItem.qml","PopupItem.qml"), ("LunarLtk/Components/Photo/LimitSkillItem.qml","LimitSkillItem.qml"), ("LunarLtk/Components/Photo/LimitSkillArea.qml","LimitSkillArea.qml"), ("Fk/Components/Common/MetroButton.qml","MetroButton.qml"), ("LunarLtk/Pages/InfoPopups/GeneralDetail.qml","GeneralDetail.qml"), ("LunarLtk/Pages/InfoPopups/ViewPile.qml","ViewPile.qml")]:
    shutil.copyfile(UI / source, base / target)
shutil.copyfile(SOURCE / "card-counter/CounterHost.qml", base / "CounterHost.qml")
photo_source=(UI/"LunarLtk/Models/PhotoModel.qml").read_text(encoding="utf-8")
skill_method=re.search(r"  function updateLimitSkill\(skill, time\) \{.*?\n  \}",photo_source,re.S).group(0)
server_source=(UI/"Fk/Pages/Common/JoinServer.qml").read_text(encoding="utf-8")
version_expression=re.search(r'text: (delay \+ " ms " \+ [^\n]+)',server_source).group(1)
put("Main.qml", '''import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQml.WorkerScript
import Fk
Window {
 width:1000;height:500;visible:true
 property var authResult: null
 WorkerScript {id:worker;source:"AUTH_SOURCE";onMessage:function(message){authResult=message;}}
 Item {id:server;anchors.fill:parent; property var selectedServer:null;property string serverListUrl:"mock"
  RowLayout {id:row;width:470;height:70
   Rectangle {Layout.preferredWidth:56;Layout.preferredHeight:56}
   ColumnLayout {Layout.fillWidth:true
    Text {id:name;Layout.fillWidth:true;text:"新月杀主力服务器的完整名称";font.pixelSize:18}
    Text {id:version;Layout.fillWidth:true;property int delay:200;property string misMatchMsg:"<font color='green' size='4'><b>✓ v0.5.25+</b></font>";text:VERSION_EXPRESSION;textFormat:Text.RichText}
   }
   Text {id:online;text:"8/<font size='1'>607</font>";font.pixelSize:26}
  }
  Text {id:desc;y:90;width:180;text:"服务器信息应当完整展示，支持多行说明。服务器信息应当完整展示，支持多行说明。服务器信息应当完整展示，支持多行说明。";wrapMode:Text.WrapAnywhere;font.pixelSize:18}
 }
 Item {id:lobby;width:1000;property var roomModel:({});property int serverPlayerNum:1
  Button {id:exitButton;anchors.right:parent.right;text:"Exit Lobby";width:110;height:40;icon.name:"application-exit"}
  MetroButton {id:toggle;text:"🗨️➕";y:50}
 }
 Item {property string data:"a model payload"}
 CounterHost {id:host;settingsReady:true}
 PopupItem {id:popup;width:600;height:300;x:200;y:120}
 Component {id:content;Item {anchors.fill:parent;property alias label:label
   Text {id:label;text:"Skill details and visible teammate cards";font.pixelSize:18;color:"black"}
 }}
 QtObject {id:photo;property list<var> limitSkills:[]; SKILL_METHOD }
 LimitSkillArea {id:skillArea;skillModel:photo.limitSkills}
 LimitSkillItem {id:switchSkill;skillname:"switch_test";usedtimes:1}
 function setup(){host.refreshCompatibility();photo.updateLimitSkill("switch_test",0);popup.setSourceComponent(Qt.createComponent("GeneralDetail.qml"),{generals:["test"]});popup.open();worker.sendMessage({generation:1,server:"test:9527",username:"测试用户",password:"test-only-password"});}
 function changeSkill(){photo.updateLimitSkill("switch_test",1);}
 function skillState(){return String(skillArea.children[0].itemAt(0).children[0].source);}
 function generalHeight(){return popup.item.contentHeight;}
 function showCards(){popup.setSourceComponent(Qt.createComponent("ViewPile.qml"),{name:"hand_card",ids:[1,2,3]});}
 function cardCount(){return popup.item.children[1].count;}
 function changeToggle(){toggle.text="🗨️➖";}
 function inspect(){host.refreshCompatibility();return JSON.stringify({
   authResult:authResult,descriptionLines:desc.lineCount,descriptionLimit:desc.maximumLineCount,
   versionHeight:version.implicitHeight,versionWidth:version.implicitWidth,
   nameWidth:name.width,onlineWidth:online.width,
   popupWidth:popup.item.width,popupHeight:popup.item.height,
   switchSource:String(switchSkill.children[0].source),toggleText:toggle.text,
   toggleIcon:String(toggle.icon.source),exitContentX:exitButton.contentItem.x,
   exitContentWidth:exitButton.contentItem.width,exitWidth:exitButton.width
 });}
}
'''.replace("AUTH_SOURCE", (SOURCE / "card-counter/SocialAuth.js").as_uri()).replace("VERSION_EXPRESSION",version_expression).replace("SKILL_METHOD",skill_method))
engine = QQmlApplicationEngine(); engine.addImportPath(str(base))
engine.rootContext().setContextProperty("AppPath", QUrl.fromLocalFile(str(base)))
engine.load(QUrl.fromLocalFile(str(base / "Main.qml")))
assert engine.rootObjects(), logs
window = engine.rootObjects()[0]
def invoke(name):return QMetaObject.invokeMethod(window,name,Qt.DirectConnection,Q_RETURN_ARG("QVariant"))
QMetaObject.invokeMethod(window,"setup",Qt.DirectConnection)
def pump(seconds):
    end=time.monotonic()+seconds
    while time.monotonic()<end:app.processEvents();time.sleep(.01)
pump(.25)
yang=invoke("skillState")
QMetaObject.invokeMethod(window,"changeSkill",Qt.DirectConnection);pump(.1)
yin=invoke("skillState")
general_height=invoke("generalHeight")
QMetaObject.invokeMethod(window,"showCards",Qt.DirectConnection);pump(.25)
card_count=invoke("cardCount")
QMetaObject.invokeMethod(window,"changeToggle",Qt.DirectConnection);pump(.1)
deadline=time.monotonic()+90
while time.monotonic()<deadline:
    app.processEvents();time.sleep(.01)
    if window.property("authResult").toVariant() is not None:break
raw = invoke("inspect")
assert raw, logs
result=json.loads(raw)
result.update(yang=yang,yin=yin,generalHeight=general_height,cardCount=card_count)
print(json.dumps({"result":result,"logs":logs},ensure_ascii=False,indent=2))
assert result["descriptionLines"] > 1, "server description must wrap"
assert result["versionHeight"] <= 22, "rich text version must respect compact size"
assert result["popupWidth"] > 100 and result["popupHeight"] > 100, "popup content size"
assert general_height > 20, "general skill description must have a nonzero height"
assert card_count == 3, "teammate handcard grid must render the supplied visible cards"
assert str(yang).endswith("/switch") and str(yin).endswith("/switch-yin"), "switch changes propagate to the real skill delegate"
assert result["switchSource"].endswith("/switch-yin"), "initial Yin value must render regardless of property initialization order"
assert "white" in result["toggleIcon"] and "M16" in result["toggleIcon"], "chat toggle tracks collapsed/expanded state"
salt=json.dumps(["freekill-social-account-v1","test:9527","测试用户"],ensure_ascii=False,separators=(",",":")).encode()
expected=hashlib.pbkdf2_hmac("sha256",b"test-only-password",salt,210000,32).hex()
assert result["authResult"]["key"] == expected, "WorkerScript identity remains compatible"
assert not [line for line in logs if any(s in line for s in ("TypeError", "ReferenceError", "SyntaxError", "Cannot assign", "Unable to assign", "Binding loop"))], logs
window.close();engine.deleteLater();app.processEvents()
