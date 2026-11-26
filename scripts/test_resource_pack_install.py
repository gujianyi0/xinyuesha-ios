"""Exercise the real Java resource extractor on a host JDK, including the large pack."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import warnings
import zipfile

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--pack',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
root=Path(__file__).resolve().parents[1]
sdk=Path.home()/'AppData/Local/Android/Sdk'
jdk=Path('C:/Program Files/Android/openjdk/jdk-21.0.8/bin')
android=sdk/'platforms/android-36/android.jar'
with tempfile.TemporaryDirectory(dir=a.output) as temp:
    b=Path(temp).resolve();classes=b/'classes';classes.mkdir()
    source=b/'ExtractorProbe.java'
    source.write_text('''package org.notify.FreeKill;
import java.nio.file.*;
public class ExtractorProbe {
 public static void main(String[] args) throws Exception {
  if(args[0].equals("limit")) {
   java.lang.reflect.Field f=CounterResourcePacks.class.getDeclaredField("MAX_ARCHIVE");
   f.setAccessible(true);if((Long)f.get(null)<Files.size(Paths.get(args[1])))throw new Exception("archive limit");
   return;
  }
  Path target=Paths.get(args[1]);Files.createDirectories(target);
  try { CounterResourcePacks.extract(Paths.get(args[0]),target); }
  catch(java.io.IOException e) { System.out.println(e.getMessage());System.exit(20); }
 }
}''',encoding='utf8')
    subprocess.run([str(jdk/'javac.exe'),'-encoding','UTF-8','-classpath',str(android),'-d',str(classes),
                    *[str(root/'android/java/org/notify/FreeKill'/f'{n}.java') for n in ('CounterResourcePacks','CounterEmbeddedPacks','BundledPackInstaller')],str(source)],check=True)
    def run(archive,dest):
        p=subprocess.run([str(jdk/'java.exe'),'-Xmx48m','-cp',str(classes)+os.pathsep+str(android),
                          'org.notify.FreeKill.ExtractorProbe',str(archive),str(dest)],capture_output=True,timeout=45)
        return p.returncode,p.stdout.decode('utf8',errors='replace')
    assert run('limit',a.pack.resolve())[0]==0
    ok,log=run(a.pack.resolve(),b/'legitimate');assert ok==0,(ok,log)
    with zipfile.ZipFile(a.pack) as z:
        for entry in z.infolist():
            target=b/'legitimate'/entry.filename
            assert target.read_bytes()==z.read(entry.filename),entry.filename
    bad=[('traversal',[('packages/../escape.png',b'x')]),
         ('absolute',[('/escape.png',b'x')]),
         ('code',[('packages/p/script.lua',b'return 1')]),
         ('qml',[('packages/p/player.qml',b'import QtQuick')]),
         ('duplicate',[('packages/p/a.png',b'x'),('packages/p/a.png',b'y')]),
         ('icon-only',[('icon.png',b'x')])]
    for name,files in bad:
        path=b/(name+'.zip')
        with warnings.catch_warnings(),zipfile.ZipFile(path,'w') as z:
            warnings.simplefilter('ignore')
            for n,data in files:z.writestr(n,data)
        code,log=run(path,b/name);assert code==20,(name,code,log)
    path=b/'expanded-limit.zip'
    with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=1) as z:
        with z.open('packages/p/oversized.png','w',force_zip64=True) as f:
            for _ in range(257):f.write(bytes(1024*1024))
    code,log=run(path,b/'expanded-limit');assert code==20,(code,log)
    assert not (b/'escape.png').exists()
    result={'passed':True,'realJavaExtractor':True,'validPackBytes':a.pack.stat().st_size,
            'heapLimitMiB':48,'exactExtractedBytes':True,'rejectedCases':[n for n,_ in bad]+['expanded-size-limit'],
            'phoneUsed':False,'networkDownloadTested':False}
    (a.output/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf8');print(json.dumps(result))
