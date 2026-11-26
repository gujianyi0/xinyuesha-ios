"""Export newly built native app files plus hashes for verified local assembly."""
from pathlib import Path
import hashlib,json,sys,zipfile

def prepare(ipa,output):
    output=Path(output);output.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(ipa) as source,zipfile.ZipFile(output/'native-files.zip','w',zipfile.ZIP_DEFLATED) as patch:
        names=[i.filename.split('/')[1] for i in source.infolist() if i.filename.startswith('Payload/') and '.app/' in i.filename]
        assert len(set(names))==1
        prefix='Payload/'+names[0]+'/'
        entries=[]
        for item in source.infolist():
            if item.is_dir():continue
            data=source.read(item);entries.append({'path':item.filename,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'mode':item.external_attr})
            if not item.filename.startswith((prefix+'res/',prefix+'Frameworks/')):patch.writestr(item,data)
    (output/'full-manifest.json').write_text(json.dumps({'bundlePrefix':prefix,'entries':entries},ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({'nativePatchBytes':(output/'native-files.zip').stat().st_size,'manifestFiles':len(entries)}))

if __name__=='__main__':prepare(sys.argv[1],sys.argv[2])
