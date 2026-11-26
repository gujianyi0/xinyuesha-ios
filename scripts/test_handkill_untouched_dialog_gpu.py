"""Actual Spine 3.6 playback must finish with an untouched request dialog."""
import hashlib,json,os,shutil,subprocess
from pathlib import Path
from PIL import Image,ImageChops
root=Path(__file__).resolve().parents[1]
out=root/'work/three-fixes-20261126/untouched-dialog-gpu';out.mkdir(parents=True,exist_ok=True)
probe=root/'work/native-v1-android/combo-probe/TenyearComboProbe.exe';qt=root/'work/native-v1-android/qt-windows-sdk'
shutil.copyfile(root/'scripts/tenyear_combo_probe/probe.qml',probe.parent/'probe.qml')
player=root/'android/payload/card-counter/HandkillPerformance.qml'
wrapper=out/'Player.qml'
wrapper.write_text('''import QtQuick
Item {
 id:root
 required property url resourceBase
 required property string general
 required property string skillName
 signal finished(bool ok)
 property var active:null
 Component.onCompleted:{
   const c=Qt.createComponent(PLAYER);
   if(c.status!==Component.Ready){console.error(c.errorString());return;}
   active=c.createObject(parent,{resourceBase:resourceBase,general:general,skillName:skillName,
     originalJiangweiLayout:true,
     frameBase:String(resourceBase).replace(/SS_Sjw_skill[12]$/,"SS_Sjw_mask")});
   if(active)active.finished.connect(function(ok){root.finished(ok);});
 }
 Component.onDestruction:if(active)active.destroy()
}'''.replace('PLAYER',json.dumps(player.as_uri())),encoding='utf8')
env=os.environ.copy();env.update(QT_QPA_PLATFORM='offscreen',QT_PLUGIN_PATH=str(qt/'plugins'),QML_IMPORT_PATH=str(qt/'qml'),QT_QUICK_CONTROLS_STYLE='Basic',FK_PROBE_END_MS='7000',FK_PROBE_POPUP_OPEN='1')
env['PATH']=str(qt/'bin')+os.pathsep+env['PATH'];env.pop('QT_QUICK_BACKEND',None)
results=[]
for name in ['SS_Sjw_skill1','SS_Sjw_skill2']:
    folder=out/name;folder.mkdir(exist_ok=True)
    base=root/'work/phone-v1-acceptance-20261120/handkill-original/assets/ui/anim/shenJiangWei'/name
    with (folder/'native.log').open('wb') as log:
        p=subprocess.run([str(probe),str(wrapper),str(base),name,str(folder)],env=env,stdout=log,stderr=log,timeout=18,creationflags=subprocess.CREATE_NO_WINDOW)
    result=json.loads((folder/'result.json').read_text())
    late=Image.open(folder/'frame-6900.png').convert('RGB')
    animationAbovePopup=False;animated=False;automaticReturn=False
    for f in folder.glob('frame-*.png'):
        ms=int(f.stem[6:]);im=Image.open(f).convert('RGB')
        delta=ImageChops.difference(im.crop((212,102,968,378)),late.crop((212,102,968,378)))
        if 400<=ms<3000: animationAbovePopup |= max(hi for lo,hi in delta.getextrema())>8
        difference=ImageChops.difference(im,late).convert('L')
        if 400<=ms<3000: animated |= difference.point(lambda x:255 if x>8 else 0).getbbox() is not None
        if ms==5500: automaticReturn=max(hi for lo,hi in ImageChops.difference(im,late).getextrema())<=1
    ok=p.returncode==0 and result['passed'] and animationAbovePopup and animated and automaticReturn
    row={'asset':name,'passed':ok,'animationVisibleAbovePopup':animationAbovePopup,
      'visibleAnimatedPixels':animated,'returnedWithoutAnyInputBy5500ms':automaticReturn,
      'nativeCompleted':result['passed'],'elapsedMs':result['elapsedMs']}
    results.append(row);print(json.dumps(row),flush=True)
report={'platform':'Windows D3D11, actual Spine 3.6','phoneUsed':False,
        'playerSha256':hashlib.sha256(player.read_bytes()).hexdigest(),'cases':results,'passed':all(r['passed'] for r in results)}
(out/'summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
raise SystemExit(0 if report['passed'] else 1)
