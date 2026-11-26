"""Real Guan Ning and OL render/cleanup above a dialog, without a phone."""
import hashlib, json, os, shutil, subprocess
from pathlib import Path
from PIL import Image, ImageChops
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'work/three-fixes-20261126/visual-gpu'
OUT.mkdir(parents=True,exist_ok=True)
QT=ROOT/'work/native-v1-android/qt-windows-sdk'
PROBE=OUT/'TenyearComboProbe.exe'
shutil.copyfile(ROOT/'work/native-v1-android/combo-probe/TenyearComboProbe.exe',PROBE)
qml=(ROOT/'scripts/tenyear_combo_probe/probe.qml').read_text(encoding='utf8')
qml=qml.replace('  property int completed: 0', '''  property alias actorPhoto: actor
  property alias targetPhoto: target
  property var dataModel:({players:[{playerid:2,photoItem:target}]})
  Item{id:actor;x:800;y:130;width:120;height:145}
  Item{id:target;x:260;y:150;width:120;height:145}
  property int completed: 0''')
(OUT/'probe.qml').write_text(qml,encoding='utf8')
env={**os.environ,'QT_QPA_PLATFORM':'offscreen','QT_PLUGIN_PATH':str(QT/'plugins'),
     'QML_IMPORT_PATH':str(QT/'qml'),'QT_QUICK_CONTROLS_STYLE':'Basic',
     'FK_PROBE_POPUP_OPEN':'1','PATH':str(QT/'bin')+os.pathsep+os.environ['PATH']}
env.pop('QT_QUICK_BACKEND',None)
cases=[]
resources=ROOT/'work/effect-web-previews-20261121/resources/tenyear/packages/freekill-core/image/xinyuesha-tenyear/guanning/8195001'
for action in ['attack','skill']:
    body='''active=c.createObject(parent,{photo:parent.actorPhoto,scene:parent,resourceRoot:RESOURCE,showPreviewButton:false});
      if(active){active.actionCompleted.connect(function(){root.mainDone=true;finishWait.start();});active.playAction(ACTION,{targets:[2]});}'''
    body=body.replace('RESOURCE',json.dumps(resources.as_uri()+'/')).replace('ACTION',json.dumps(action))
    cases.append(('guanning-'+action,ROOT/'android/payload/card-counter/guanning/GuanNingActions.qml',resources/'chuchang2',body,7000))
cases.append(('ol',ROOT/'android/payload/card-counter/LightTargetLine.qml',ROOT/'work/ol-source-20261120/original-ol-gold/zhixiangxianlong',
    '''active=c.createObject(parent,{origin:Qt.point(260,200),destination:Qt.point(850,230),imageSource:resourceBase+".png",olOriginalFrames:true,autoDispose:false});
       if(active)active.finished.connect(function(ok){root.finished(ok);});''',2300))
results=[]
for name,player,base,body,end in cases:
    folder=OUT/name;folder.mkdir(exist_ok=True)
    wrapper=folder/'Player.qml'
    wrapper.write_text('''import QtQuick
Item{id:root;required property url resourceBase;required property string general;required property string skillName;
 signal finished(bool ok);property var active:null;property bool mainDone:false
 Timer{id:finishWait;interval:100;repeat:true;onTriggered:{if(root.mainDone&&root.active&&!root.active.activeAction&&root.active.trails.length===0){stop();root.finished(true);}}}
 Component.onCompleted:{const c=Qt.createComponent(PLAYER);if(c.status!==Component.Ready){console.error(c.errorString());return;}BODY}
 Component.onDestruction:if(active)active.destroy()
}'''.replace('PLAYER',json.dumps(player.as_uri())).replace('BODY',body),encoding='utf8')
    env['FK_PROBE_END_MS']=str(end)
    with (folder/'native.log').open('wb') as log:
        run=subprocess.run([str(PROBE),str(wrapper),str(base),name,str(folder)],env=env,stdout=log,stderr=log,timeout=20,creationflags=subprocess.CREATE_NO_WINDOW)
    report=json.loads((folder/'result.json').read_text(encoding='utf8'))
    assert run.returncode==0 and report['passed'],(name,run.returncode,report)
    late=Image.open(folder/f'frame-{end-100}.png').convert('RGB')
    differences=[]
    for frame in folder.glob('frame-*.png'):
        ms=int(frame.stem[6:])
        if 400<=ms<=1900:
            delta=ImageChops.difference(Image.open(frame).convert('RGB').crop((212,102,968,378)),late.crop((212,102,968,378))).convert('L')
            differences.append(sum(n for value,n in enumerate(delta.histogram()) if value>8))
    assert max(differences)>100,(name,differences)
    cleared=Image.open(folder/('frame-1900.png' if name=='ol' else 'frame-5500.png')).convert('RGB')
    assert not ImageChops.difference(cleared,late).getbbox(),name
    errors=[s for s in report['messages'] if any(t in s for t in ('TypeError','ReferenceError','Cannot assign','Unable to assign','Binding loop'))]
    assert not errors,errors
    results.append({'case':name,'passed':True,'animatedPixelsOverDialog':max(differences),'automaticCleanup':True,'elapsedMs':report['elapsedMs'],'playerSha256':hashlib.sha256(player.read_bytes()).hexdigest()})
result={'passed':True,'platform':'Windows D3D11 / real Spine','phoneUsed':False,'cases':results}
(OUT/'summary.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print(json.dumps(result))
