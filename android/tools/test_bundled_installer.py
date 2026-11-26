"""Run the production Java transaction and ZIP extractor on isolated desktop files."""
from pathlib import Path
import os, subprocess, urllib.request, json

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'work/embedded-v1-20261121'
WORK.mkdir(parents=True,exist_ok=True)
JDK=Path(os.environ['JAVA_HOME'])/'bin'
ANDROID=Path(os.environ['ANDROID_HOME'])/'platforms/android-36/android.jar'
JAR=WORK/'json-20240303.jar'
if not JAR.exists():
    urllib.request.urlretrieve('https://repo.maven.apache.org/maven2/org/json/json/20240303/json-20240303.jar',JAR)
HARNESS=r'''
package org.notify.FreeKill;
import org.json.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.*;
import java.io.*;

public class InstallerHarness {
 static int checks=0;
 static void check(boolean okay,String name)throws Exception{if(!okay)throw new Exception(name);checks++;System.out.println("PASS "+name);}
 static byte[] bytes(String value){return value.getBytes(StandardCharsets.UTF_8);}
 static JSONObject config(Path p)throws Exception{return new JSONObject(new String(Files.readAllBytes(p.resolve("freekill.client.config.json")),StandardCharsets.UTF_8));}
 static JSONObject fixture(Path assets)throws Exception{
   Files.createDirectories(assets);JSONArray packs=new JSONArray();
   int i=0;
   for(String id:BundledPackInstaller.IDS){
     Path zip=assets.resolve("fixture-"+(i++)+".zip");String path="packages/freekill-core/image/sample.json";
     byte[] data=bytes("{\"sample\":true}");
     try(ZipOutputStream out=new ZipOutputStream(Files.newOutputStream(zip))){out.putNextEntry(new ZipEntry(path));out.write(data);out.closeEntry();}
     packs.put(new JSONObject().put("id",id).put("title",id).put("version","test").put("archive",zip.getFileName().toString())
       .put("bytes",Files.size(zip)).put("sha256",BundledPackInstaller.hash(zip))
       .put("files",new JSONArray().put(new JSONObject().put("path",path).put("sha256",BundledPackInstaller.hex(java.security.MessageDigest.getInstance("SHA-256").digest(data))))));
   }
   return new JSONObject().put("schema",1).put("bundleId",String.join("",Collections.nCopies(64,"a"))).put("packs",packs);
 }
 static boolean install(Path root,JSONObject catalog,Path source)throws Exception{
   return BundledPackInstaller.install(root,catalog,name->Files.newInputStream(source.resolve(name)),CounterResourcePacks::extract,(t,c,n)->{});
 }
 public static void main(String[] args)throws Exception{
   Path assets=Paths.get(args[0]),work=Files.createTempDirectory(Paths.get(args[1]),"test-");
   JSONObject real=new JSONObject(new String(Files.readAllBytes(assets.resolve("catalog.json")),StandardCharsets.UTF_8));
   Path fresh=work.resolve("fresh");
   check(install(fresh,real,assets),"fresh install of all 3 real archives");
   check(config(fresh).getJSONArray("enabledResourcePacks").length()==3,"three packs enabled before game config loads");
   int count=0;JSONArray list=real.getJSONArray("packs");
   for(int i=0;i<list.length();i++){JSONObject p=list.getJSONObject(i);JSONArray files=p.getJSONArray("files");
     for(int j=0;j<files.length();j++){JSONObject f=files.getJSONObject(j);check(BundledPackInstaller.hash(fresh.resolve("resource_pak").resolve(p.getString("id")).resolve(f.getString("path"))).equals(f.getString("sha256")),"real resource "+(++count));}}
   check(count==322,"322 real resource files");
   JSONObject changed=config(fresh).put("username","EXAMPLE-NOT-A-USER").put("password","test-only").put("enabledResourcePacks",new JSONArray());
   BundledPackInstaller.writeJson(fresh.resolve("freekill.client.config.json"),changed);
   String family=list.getJSONObject(0).getString("id");
   Path selected=fresh.resolve("resource_pak").resolve(family);Path held=fresh.resolve("disabled-copy");Files.move(selected,held);
   check(!install(fresh,real,assets),"subsequent launch skips installed revision");
   check(!Files.exists(selected)&&config(fresh).getJSONArray("enabledResourcePacks").length()==0,"manual delete and disable survive relaunch");
   Path fixtures=work.resolve("fixtures");JSONObject tiny=fixture(fixtures);
   Path upgrade=work.resolve("existing");Files.createDirectories(upgrade);
   BundledPackInstaller.writeJson(upgrade.resolve("freekill.client.config.json"),new JSONObject().put("username","TEST").put("password","fixture-secret").put("enabledResourcePacks",new JSONArray().put("other-pack")).put("favorites",new JSONArray().put("other-general")));
   install(upgrade,tiny,fixtures);
   JSONObject kept=config(upgrade);
   check(kept.getString("username").equals("TEST")&&kept.getString("password").equals("fixture-secret")&&kept.getJSONArray("favorites").length()==1,"existing account and preferences preserved");
   check(kept.getJSONArray("enabledResourcePacks").length()==4,"unrelated enabled pack preserved");
   Path bad=work.resolve("corrupt"),first=fixtures.resolve(tiny.getJSONArray("packs").getJSONObject(0).getString("archive"));
   byte[] original=Files.readAllBytes(first);Files.write(first,bytes("broken"));boolean rejected=false;
   try{install(bad,tiny,fixtures);}catch(Exception expected){rejected=true;}
   check(rejected&&!Files.exists(bad.resolve("freekill.client.config.json")),"corrupt archive never changes config");Files.write(first,original);
   check(install(bad,tiny,fixtures),"retry after corrupted source restored");
   Path invalid=work.resolve("invalid-config");Files.createDirectories(invalid);Files.write(invalid.resolve("freekill.client.config.json"),bytes("not json"));rejected=false;
   try{install(invalid,tiny,fixtures);}catch(Exception expected){rejected=true;}
   check(rejected&&new String(Files.readAllBytes(invalid.resolve("freekill.client.config.json")),StandardCharsets.UTF_8).equals("not json"),"invalid existing config is not overwritten");
   Path rollback=work.resolve("rollback");Files.createDirectories(rollback);Files.write(rollback.resolve("freekill.client.config.json"),bytes("{\"original\":true}"));
   String firstId=tiny.getJSONArray("packs").getJSONObject(0).getString("id");Path old=rollback.resolve("resource_pak").resolve(firstId);Files.createDirectories(old);Files.write(old.resolve("old.txt"),bytes("old"));rejected=false;
   try{BundledPackInstaller.install(rollback,tiny,name->Files.newInputStream(fixtures.resolve(name)),CounterResourcePacks::extract,(t,c,n)->{if(c==n)throw new IOException("test failure after commit");});}catch(Exception expected){rejected=true;}
   check(rejected&&Files.exists(old.resolve("old.txt"))&&config(rollback).getBoolean("original"),"failed commit rolls back config and previous resource directories");
   check(install(rollback,tiny,fixtures),"retry after rollback succeeds without stale completion marker");
   JSONObject traversal=new JSONObject(tiny.toString());traversal.getJSONArray("packs").getJSONObject(0).getJSONArray("files").getJSONObject(0).put("path","../outside.json");rejected=false;
   try{BundledPackInstaller.validate(traversal);}catch(Exception expected){rejected=true;}
   check(rejected,"path traversal inventory rejected");
   JSONObject result=new JSONObject().put("passed",true).put("checks",checks).put("actualResourceFiles",count).put("phoneTested",false).put("method","Production Java transaction and production ZIP extractor on isolated Windows files");
   Files.write(Paths.get(args[1]).resolve("installer-result.json"),bytes(result.toString(2)));
   System.out.println("COMPLETE "+checks+" checks");
 }
}
'''
source=WORK/'InstallerHarness.java';source.write_text(HARNESS,encoding='utf-8')
classes=WORK/'test-classes';classes.mkdir(exist_ok=True)
sources=[ROOT/'android/java/org/notify/FreeKill'/f'{n}.java' for n in ('BundledPackInstaller','CounterEmbeddedPacks','CounterResourcePacks','ResourcePackInstaller')]
cp=os.pathsep.join(map(str,(JAR,ANDROID)))
subprocess.run([str(JDK/'javac.exe'),'-encoding','UTF-8','-classpath',cp,'-d',str(classes),*map(str,sources),str(source)],check=True)
completed=subprocess.run([str(JDK/'java.exe'),'-cp',os.pathsep.join((str(classes),cp)),'org.notify.FreeKill.InstallerHarness',str(WORK/'assets'),str(WORK)],text=True,capture_output=True)
(WORK/'installer-test.log').write_text(completed.stdout+completed.stderr,encoding='utf-8')
if completed.returncode:
    print(completed.stdout[-5000:]);print(completed.stderr);raise SystemExit(completed.returncode)
print((WORK/'installer-result.json').read_text())
