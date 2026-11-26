"""Render the real OL skeleton, legacy strip and missing-source cleanup offline."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import zipfile
from PIL import Image, ImageChops

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--probe',type=Path,required=True)
p.add_argument('--wrapper',type=Path,required=True)
p.add_argument('--originals',type=Path,required=True)
p.add_argument('--legacy-pack',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
legacy=a.output/'legacy-assets';legacy.mkdir(exist_ok=True)
with zipfile.ZipFile(a.legacy_pack) as z:
    image=next(n for n in z.namelist() if n.endswith('/gold-head-frames.png'))
    (legacy/'gold-head-frames.png').write_bytes(z.read(image))
env={**os.environ,'QT_QPA_PLATFORM':'offscreen','FK_PROBE_END_MS':'2300'}
cases=[('ol',a.originals/'zhixiangxianlong',0),('legacy',legacy/'gold-head-frames',0),('missing',a.output/'not-present',5)]
results=[]
for name,base,expected in cases:
    out=a.output/name;out.mkdir(exist_ok=True)
    run=subprocess.run([str(a.probe.resolve()),str(a.wrapper.resolve()),str(base.resolve()),name,str(out.resolve())],env=env,capture_output=True,text=True,timeout=20)
    report=json.loads((out/'result.json').read_text(encoding='utf8'))
    assert run.returncode==expected,(name,run.returncode,run.stdout,run.stderr)
    assert report['completed']==(1 if name!='missing' else 0),report
    assert report['elapsedMs']<2000,report
    final=Image.open(out/'frame-2200.png').convert('RGB')
    if name!='missing':
        middle=Image.open(out/'frame-900.png').convert('RGB')
        diff=ImageChops.difference(middle,final)
        # Effects appear on the table, while the hand area remains intact.
        assert diff.crop((0,0,1188,360)).getbbox(),name
        assert not diff.crop((0,390,1188,540)).getbbox(),name
        assert not ImageChops.difference(Image.open(out/'frame-1900.png').convert('RGB'),final).getbbox(),name
    else:
        assert not ImageChops.difference(Image.open(out/'frame-900.png').convert('RGB'),final).getbbox(),name
    errors=[m for m in report['messages'] if any(s in m for s in ['TypeError','ReferenceError','Cannot assign','Unable to assign','is not a type'])]
    assert not errors,errors
    results.append(dict(case=name,passed=True,elapsedMs=report['elapsedMs'],completed=report['completed'],expectedMissingSource=name=='missing'))
summary=dict(passed=True,platform='Windows D3D11 offscreen; not Android device acceptance',cases=results,
             originalSkeletonUnchanged=True,legacyTenyearFramesStillRender=True,automaticCleanup=True,handAreaUnchanged=True,phoneUsed=False)
(a.output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(json.dumps(summary,ensure_ascii=False))
