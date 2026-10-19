"""Run the real Android image importer on an explicitly selected test device."""
from pathlib import Path
import argparse, os, struct, subprocess, time, uuid, zipfile, zlib

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial',required=True)
parser.add_argument('--work-dir',type=Path,required=True)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
work=Path(os.path.abspath(args.work_dir));work.mkdir(parents=True,exist_ok=True)
sdk=Path(os.environ.get('ANDROID_HOME',str(Path.home()/'AppData/Local/Android/Sdk')))
jdk=Path(os.environ.get('JAVA_HOME',r'C:/Program Files/Android/openjdk/jdk-21.0.8'))/'bin'
jar=sdk/'platforms/android-36/android.jar'
classes=work/'classes';classes.mkdir(exist_ok=True)
dex=work/'dex';dex.mkdir(exist_ok=True)
def run(*command):
    result=subprocess.run(list(map(str,command)),capture_output=True,text=True,encoding='utf-8',errors='replace')
    if result.returncode:print(result.stdout);print(result.stderr)
    result.check_returncode()
    return result
run(jdk/'javac.exe','-encoding','UTF-8','-source','8','-target','8','-classpath',jar,'-d',classes,
    root/'java/org/notify/FreeKill/CounterBackgroundImages.java',*sorted((root/'tests').glob('*.java')))
run(jdk/'java.exe','-cp',sdk/'build-tools/36.0.0/lib/d8.jar','com.android.tools.r8.D8','--lib',jar,
    '--min-api','28','--output',dex,*sorted(classes.rglob('*.class')))

# Stream a 40-megapixel PNG fixture without allocating a huge desktop bitmap.
fixture=work/'large.png'
def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
with fixture.open('wb') as stream:
    stream.write(b'\x89PNG\r\n\x1a\n')
    stream.write(chunk(b'IHDR',struct.pack('>IIBBBBB',8000,5000,8,2,0,0,0)))
    compressor=zlib.compressobj(6)
    row=b'\0'+bytes((20,180,60))*8000
    for _ in range(5000):
        data=compressor.compress(row)
        if data:stream.write(chunk(b'IDAT',data))
    stream.write(chunk(b'IDAT',compressor.flush()));stream.write(chunk(b'IEND',b''))
adb=[sdk/'platform-tools/adb.exe','-s',args.serial]
package='com.cui.freekill.bgtest'+uuid.uuid4().hex[:12]
assets=work/'assets';assets.mkdir(exist_ok=True)
import shutil
shutil.copyfile(fixture,assets/'large.png')
manifest=work/'AndroidManifest.xml'
manifest.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="'''+package+'''">
 <uses-sdk android:minSdkVersion="34" android:targetSdkVersion="35"/>
 <application android:debuggable="true" android:label="Image Import Fixture" android:theme="@android:style/Theme.Material.Light.NoActionBar">
  <provider android:name="org.notify.FreeKill.BackgroundTestProvider" android:authorities="'''+package+'''.images" android:exported="false"/>
  <activity android:name="org.notify.FreeKill.BackgroundTestActivity" android:exported="true">
   <intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter>
  </activity>
 </application></manifest>''',encoding='utf-8')
unsigned=work/'fixture-unsigned.apk';signed=work/'fixture.apk'
tools=sdk/'build-tools/36.0.0'
run(tools/'aapt2.exe','link','-I',jar,'--manifest',manifest,'-A',assets,'-o',unsigned)
with zipfile.ZipFile(unsigned,'a') as apk:apk.write(dex/'classes.dex','classes.dex')
key=work/'fixture-debug.p12'
if not key.exists():
    run(jdk/'keytool.exe','-genkeypair','-keystore',key,'-storetype','PKCS12','-storepass','android',
        '-keypass','android','-alias','fixture','-dname','CN=Image Import Fixture','-keyalg','RSA','-validity','30')
run(jdk/'java.exe','-jar',tools/'lib/apksigner.jar','sign','--ks',key,'--ks-pass','pass:android','--out',signed,unsigned)
run(*adb,'install',signed)
try:
    run(*adb,'shell','am','start','-n',package+'/org.notify.FreeKill.BackgroundTestActivity')
    deadline=time.monotonic()+60;result=''
    while time.monotonic()<deadline:
        read=subprocess.run(list(map(str,adb+['shell','run-as',package,'cat','files/result.txt'])),capture_output=True,text=True)
        if read.returncode==0:result=read.stdout;break
        time.sleep(.5)
    print(result)
    assert result.startswith('PASS:'),result or 'Android test timed out'
finally:
    assert package.startswith('com.cui.freekill.bgtest') and len(package)==len('com.cui.freekill.bgtest')+12
    run(*adb,'uninstall',package)
