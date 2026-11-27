"""Create narrowly scoped data adaptations; never rewrite retained originals.

Two public exports reference one absent atlas region each. A transparent page
keeps their original skeleton/timing intact. This repairs loading, not recovery
of the absent image. Original-pixel completeness stays explicitly unverified.
"""
import argparse,hashlib,json,re,shutil
from pathlib import Path
from PIL import Image

REPAIRS={
 'ui/anim/caomaozhengwang/SS_CM_2025zhenwang':('texture/rwmhgx/rwmhgx_00059','2bc64fbcc8cfc0ebf03aad7447b7402b'),
 'ui/anim/spell/yuli/SS_2026smc_leishashouji2':('shouji2/shouji2_ad_00012','9aabb28d98bc2e231d73dcd8a5af6bd7'),
}

def repair(research:Path,output:Path):
 assert not output.exists(),'Preserve prior candidates; choose a new output'
 output.mkdir(parents=True)
 index=json.loads((research/'cloud-index.json').read_text('utf8'))
 rows=[]
 for stem,(missing,skel_md5) in REPAIRS.items():
  source=research/'assets'/stem
  skel=source.with_suffix('.skel').read_bytes();atlas=source.with_suffix('.atlas').read_bytes()
  assert hashlib.md5(skel).hexdigest()==skel_md5
  for ext,data in [('.skel',skel),('.atlas',atlas)]:
   row=index[stem+ext];assert len(data)==row['size'] and hashlib.md5(data).hexdigest()==row['md5']
  names={l for l in atlas.decode('utf8').splitlines() if l and not l.startswith(' ') and ':' not in l and not l.endswith('.png')}
  assert missing not in names and missing.encode() in skel
  adapted_stem=stem+'_atlasfix1';base=output/'assets'/adapted_stem;base.parent.mkdir(parents=True,exist_ok=True)
  base.with_suffix('.skel').write_bytes(skel)
  image_name=base.name+'__empty.png';empty=base.parent/image_name
  Image.new('RGBA',(1,1),(0,0,0,0)).save(empty)
  extra=f'\n\n{image_name}\nsize: 1,1\nformat: RGBA8888\nfilter: Linear,Linear\nrepeat: none\n{missing}\n  rotate: false\n  xy: 0, 0\n  size: 1, 1\n  orig: 1, 1\n  offset: 0, 0\n  index: -1\n'.encode()
  base.with_suffix('.atlas').write_bytes(atlas.rstrip()+extra)
  originals=[]
  for page in re.findall(r'^([^\s].*\.png)$',atlas.decode('utf8'),re.M):
   assert Path(page).name==page
   p=source.parent/page;blob=p.read_bytes();expected=index[(Path(stem).parent/page).as_posix()]
   assert len(blob)==expected['size'] and hashlib.md5(blob).hexdigest()==expected['md5']
   shutil.copyfile(p,base.parent/page)
   originals.append({'file':page,'sha256':hashlib.sha256(blob).hexdigest(),'pixelsChanged':False})
  rows.append({'sourceStem':stem,'stem':adapted_stem,'missingRegion':missing,'repairId':'explicit-transparent-region-v1',
   'sourceSkeletonMD5':skel_md5,'sourceSkeletonSHA256':hashlib.sha256(skel).hexdigest(),
   'sourceAtlasSHA256':hashlib.sha256(atlas).hexdigest(),'adaptedAtlasSHA256':hashlib.sha256(base.with_suffix('.atlas').read_bytes()).hexdigest(),
   'skeletonBytesChanged':False,'originalPages':originals,'missingOriginalPixelsRecovered':False,
   'originalPixelCompleteness':'unverified','nativeCompatibility':'pending','phoneAcceptance':'pending'})
 (output/'repairs.json').write_text(json.dumps({'schema':1,'repairs':rows,'published':False},ensure_ascii=False,indent=2)+'\n','utf8')
 return rows

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--research',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 print(json.dumps({'adaptations':len(repair(a.research,a.output)),'nativeOrDeviceAccepted':False}))
