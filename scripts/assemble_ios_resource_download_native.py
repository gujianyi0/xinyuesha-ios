"""Combine a compact CI native patch with locally held identical resource/framework data.

Every reused non-UI file must match CI's full SHA256 inventory. The Git index
is regenerated metadata and may differ; its complete upstream core tree is
checked by the existing protected-core gate. Managed UI is replaced by the
explicit latest client payload in the following packaging step.
"""
import argparse,hashlib,json,zipfile,configparser
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);p.add_argument('--patch',type=Path,required=True);p.add_argument('--manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();inventory=json.loads(a.manifest.read_text('utf8'));prefix=inventory['bundlePrefix'];managed=tuple(prefix+'res/'+d+'/' for d in ['Fk','LunarLtk','card-counter']);index=prefix+'res/packages/freekill-core/.git/index';revision=prefix+'res/client-ui-revision';rows=[];missing=[];metadata=[];native=[]
with zipfile.ZipFile(a.baseline) as old,zipfile.ZipFile(a.patch) as patch:
    sources={n:old for n in old.namelist()};sources.update({n:patch for n in patch.namelist()});verified=[]
    for row in inventory['entries']:
        name=row['path']
        if name.startswith(managed) or name==revision:continue
        if name not in sources:missing.append(name);continue
        data=sources[name].read(name)
        if len(data)!=row['bytes'] or hashlib.sha256(data).hexdigest()!=row['sha256']:
            if name==index:metadata.append(name)
            elif name==prefix+'res/packages/freekill-core/.git/config':
                config=configparser.ConfigParser();config.read_string(data.decode('utf8'))
                assert set(config.sections())=={'core','remote "origin"'}
                assert config['remote "origin"']['url']=='https://gitee.com/Qsgs-Fans/freekill-core'
                assert set(config['core'])<={'repositoryformatversion','filemode','bare','logallrefupdates','symlinks','ignorecase','autocrlf','precomposeunicode'}
                assert config['core']['bare']=='false'
                metadata.append(name)
            else:missing.append(name)
        else:verified.append(name)
    assert not missing, 'Non-UI files differ from CI: '+json.dumps(missing,ensure_ascii=False)
    assert prefix+'FreeKill' in patch.namelist()
    a.output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(a.output,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as target:
        present=set()
        for item in old.infolist():
            if item.filename in patch.namelist():continue
            target.writestr(item,old.read(item));present.add(item.filename)
        for item in patch.infolist():target.writestr(item,patch.read(item));present.add(item.filename)
report={'passed':True,'reusedUnmanagedDataAndBinariesMatchCloudManifest':True,'verifiedUnmanagedFiles':len(verified),'allowedPortableGitMetadataDifferences':metadata,'nativeFilesFromCloud':len(patch.namelist()),'frameworksVerifiedBySha256':True,'latestManagedUiAppliedSeparately':True,'deviceAcceptance':False}
(a.output.parent/'native-assembly-verification.json').write_text(json.dumps(report,indent=2),'utf8');print(json.dumps(report))
