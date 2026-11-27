"""Repackage local PC/iOS candidates with explicit native replacement only."""
import argparse,copy,hashlib,json,re,shutil,sys,tempfile,zipfile
from pathlib import Path
from prepare_ui_payload import prepare

root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--platform',choices=['pc','ios'],required=True);p.add_argument('--bundle',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--revision',default='20261127.36');p.add_argument('--pc-native',type=Path);a=p.parse_args()
assert re.fullmatch(r'\d{8}\.\d{1,3}',a.revision)
if a.pc_native and a.platform!='pc':p.error('--pc-native only accepts a Windows build')
if a.pc_native:assert a.pc_native.read_bytes().startswith(b'MZ')
version=a.revision;before=root.parent/'特效补丁/v1/20261126.35-资源包在线下载候选'
source=before/('新月杀-PC-20261126.35-x64.zip' if a.platform=='pc' else '新月杀-iOS-20261126.35-unsigned.ipa')
target=a.output/('新月杀-PC-'+version+'-x64.zip' if a.platform=='pc' else '新月杀-iOS-'+version+'-unsigned.ipa')
assert not target.exists(),'Preserve previous candidates'
prefix='' if a.platform=='pc' else 'Payload/FreeKill.app/res/'
payload=root/('pc/payload' if a.platform=='pc' else 'runtime')
catalog=json.loads((a.bundle/'catalog.json').read_text('utf8'));hand=next(p for p in catalog['packs'] if p['id']=='手杀武将特效-v1')
resource_prefix=prefix+'resource_pak/'+hand['id']+'/'
a.output.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(dir=root/'work/original-compat-20261127',prefix='package-'+a.platform+'-') as tmp,zipfile.ZipFile(source) as old,zipfile.ZipFile(a.bundle/hand['archive']) as resources:
 stage=Path(tmp)
 for item in old.infolist():
  if item.is_dir() or not item.filename.startswith(prefix):continue
  relative=Path(item.filename[len(prefix):])
  if relative.parts and relative.parts[0] in ['Fk','LunarLtk','card-counter']:
   file=stage/relative;file.parent.mkdir(parents=True,exist_ok=True);file.write_bytes(old.read(item))
 for folder in ['Fk','LunarLtk','card-counter']:
  if (payload/folder).exists():shutil.copytree(payload/folder,stage/folder,dirs_exist_ok=True)
 included=stage/'card-counter/included-visual-packs.json'
 if included.exists():
  data=json.loads(included.read_text('utf8'));data['bundleId']=catalog['bundleId'];included.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n','utf8')
 prepare(stage)
 changes={prefix+f.relative_to(stage).as_posix():f for f in stage.rglob('*') if f.is_file()}
 if a.pc_native:changes['FreeKill.exe']=a.pc_native
 resource_names={resource_prefix+n:n for n in resources.namelist() if not n.endswith('/')}
 present=set()
 with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=5) as new:
  for item in old.infolist():
   name=item.filename;present.add(name)
   if name in changes:new.writestr(copy.copy(item),changes[name].read_bytes())
   elif name in resource_names:
    with resources.open(resource_names[name]) as src,new.open(copy.copy(item),'w') as dst:shutil.copyfileobj(src,dst,1024*1024)
   else:
    with old.open(item) as src,new.open(copy.copy(item),'w') as dst:shutil.copyfileobj(src,dst,1024*1024)
  for name,file in changes.items():
   if name not in present:new.write(file,name)
  for name,resource in resource_names.items():
   if name not in present:
    with resources.open(resource) as src,new.open(name,'w') as dst:shutil.copyfileobj(src,dst,1024*1024)
 native='FreeKill.exe' if a.platform=='pc' else 'Payload/FreeKill.app/FreeKill'
 with zipfile.ZipFile(target) as new:assert new.read(native)==(a.pc_native.read_bytes() if a.pc_native else old.read(native))
report={'platform':a.platform,'archive':target.name,'sha256':hashlib.file_digest(target.open('rb'),'sha256').hexdigest(),'nativeBaselineUnchanged':a.pc_native is None,'explicitNativeReplacement':a.pc_native is not None,'deviceAcceptance':False,'published':False}
(a.output/('包体-'+a.platform+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n','utf8');print(json.dumps(report,ensure_ascii=False))
