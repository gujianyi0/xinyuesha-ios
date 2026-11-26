"""Actual native regression: missing atlas regions must return an error, never crash."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

root=Path(__file__).resolve().parents[1]
research=root/'work/phone-v1-acceptance-20261120/handkill-original'
out=root/'work/handkill-completion-20261120/parser';out.mkdir(exist_ok=True)
probe=Path('Q:/combo-probe/TenyearComboProbe.exe')
env=os.environ.copy();env['QT_QPA_PLATFORM']='offscreen';env['PATH']='Q:/qt-windows-sdk/bin;'+env['PATH']
results=[]
for row in json.loads((research/'inventory/all.json').read_text()):
    stem=row['stem'];report=out/(Path(stem).name+'.json')
    p=subprocess.run([str(probe.resolve()),'--inspect36',str((research/'assets'/stem).resolve()),str(report)],env=env,capture_output=True,timeout=20,creationflags=subprocess.CREATE_NO_WINDOW)
    assert p.returncode==(0 if row.get('loaded') else 10),(stem,p.returncode,p.stderr[-1500:])
    data=json.loads(report.read_text())
    if not row.get('loaded'):assert data.get('error','').startswith('Region not found:'),data
    results.append({'stem':stem,'loaded':data['loaded'],'error':data.get('error'),'returncode':p.returncode})
report={'passed':True,'validOriginalsLoaded':sum(r['loaded'] for r in results),'defectiveExportsSafelyRejected':sum(not r['loaded'] for r in results),'cases':results,'nativeProbeSha256':hashlib.sha256(probe.read_bytes()).hexdigest()}
(out/'summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(json.dumps({k:v for k,v in report.items() if k!='cases'}))
