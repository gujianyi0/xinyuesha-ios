"""Exercise the production move policy with an unsupported-atomic provider fixture."""
import argparse,json,os,subprocess,tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
root=Path(__file__).resolve().parents[1];jdk=Path(os.environ.get('JAVA_HOME','C:/Program Files/Android/openjdk/jdk-21.0.8'))/'bin';jar=root/'work/embedded-v1-20261121/json-20240303.jar'
with tempfile.TemporaryDirectory(dir=a.output) as temp:
 b=Path(temp);src=b/'StorageCompatProbe.java'
 src.write_text(r'''package org.notify.FreeKill;
import java.nio.file.*;import java.util.*;import java.io.*;import org.json.*;
public class StorageCompatProbe {
 static int calls=0;
 static Path unsupported(Path from,Path to,CopyOption... options)throws IOException {
  calls++;if(Arrays.asList(options).contains(StandardCopyOption.ATOMIC_MOVE))throw new AtomicMoveNotSupportedException(from.toString(),to.toString(),"fixture provider");
  return Files.move(from,to,options);
 }
 static void check(boolean ok)throws Exception{if(!ok)throw new Exception("Storage assertion failed");}
 public static void main(String[] args)throws Exception {
  Path root=Paths.get(args[0]);Files.createDirectories(root);
  Path from=root.resolve("part.partial"),to=root.resolve("part.zip");Files.write(from,new byte[]{1,2,3});Files.write(to,new byte[]{9});
  ResourcePackInstaller.moveCompatible(from,to,true,StorageCompatProbe::unsupported);check(calls==2&&Arrays.equals(Files.readAllBytes(to),new byte[]{1,2,3})&&!Files.exists(from));
  Path stage=Files.createDirectory(root.resolve("stage")),dest=root.resolve("pack");Files.write(stage.resolve("icon.png"),new byte[]{4});calls=0;
  ResourcePackInstaller.moveCompatible(stage,dest,false,StorageCompatProbe::unsupported);check(calls==2&&!Files.exists(stage)&&Files.readAllBytes(dest.resolve("icon.png"))[0]==4);
  Files.write(from,new byte[]{8});calls=0;
  try{ResourcePackInstaller.moveCompatible(from,to,true,(f,t,o)->{calls++;throw new AccessDeniedException(t.toString());});throw new Exception("permission failure swallowed");}
  catch(AccessDeniedException expected){check(calls==1&&Files.readAllBytes(from)[0]==8&&Files.readAllBytes(to)[0]==1);}
  Path state=root.resolve("state.json");BundledPackInstaller.writeJson(state,new JSONObject().put("id","42").put("ok",true));
  check(new JSONObject(new String(Files.readAllBytes(state),"UTF-8")).getBoolean("ok"));
  check(Files.list(root).noneMatch(f->f.getFileName().toString().startsWith("embedded-write-")));
  System.out.println("{\"passed\":true,\"unsupportedAtomicFileAndDirectoryFallback\":true,\"permissionFailurePreservesBothFiles\":true,\"productionJsonWriter\":true,\"realAndroidFilesystem\":false}");
 }
}''','utf8')
 classes=b/'classes';classes.mkdir();subprocess.run([str(jdk/'javac.exe'),'-encoding','UTF-8','-cp',str(jar),'-d',str(classes),*[str(root/'android/java/org/notify/FreeKill'/n) for n in ['ResourcePackInstaller.java','BundledPackInstaller.java']],str(src)],check=True)
 result=subprocess.check_output([str(jdk/'java.exe'),'-Xmx48m','-cp',str(classes)+os.pathsep+str(jar),'org.notify.FreeKill.StorageCompatProbe',str(b/'app')]);report=json.loads(result);(a.output/'result.json').write_text(json.dumps(report,indent=2),'utf8');print(json.dumps(report))
