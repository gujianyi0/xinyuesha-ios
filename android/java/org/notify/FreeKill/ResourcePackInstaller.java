// SPDX-License-Identifier: GPL-3.0-or-later
package org.notify.FreeKill;

import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.zip.*;

/** Streaming, resumable data-only installer. No Android UI or account writes. */
final class ResourcePackInstaller {
    static final long MAX_ARCHIVE=192L*1024*1024, MAX_PACK=2L*1024*1024*1024;
    static final int MAX_FILES=4096;
    interface Progress { void update(String stage,long done,long total,int part,int parts)throws Exception; }
    interface Copier { void copy(JSONObject part,Path destination)throws Exception; }
    interface Mover { Path move(Path from,Path to,CopyOption... options)throws IOException; }
    static void moveCompatible(Path from,Path to,boolean replace)throws IOException {
        moveCompatible(from,to,replace,Files::move);
    }
    static void moveCompatible(Path from,Path to,boolean replace,Mover mover)throws IOException {
        CopyOption[] atomic=replace?new CopyOption[]{StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING}:new CopyOption[]{StandardCopyOption.ATOMIC_MOVE};
        try {mover.move(from,to,atomic);}
        catch(AtomicMoveNotSupportedException|UnsupportedOperationException unavailable) {
            mover.move(from,to,replace?new CopyOption[]{StandardCopyOption.REPLACE_EXISTING}:new CopyOption[]{});
        }
    }
    final Path root,bridge; final String origin,id; final Progress progress;
    private long lastProgress,lastCancelCheck; private long before,total;private int partNumber,partCount;
    ResourcePackInstaller(Path root,String origin,String id,Progress progress)throws Exception {
        this.root=root.toRealPath();this.origin=origin;this.id=id;this.progress=progress;
        bridge=safe("assets/resource-pack-download");Files.createDirectories(bridge);
    }
    Path safe(String name)throws IOException {
        Path result=root.resolve(name).normalize();if(!result.startsWith(root))throw new IOException("Invalid resource path");
        for(Path p=result;p!=null&&!p.equals(root);p=p.getParent())if(Files.isSymbolicLink(p))throw new IOException("Linked resource path");
        return result;
    }
    static String hash(Path path)throws Exception {
        MessageDigest md=MessageDigest.getInstance("SHA-256");byte[] buffer=new byte[65536];
        try(InputStream input=Files.newInputStream(path)){for(int n;(n=input.read(buffer))!=-1;)md.update(buffer,0,n);}
        StringBuilder out=new StringBuilder();for(byte b:md.digest())out.append(String.format(Locale.ROOT,"%02x",b&255));return out.toString();
    }
    static JSONArray validate(JSONObject catalog)throws Exception {
        if(catalog.getInt("schema")!=1&&catalog.getInt("schema")!=2)throw new IOException("Unsupported resource catalog");
        JSONArray result=new JSONArray(),rows=catalog.getJSONArray("packs");Set<String> ids=new HashSet<>();
        if(rows.length()>32)throw new IOException("Too many resource packs");
        for(int i=0;i<rows.length();i++) {
            JSONObject row=new JSONObject(rows.getJSONObject(i).toString());String key=row.getString("id");
            if(!key.matches("[A-Za-z0-9_\\-\\p{IsHan}]{1,64}")||!ids.add(key)||row.getString("title").length()>80||row.getString("version").length()>32)throw new IOException("Invalid resource metadata");
            JSONArray parts=row.optJSONArray("parts");if(parts==null){parts=new JSONArray().put(new JSONObject(row.toString()));row.put("parts",parts);}
            if(parts.length()==0||parts.length()>32)throw new IOException("Invalid resource parts");
            long bytes=0,expanded=0;int files=0;Set<String> names=new HashSet<>();
            for(int j=0;j<parts.length();j++) {
                JSONObject p=parts.getJSONObject(j);String archive=p.getString("archive");long length=p.getLong("bytes");
                if(!archive.matches("[A-Za-z0-9_-]{1,96}\\.zip")||!names.add(archive)||!p.getString("sha256").matches("[a-f0-9]{64}")||length<=0||length>MAX_ARCHIVE)throw new IOException("Invalid resource part");
                bytes+=length;expanded+=p.optLong("expandedBytes",256L*1024*1024);files+=p.optInt("fileCount",2048);
            }
            if(bytes!=row.getLong("bytes")||bytes>MAX_PACK||expanded>MAX_PACK||files>MAX_FILES||row.optLong("expandedBytes",expanded)!=expanded||row.optInt("fileCount",files)!=files)throw new IOException("Resource limits exceeded");
            row.put("strictExpanded",row.has("expandedBytes")).put("strictFileCount",row.has("fileCount"));
            row.put("expandedBytes",expanded).put("fileCount",files);result.put(row);
        }
        return result;
    }
    void checkCancelled()throws Exception {
        if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("Download paused");
        long now=System.currentTimeMillis();if(now-lastCancelCheck<200)return;lastCancelCheck=now;
        Path cancel=bridge.resolve("cancel.json");
        if(Files.isRegularFile(cancel)&&Files.size(cancel)<1024)try{if(id.equals(new JSONObject(new String(Files.readAllBytes(cancel),StandardCharsets.UTF_8)).optString("id")))throw new Cancelled();}catch(JSONException unfinished){}
    }
    static final class Cancelled extends IOException {Cancelled(){super("下载已取消，可重新下载并继续已缓存部分。");}}
    void report(String stage,long done,boolean force)throws Exception {
        checkCancelled();long now=System.currentTimeMillis();if(force||now-lastProgress>=300){progress.update(stage,done,total,partNumber,partCount);lastProgress=now;}
    }
    void fetch(JSONObject part,Path path)throws Exception {
        long expected=part.getLong("bytes"),offset=Files.exists(path)?Files.size(path):0;
        if(offset>expected){Files.delete(path);offset=0;}
        if(offset==expected)return;
        HttpURLConnection connection=(HttpURLConnection)new URL(origin+"/download/"+part.getString("archive")).openConnection();
        connection.setInstanceFollowRedirects(false);connection.setConnectTimeout(12000);connection.setReadTimeout(18000);connection.setRequestProperty("Accept-Encoding","identity");
        connection.setRequestProperty("User-Agent","FreeKill Resource Download");
        if(offset>0)connection.setRequestProperty("Range","bytes="+offset+"-");
        try {
            int status=connection.getResponseCode();
            if(status==200)offset=0;
            else if(status!=206||offset<=0||!("bytes "+offset+"-"+(expected-1)+"/"+expected).equals(connection.getHeaderField("Content-Range")))throw new IOException("下载范围校验失败，请重试。");
            try(InputStream input=connection.getInputStream();OutputStream output=Files.newOutputStream(path,StandardOpenOption.CREATE,offset>0?StandardOpenOption.APPEND:StandardOpenOption.TRUNCATE_EXISTING)) {
                byte[] buffer=new byte[65536];long length=offset;
                for(int n;(n=input.read(buffer))!=-1;){checkCancelled();length+=n;if(length>expected)throw new IOException("下载大小不匹配");output.write(buffer,0,n);report("downloading",before+length,false);}
                if(length!=expected)throw new IOException("下载中断，请重试，已缓存部分会继续下载。");
            }
        }finally{connection.disconnect();}
    }
    void install(JSONObject pack,Copier embedded)throws Exception {
        String key=pack.getString("id");if(!key.matches("[A-Za-z0-9_\\-\\p{IsHan}]{1,64}"))throw new IOException("Invalid resource id");
        Path destination=safe("resource_pak/"+key);Files.createDirectories(destination.getParent());if(Files.isDirectory(destination,LinkOption.NOFOLLOW_LINKS))return;
        JSONArray parts=pack.getJSONArray("parts");total=pack.getLong("bytes");partCount=parts.length();
        Path cache=safe("assets/resource-pack-download/cache");Files.createDirectories(cache);
        long needed=pack.getLong("expandedBytes")+64L*1024*1024;
        for(int i=0;i<parts.length();i++){JSONObject p=parts.getJSONObject(i);Path cached=cache.resolve(p.getString("sha256")+".zip"),partial=cache.resolve(p.getString("sha256")+".partial");long have=Files.exists(cached)?Files.size(cached):Files.exists(partial)?Files.size(partial):0;needed+=Math.max(0,p.getLong("bytes")-have);}
        // Android's NIO provider rejects getFileStore; File uses statvfs on
        // the same app-owned volume and is supported by the Android runtime.
        if(root.toFile().getUsableSpace()<needed)throw new IOException("存储空间不足，请至少腾出 "+((needed+1048575)/1048576)+" MB 后重试。");
        Path temporary=Files.createTempDirectory(bridge,"install-");long[] expanded={pack.getLong("expandedBytes")};int[] files={0};Set<String> seen=new HashSet<>();List<Path> completed=new ArrayList<>();
        try {
            Path output=Files.createDirectory(temporary.resolve("pack"));before=0;
            for(int i=0;i<parts.length();i++) {
                partNumber=i+1;JSONObject p=parts.getJSONObject(i);Path archive=cache.resolve(p.getString("sha256")+".zip"),partial=cache.resolve(p.getString("sha256")+".partial");
                archive=safe("assets/resource-pack-download/cache/"+p.getString("sha256")+".zip");partial=safe("assets/resource-pack-download/cache/"+p.getString("sha256")+".partial");
                if(Files.exists(archive)&&(Files.size(archive)!=p.getLong("bytes")||!hash(archive).equals(p.getString("sha256"))))Files.delete(archive);
                if(!Files.exists(archive)) {
                    report("downloading",before+(Files.exists(partial)?Files.size(partial):0),true);
                    if(embedded!=null){Files.deleteIfExists(partial);embedded.copy(p,partial);}else fetch(p,partial);
                    if(Files.size(partial)!=p.getLong("bytes")||!hash(partial).equals(p.getString("sha256"))){Files.deleteIfExists(partial);throw new IOException("资源校验失败，请重新下载。");}
                    moveCompatible(partial,archive,true);
                }
                before+=p.getLong("bytes");report("extracting",before,true);extract(archive,output,expanded,files,seen);completed.add(archive);
            }
            if(files[0]==0||(pack.optBoolean("strictFileCount",false)&&pack.getInt("fileCount")!=files[0])||(pack.optBoolean("strictExpanded",false)&&expanded[0]!=0))throw new IOException("资源展开清单不匹配");
            lastCancelCheck=0;checkCancelled();moveCompatible(output,destination,false);
            // A committed, verified pack must not be reported as failed just
            // because the filesystem temporarily refuses cache housekeeping.
            for(Path file:completed)try{Files.deleteIfExists(file);}catch(IOException ignored){}
        }finally{try(java.util.stream.Stream<Path> paths=Files.walk(temporary)){for(Path path:(Iterable<Path>)paths.sorted(Comparator.reverseOrder())::iterator)Files.deleteIfExists(path);}}
    }
    static void extract(Path archive,Path destination,long[] remaining,int[] count,Set<String> seen)throws Exception {
        try(ZipFile zip=new ZipFile(archive.toFile())) {
            if(zip.size()>MAX_FILES)throw new IOException("Too many resource files");
            for(Enumeration<? extends ZipEntry> e=zip.entries();e.hasMoreElements();) {
                ZipEntry entry=e.nextElement();if(entry.isDirectory())continue;String name=entry.getName();
                if(name.length()>320||!name.matches("[\\p{L}\\p{N}_ ./-]+")||!name.matches("(?i)(icon\\.png|packages/.+\\.(png|jpe?g|webp|gif|mp4|webm|ogg|wav|mp3|atlas|skel|json))")||!seen.add(name.toLowerCase(Locale.ROOT)))throw new IOException("Unsupported resource file");
                for(String component:name.split("/",-1))if(component.isEmpty()||component.startsWith("."))throw new IOException("Invalid resource path");
                if(++count[0]>MAX_FILES||entry.getSize()<0||entry.getSize()>128L*1024*1024||entry.getSize()>remaining[0])throw new IOException("Resource extraction limits exceeded");
                Path file=destination.resolve(name).normalize();if(!file.startsWith(destination))throw new IOException("Invalid resource path");Files.createDirectories(file.getParent());long length=0;
                try(InputStream input=zip.getInputStream(entry);OutputStream output=Files.newOutputStream(file,StandardOpenOption.CREATE_NEW)){byte[] buffer=new byte[65536];for(int n;(n=input.read(buffer))!=-1;){if(Thread.currentThread().isInterrupted())throw new InterruptedIOException();length+=n;if(length>entry.getSize())throw new IOException("Resource size differs");output.write(buffer,0,n);}}
                if(length!=entry.getSize())throw new IOException("Incomplete resource file");remaining[0]-=length;
            }
        }
    }
}
