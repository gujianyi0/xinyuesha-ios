"""Apply the iOS profile-swipe adapter to an existing unsigned release IPA.

Preserves the release's native binary, core and all unrelated resources. This
also retains hotfixes that have not yet been consolidated into the runtime tree.
"""
import argparse, copy, hashlib, json, re, zipfile
from pathlib import Path, PureWindowsPath
p=argparse.ArgumentParser();p.add_argument('--base-ipa',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--version',required=True);a=p.parse_args()
if a.base_ipa.resolve()==a.output.resolve():raise SystemExit('Use a new output file; the base IPA must remain intact.')
if a.output.exists():raise SystemExit('Output already exists; choose a new file.')
root=Path(__file__).resolve().parents[1]
canonical=(root/'runtime/card-counter/CounterHost.qml').read_text(encoding='utf8')
start=canonical.index('  // FB-0DX3XM:');end=canonical.index('  function adaptPlayerDetail(item)',start);adapter=canonical[start:end]
prefix='Payload/FreeKill.app/res/'
with zipfile.ZipFile(a.base_ipa) as z:
    host=z.read(prefix+'card-counter/CounterHost.qml').decode('utf8').replace('\r\n','\n')
    if 'function adaptPlayerDetailSwipe' in host:raise SystemExit('Base already includes profile swiping.')
    anchor='  function adaptPlayerDetail(item) {'
    assert host.count(anchor)==1
    host=host.replace(anchor,adapter+anchor)
    anchor='    if (!item || !("dataModel" in item) || !("finish" in item) ||\n        !item.children) return;'
    assert host.count(anchor)==1
    host=host.replace(anchor,anchor+'\n    adaptPlayerDetailSwipe(item);')
    social=z.read(prefix+'card-counter/SocialHost.qml').decode('utf8').replace('\r\n','\n')
    social,n=re.subn(r'好友与显示设置 · [^"\n]+','好友与显示设置 · '+a.version,social);assert n==1
    replacements={prefix+'card-counter/CounterHost.qml':host.replace('\n','\r\n').encode(),prefix+'card-counter/SocialHost.qml':social.replace('\n','\r\n').encode()}
    digest=hashlib.sha256()
    for directory in ['Fk','LunarLtk','card-counter']:
        names=[n for n in z.namelist() if n.startswith(prefix+directory+'/') and not n.endswith('/')]
        for n in sorted(names,key=lambda n:PureWindowsPath(n[len(prefix):])):
            digest.update(n[len(prefix):].encode()+b'\0');digest.update(hashlib.sha256(replacements.get(n,z.read(n))).digest())
    replacements[prefix+'client-ui-revision']=(digest.hexdigest()+'\n').encode()
    a.output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(a.output,'w') as w:
        for info in z.infolist():w.writestr(copy.copy(info),replacements.get(info.filename,z.read(info.filename)))
    with zipfile.ZipFile(a.output) as w:
        assert w.testzip() is None
        assert w.namelist()==z.namelist()
        changed=[n for n in z.namelist() if w.read(n)!=z.read(n)]
        assert sorted(changed)==sorted(replacements),changed
    print(json.dumps({'version':a.version,'sha256':hashlib.sha256(a.output.read_bytes()).hexdigest(),'size':a.output.stat().st_size,'changed':changed,'nativeAndCoreUnchanged':True},ensure_ascii=False))

