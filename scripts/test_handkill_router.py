"""Exercise real handkill routing and QML lifecycle with a simulated Spine clock.

Rendering is covered separately by the native D3D11 probe. No phone is used.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile
import zipfile
os.environ.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
from PySide6.QtCore import QUrl, QMetaObject, Q_ARG, Q_RETURN_ARG, QTimer, QEventLoop, qInstallMessageHandler, QPoint, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--pack', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args(); a.output.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parents[1]
app = QGuiApplication([]); logs=[]; qInstallMessageHandler(lambda k,c,m:logs.append(m))
with tempfile.TemporaryDirectory(dir=a.output) as temp:
    b=Path(temp)
    def put(name,text):
        f=b/name; f.parent.mkdir(parents=True,exist_ok=True); f.write_text(text,encoding='utf8')
    with zipfile.ZipFile(a.pack) as z:
        files=[b.as_uri()+'/resource_pak/handkill/'+n for n in z.namelist()]
        manifest=json.loads(z.read('packages/freekill-core/image/xinyuesha-handkill/manifest.json'))
    repaired=any(x['stem'].endswith('_atlasfix1') for x in manifest['effects'])
    put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Cpp','Config','Lua','Backend']))
    put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject {property string path:'+json.dumps(b.as_uri())+'}')
    put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject {property bool banChangeSkin:false;property var enabledResourcePacks:["handkill"]}')
    put('Fk/Lua.qml','pragma Singleton\nimport QtQuick\nQtObject {property var publicStateData:({hp:2,zhouyu:0,quest:0,kuanggu:0});property int cardReads:0;property string publicCardColour:"red";function tr(s){return s;}function ev(s){if(s.includes("p:getMark"))return publicStateData;if(s.includes("Fk:getCardById")){cardReads++;return publicCardColour;}return false;}}')
    put('Fk/Backend.qml','pragma Singleton\nimport QtQuick\nQtObject {property bool invalidRepairMetadata:false;property var contents:'+json.dumps(manifest)+';function readFileFromAssets(p){return "";}function readJsonObjectFromFile(p){const value=JSON.parse(JSON.stringify(contents));if(invalidRepairMetadata)for(const row of value.effects)if(row.repair)row.repair.sourceSkeletonMD5="invalid";return value;}}')
    put('Spine/qmldir','module Spine\nSkeletonAnimation 1.0 SkeletonAnimation.qml\nsingleton SpineVersion 1.0 SpineVersion.qml\nsingleton TestControl 1.0 TestControl.qml\n')
    put('Spine/SpineVersion.qml','pragma Singleton\nimport QtQuick\nQtObject {enum Version {Auto}}')
    put('Spine/TestControl.qml','pragma Singleton\nimport QtQuick\nQtObject {property bool fail:false;}')
    put('Spine/SkeletonAnimation.qml','''import QtQuick
Item {id:root;property url atlasFile;property url skeletonDataFile;property real skeletonScale:1;property int spineVersion:0;property bool premultipliedAlapha:false;property string skin:"";property bool loaded:false;property bool playing:false
signal skeletonLoadFinished(bool ok);signal complete(int trackIndex,int loopCount)
function clearTracks(){playing=false;done.stop();}function setToSetupPose(){}
function setAnimation(track,name,loop){playing=loaded&&/^play[0-9]*$/.test(name);if(playing&&!loop)done.restart();}
function isPlaying(track){return playing;}
Timer {interval:8;running:true;onTriggered:{root.loaded=!TestControl.fail;root.skeletonLoadFinished(root.loaded);}}
Timer {id:done;interval:280;onTriggered:{root.playing=false;root.complete(0,1);}}
}''')
    for name in ['HandkillRouter.qml','HandkillPerformance.qml','EffectLayer.qml']:
        shutil.copyfile(root/'android/payload/card-counter'/name,b/name)
    put('Main.qml','''import QtQuick
import QtQuick.Controls
import Fk
import Spine
Window {id:win;width:1188;height:540;visible:true;property int clicks:0
Item {id:scene;anchors.fill:parent;property var dataModel:({players:[actor]});property var popupItem:null;property var agItem:null
 Button {x:900;y:430;width:150;height:50;text:"Table";onClicked:win.clicks++}
 Item {id:photo;x:460;y:20;width:120;height:150;visible:true;property string general:"神姜维";property string deputyGeneral:""}
 QtObject {id:actor;property int playerid:2;property var photoItem:photo}
}
QtObject {id:owner;property var currentScene:scene;property bool missing:false;property bool missingRepairs:false
 function visualFileExists(p){return !missing&&!(missingRepairs&&p.includes("_atlasfix1"))&&FILES.includes(p);}
 function generalOwnsSkill(g,n){return n!=="foreign_skill";}
 function canonicalSkillName(n){return ({"#zhongao_4_trig":"zhongao","#m_shi__kuanggu_1_trig":"m_shi__kuanggu","#xiongzi_1_trig":"xiongzi","#chiyun_1_trig":"chiyun","#yuli_2_trig":"yuli"})[n]||n;}
}
HandkillRouter {id:router;owner:owner}
function configure(g,d){router.reset();scene.popupItem=null;photo.general=g;photo.deputyGeneral=d;Config.enabledResourcePacks=["handkill"];Config.banChangeSkin=false;owner.missing=false;owner.missingRepairs=false;Backend.invalidRepairMetadata=false;TestControl.fail=false;Lua.publicStateData=({hp:2,zhouyu:0,quest:0,kuanggu:0});}
function legacy(){owner.missingRepairs=true;router.reset();}
function tamperRepair(){Backend.invalidRepairMetadata=true;router.reset();}
function send(command,data){return router.route(command,data);}
function publicState(data){Lua.publicStateData=data;}
function cardColour(colour){Lua.publicCardColour=colour;}
function reads(){return Lua.cardReads;}
function deferred(){return Object.keys(router.pendingStates).length;}

function state(){const i=router.activeItem;return JSON.stringify({active:i?{general:i.general,skill:i.skillName,animation:i.animationName,base:String(i.resourceBase).split("/").pop(),started:i.started}:null,pending:router.queue.length});}
function disable(){Config.enabledResourcePacks=[];}
function leave(){owner.currentScene=null;}
function restore(){owner.currentScene=scene;}
function hidden(){scene.visible=false;}
function show(){scene.visible=true;}
function fail(){TestControl.fail=true;}
function missing(){owner.missing=true;}
function openPopup(){scene.popupItem=({visible:true});}
function closePopup(){scene.popupItem=null;}
function openGameOver(){scene.popupItem=({visible:true,opacity:1,dataModel:{winner:"1"}});}

function bad(){return router.resource("ui/anim/caomaozhengwang/SS_CM_2025zhenwang","play")===null&&router.resource("ui/anim/spell/yuli/SS_2026smc_leishashouji2","play")===null;}
}'''.replace('FILES',json.dumps(files)))
    engine=QQmlApplicationEngine();engine.addImportPath(str(b));engine.load(QUrl.fromLocalFile(str(b/'Main.qml')))
    assert engine.rootObjects(),logs
    win=engine.rootObjects()[0]
    def pump(ms=35):
        loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
    def call(name,*args):
        r=QMetaObject.invokeMethod(win,name,*[Q_ARG('QVariant',v) for v in args]);pump();return r
    def config(g,d=''):call('configure',g,d)
    def send(cmd,data):call('send',cmd,data)
    def skill(n,**kw):send('Animate',dict(type='InvokeSkill',player=2,name=n,**kw))
    def state():return json.loads(QMetaObject.invokeMethod(win,'state',Q_RETURN_ARG('QVariant')))
    def active(base,g=None):
        s=state();assert s['active'] and s['active']['base']==base and s['active']['started'],(s,logs)
        if g:assert s['active']['general']==g,s
    cases=[('神姜维','xinghun','SS_Sjw_skill1'),('神姜维','tiantao','SS_Sjw_skill2'),
           ('神马超','jimie','SS_smc_dazhao'),
           ('势魏延','kuanggu','SS_ShiWeiyanFaDongSkill'),('曹髦','juejin','SS_cmskill'),
           ('周群','tiansuan','SSXF_PJN_qiuqian'),
           ('司马昭','zhaoxiong','SS_smz_fadongjineng'),
           ('谋吕布','wushuang','SS_MoulvbuSkill')]
    for general,name,base in cases:
        config(general);skill(name);active(base,general);pump(620);assert state()['active'] is None,state()
    for general,name,base in [('os__godmachao','jimie','SS_smc_dazhao'),
                              ('god__jiangwei','jiufa','SS_Sjw_skill1'),
                              ('mobile__shi__weiyan','m_shi__kuanggu','SS_ShiWeiyanFaDongSkill'),
                              ('mou__lvbu','wushuang','SS_MoulvbuSkill')]:
        config(general);skill(name);active(base,general);pump(620);assert state()['active'] is None,state()
    # Branch outcomes come from public server state, never a tentative reply.
    def publish(value):call('publicState',value)
    for outcome,animation in [('succeed','play2'),('failed','play1')]:
        config('势魏延');skill('zhongao');assert state()['active'] is None
        publish(dict(hp=2,quest=outcome));send('Fk.HandkillQuest',[2,'zhongao']);active('SS_ShiWeiYanSkill');assert state()['active']['animation']==animation
    config('势魏延');send('Fk.HandkillQuest',[2,'zhongao']);assert state()['active'] is None
    for index,animation in [(1,'play1'),(3,'play2'),(5,'play3')]:
        config('势魏延');send('LogEvent',dict(type='PlaySkillSound',name='m_shi__kuanggu',general='势魏延',i=index))
        skill('m_shi__kuanggu');active('SS_ShiWeiyanFaDongSkill');assert state()['active']['animation']==animation
    config('势魏延');send('LogEvent',dict(type='PlaySkillSound',name='zhongao',general='势魏延',i=1));skill('zhongao');assert state()['active'] is None
    # Real .25 callbacks use registered SkillSkeleton branch names. Test the
    # same parent identity for gating, pending quest state and voice variants.
    config('势魏延');skill('#zhongao_4_trig');publish(dict(hp=2,quest='failed'));send('Fk.HandkillQuest',[2,'zhongao']);active('SS_ShiWeiYanSkill');assert state()['active']['animation']=='play1'
    config('势魏延');send('LogEvent',dict(type='PlaySkillSound',name='m_shi__kuanggu',general='势魏延',i=3));skill('#m_shi__kuanggu_1_trig');active('SS_ShiWeiyanFaDongSkill');assert state()['active']['animation']=='play2'
    config('势周瑜');skill('#xiongzi_1_trig');send('SetPlayerMark',[2,'@xiongzi-noclear','xiongzi_1']);active('SS_szy_jn_shui')
    config('势周瑜');publish(dict(zhouyu='xiongzi_2',hp=2));skill('#chiyun_1_trig');active('SS_jn_szyskillred')
    config('神马超');skill('#yuli_2_trig',skill_type='defensive');active('SS_2026smc_leishashouji2_atlasfix1' if repaired else 'SS_2026smc_huixue')
    if repaired:
        for mode in ['legacy','tamperRepair']:
            config('神马超');call(mode);skill('#yuli_2_trig',skill_type='defensive');active('SS_2026smc_huixue')
            config('曹髦');call(mode);send('Animate',dict(type='Death',to=2));active('SS_CM_zhenwang')
    for scheme,stem,colour in [('xiongzi_1','SS_szy_jn_shui','blue'),('xiongzi_2','SS_szy_jn_huo','red')]:
        config('势周瑜');skill('xiongzi');assert state()['active'] is None
        send('SetPlayerMark',[2,'@xiongzi-noclear',scheme]);active(stem)
        for name,animation in [('chiyun','play1'),('yanhui','play3'),('fentao','play2')]:
            config('势周瑜');publish(dict(zhouyu=scheme,hp=2));skill(name);active('SS_jn_szyskill'+colour);assert state()['active']['animation']==animation
    config('势周瑜');skill('chiyun');send('SetPlayerMark',[2,'@xiongzi-noclear','xiongzi_1']);assert state()['active'] is None
    for choice,animation in [('mobile__zhenfeng_hp','play4'),('mobile__zhenfeng_lostHp','play3'),('mobile__zhenfeng_alives','play5')]:
        config('势太史慈');skill('mobile__zhenfeng');assert state()['active'] is None
        send('SetPlayerMark',[2,'@mobile__zhenfeng_mobile__hanzhan',choice]);active('SS_taishici_jineng');assert state()['active']['animation']==animation
        send('SetPlayerMark',[2,'@mobile__zhenfeng_zhanlie',choice]);assert state()['pending']==0,'same selection repeated twice'
    config('势太史慈');skill('mobile__zhenfeng');send('PropertyUpdate',[2,'hp',4]);active('SS_taishici_jineng');assert state()['active']['animation']=='play2'
    for colour,animation in [('red','play1'),('black','play2')]:
        config('笮融');call('cardColour',colour)
        send('MoveCards',{'42':True,'merged':[dict(to=2,skillName='futu',specialName='futu_ye',ids=[42])]})
        active('SS_pjn_skill_zr');assert state()['active']['animation']==animation
    config('笮融');before=QMetaObject.invokeMethod(win,'reads',Q_RETURN_ARG('QVariant'))
    send('MoveCards',{'42':False,'merged':[dict(to=2,skillName='futu',specialName='futu_ye',ids=[42])]})
    assert state()['active'] is None and QMetaObject.invokeMethod(win,'reads',Q_RETURN_ARG('QVariant'))==before
    send('MoveCards',{'merged':[dict(**{'from':2},skillName='futu',fromSpecialName='futu_ye',ids=[42])]});active('SS_pjn_skill_zr');assert state()['active']['animation']=='play3'
    config('张让');send('MoveCards',{'42':True,'merged':[dict(to=2,skillName='futu',specialName='futu_ye',ids=[42])]});assert state()['active'] is None
    config('神荀彧');skill('tiansuan');assert state()['active'] is None
    config('周群');send('Fk.HandkillPublicLog',dict(type='#TiansuanResult',player=2,result='tiansuanSSR'));active('SSXF_PJN_zhongqian')
    config('神姜维');call('openPopup');skill('xinghun');active('SS_Sjw_skill1')
    pump(350);assert state()['active'] is None,'An untouched interaction dialog must never retain a still performance'
    call('closePopup')
    config('神姜维');skill('jiufa');skill('jiufa');assert state()['pending']==0,state()
    QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(975,455));pump();assert win.property('clicks')==1
    skill('pingxiang');assert state()['pending']==1;call('disable');assert state()=={'active':None,'pending':0}
    skill('jiufa');assert state()['active'] is None
    for g in ['姜维','魏延','周瑜','马超']:
        config(g)
        for n in ['jiufa','zhongao','jimie','fixture_skill']:skill(n)
        send('Fk.GuanNingSkinAction',dict(player=2,action='attack'));assert state()['active'] is None,(g,state())
    config('神姜维');skill('foreign_skill');assert state()['active'] is None
    send('Animate',dict(type='InvokeSkill',player=3,name='jiufa'));assert state()['active'] is None
    for cmd in ['AskForUseCard','CancelRequest','MoveFocus']:
        send(cmd,dict(player=2,name='jiufa'));assert state()['active'] is None
    config('姜维','神姜维');send('Animate',dict(type='InvokeUltSkill',player=2,name='jiufa',deputy=False));assert state()['active'] is None
    send('Animate',dict(type='InvokeUltSkill',player=2,name='jiufa',deputy=True));active('SS_Sjw_skill1','神姜维')
    call('leave');assert state()=={'active':None,'pending':0};call('restore')
    config('神姜维');send('LogEvent',dict(type='Death',to=2));active('SS_Sjw_dead')
    # The final death must get full visible playback after the stock victory
    # overlay/result opening; an untouched unrelated dialog is not that result.
    send('GameOver',{});assert state()=={'active':None,'pending':1}
    call('openPopup');pump(300);assert state()=={'active':None,'pending':1}
    call('openGameOver');pump(260);active('SS_Sjw_dead');pump(350);assert state()['active'] is None
    skill('xinghun');assert state()['active'] is None,'Post-game skill events must not restart animations'
    send('EnterRoom',{});skill('xinghun');active('SS_Sjw_skill1')
    config('神姜维');send('GameOver',{});send('Fk.HandkillGameStart',{});skill('xinghun');active('SS_Sjw_skill1')
    config('神姜维');skill('xinghun');send('LogEvent',dict(type='Death',to=2));assert state()['pending']==1
    send('GameOver',{});assert state()=={'active':None,'pending':1}
    call('openGameOver');pump(260);active('SS_Sjw_dead');assert state()['pending']==0
    call('leave');assert state()=={'active':None,'pending':0};call('restore')
    config('曹髦');send('Animate',dict(type='Death',to=2));active('SS_CM_2025zhenwang_atlasfix1' if repaired else 'SS_CM_zhenwang')
    config('势周瑜');send('Fk.HandkillGameStart',{});pump(715);active('Ss_zy_ruchangzhanshi')
    for card,base in [('slash','SS_szy_sha'),('fire__slash','SS_szy_huosha'),('thunder__slash','SS_szy_leisha'),('jink','SS_szy_shan')]:
        config('势赵云');send('Fk.HandkillCard',dict(player=2,cardName=card));active(base)
    config('赵云');send('Fk.HandkillCard',dict(player=2,cardName='slash'));assert state()['active'] is None
    config('神姜维');call('fail');skill('jiufa');pump();assert state()['active'] is None,(state(),logs)
    config('神姜维');call('missing');skill('jiufa');assert state()['active'] is None
    config('神姜维');skill('jiufa');call('hidden');assert state()=={'active':None,'pending':0};call('show')
    assert QMetaObject.invokeMethod(win,'bad',Q_RETURN_ARG('QVariant'))
    errors=[x for x in logs if any(t in x for t in ['TypeError','ReferenceError','SyntaxError','Unable to assign','Cannot assign'])]
    assert not errors,errors
    result={'passed':True,'skillRoutes':len(cases),'publicBranchOutcomesTested':True,'futuHiddenIdentitiesNeverRead':True,'canonicalAliasCases':4,'deathRoutes':2,'cardRoutes':4,'entryRoutes':1,
            'ordinaryVersionsExcluded':True,'deputyAndOwnedSkillGates':True,'publicActorGate':True,
            'noTableInputBlocking':True,'automaticPlaybackAndCleanupWithUntouchedDialog':True,'disabledAndHiddenAndRoomLeaveCleaned':True,
            'loadFailureAndMissingResourcesSkipped':True,'unsafeExportsBlocked':True,'repairedOriginalRoutes':repaired,'repairAbsentOrMetadataInvalidFallsBack':repaired,'finalDeathSurvivesGameOverAndLeavesCleanly':True,
            'nativeRendering':'separate D3D11 probes','deviceAcceptance':False}
    (a.output/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(result));win.close()
