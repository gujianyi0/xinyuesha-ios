// SPDX-License-Identifier: GPL-3.0-or-later
package org.notify.FreeKill;

import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.nio.channels.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;

/** Filesystem-only transaction; Android glue supplies APK assets and progress. */
final class BundledPackInstaller {
    interface Source { InputStream open(String archive) throws Exception; }
    interface Extractor { void extract(Path archive, Path destination) throws Exception; }
    interface Progress { void update(String title, int completed, int total) throws Exception; }
    static final Set<String> IDS = new LinkedHashSet<>(Arrays.asList("手杀武将特效-v1", "十周年特效-v1", "指向线特效-v1"));
    static final long MAX_ARCHIVE = 192L * 1024 * 1024;

    static void validate(JSONObject catalog) throws Exception {
        if (catalog.getInt("schema") != 1 || !catalog.getString("bundleId").matches("[a-f0-9]{64}"))
            throw new IOException("Invalid bundled catalog");
        JSONArray packs = catalog.getJSONArray("packs");
        Set<String> seen = new HashSet<>();
        for (int i=0; i<packs.length(); i++) {
            JSONObject pack = packs.getJSONObject(i);
            String id=pack.getString("id");
            if (!IDS.contains(id) || !seen.add(id) || !pack.getString("archive").matches("[A-Za-z0-9_-]{1,96}\\.zip")
                    || !pack.getString("sha256").matches("[a-f0-9]{64}") || pack.getLong("bytes")<=0
                    || pack.getLong("bytes")>MAX_ARCHIVE || pack.getJSONArray("files").length()>2048)
                throw new IOException("Invalid bundled resource metadata");
            Set<String> paths = new HashSet<>();
            JSONArray files=pack.getJSONArray("files");
            for (int j=0; j<files.length(); j++) {
                JSONObject f=files.getJSONObject(j);String path=f.getString("path");
                if (!path.matches("[\\p{L}\\p{N}_ ./-]+") || !paths.add(path)
                        || !f.getString("sha256").matches("[a-f0-9]{64}")) throw new IOException("Invalid resource file");
                for (String part:path.split("/",-1)) if (part.isEmpty() || part.startsWith(".")) throw new IOException("Invalid resource path");
            }
            if (files.length()==0) throw new IOException("Empty bundled resource pack");
        }
        if (!seen.equals(IDS)) throw new IOException("Incomplete bundled families");
    }

    static Path safe(Path root, String relative) throws Exception {
        Path target=root.resolve(relative).normalize();
        if (!target.startsWith(root) || target.equals(root)) throw new IOException("Path outside application data");
        Path cursor=root;
        for (Path part:root.relativize(target)) {
            cursor=cursor.resolve(part);
            if (Files.isSymbolicLink(cursor)) throw new IOException("Symlink refused");
        }
        return target;
    }

    static String hash(Path file) throws Exception {
        MessageDigest digest=MessageDigest.getInstance("SHA-256");
        try (InputStream input=Files.newInputStream(file)) {
            byte[] buffer=new byte[65536];int count;
            while ((count=input.read(buffer))!=-1) digest.update(buffer,0,count);
        }
        return hex(digest.digest());
    }
    static String hex(byte[] bytes) {
        StringBuilder result=new StringBuilder();
        for (byte b:bytes) result.append(String.format(Locale.ROOT,"%02x",b&255));
        return result.toString();
    }
    static void copyVerified(Source source, JSONObject pack, Path target) throws Exception {
        MessageDigest digest=MessageDigest.getInstance("SHA-256");long total=0;
        try (InputStream input=source.open(pack.getString("archive"));
             OutputStream output=Files.newOutputStream(target,StandardOpenOption.CREATE_NEW)) {
            byte[] buffer=new byte[65536];int count;
            while ((count=input.read(buffer))!=-1) {
                if (Thread.currentThread().isInterrupted()) throw new InterruptedIOException("Preparation stopped");
                total+=count;
                if (total>pack.getLong("bytes") || total>MAX_ARCHIVE) throw new IOException("Resource archive too large");
                digest.update(buffer,0,count);output.write(buffer,0,count);
            }
        }
        if (total!=pack.getLong("bytes") || !hex(digest.digest()).equals(pack.getString("sha256")))
            throw new IOException("Bundled archive checksum mismatch");
    }
    static void atomicWrite(Path file, byte[] bytes) throws Exception {
        if (Files.isSymbolicLink(file)) throw new IOException("Symlink refused");
        Files.createDirectories(file.getParent());
        Path stage=Files.createTempFile(file.getParent(),"embedded-write-",".tmp");
        try {
            try (FileOutputStream output=new FileOutputStream(stage.toFile())) { output.write(bytes);output.getFD().sync(); }
            ResourcePackInstaller.moveCompatible(stage,file,true);
        } finally { Files.deleteIfExists(stage); }
    }
    static void writeJson(Path file, JSONObject json) throws Exception {
        atomicWrite(file,json.toString().getBytes(StandardCharsets.UTF_8));
    }

    static boolean install(Path inputRoot, JSONObject catalog, Source source, Extractor extractor, Progress progress) throws Exception {
        validate(catalog);
        Path root=inputRoot.toFile().getCanonicalFile().toPath();Files.createDirectories(root);
        Path meta=safe(root,"assets/effect-bundle");Files.createDirectories(meta);
        Path lockPath=safe(root,"assets/effect-bundle/install.lock");
        try (FileChannel channel=FileChannel.open(lockPath,StandardOpenOption.CREATE,StandardOpenOption.WRITE)) {
            FileLock lock=null;
            while (lock==null) {
                if (Thread.currentThread().isInterrupted()) throw new InterruptedIOException("Preparation stopped");
                try { lock=channel.tryLock(); } catch (OverlappingFileLockException busy) { }
                if (lock==null) Thread.sleep(50);
            }
            try { return installLocked(root,meta,catalog,source,extractor,progress); }
            finally { lock.release(); }
        }
    }

    private static boolean installLocked(Path root, Path meta, JSONObject catalog, Source source, Extractor extractor, Progress progress) throws Exception {
        String revision=catalog.getString("bundleId");
        Path marker=safe(root,"assets/effect-bundle/applied-"+revision+".json");
        if (Files.isRegularFile(marker,LinkOption.NOFOLLOW_LINKS)) {
            // A user's later disable/delete choice survives subsequent launches.
            return false;
        }
        Path config=safe(root,"freekill.client.config.json");
        boolean hadConfig=Files.exists(config,LinkOption.NOFOLLOW_LINKS);
        if (hadConfig && (!Files.isRegularFile(config,LinkOption.NOFOLLOW_LINKS) || Files.size(config)>4L*1024*1024))
            throw new IOException("Invalid existing configuration");
        byte[] before=hadConfig?Files.readAllBytes(config):null;
        JSONObject conf=hadConfig?new JSONObject(new String(before,StandardCharsets.UTF_8)):new JSONObject();
        JSONArray enabled=conf.optJSONArray("enabledResourcePacks");
        if (conf.has("enabledResourcePacks") && enabled==null) throw new IOException("Invalid enabled resource list");
        LinkedHashSet<String> next=new LinkedHashSet<>();
        if (enabled!=null) for (int i=0;i<enabled.length();i++) next.add(enabled.getString(i));
        JSONArray packs=catalog.getJSONArray("packs");
        Path active=safe(root,"resource_pak");Files.createDirectories(active);
        for (int i=0;i<packs.length();i++) {
            Path destination=safe(root,"resource_pak/"+packs.getJSONObject(i).getString("id"));
            if (Files.exists(destination,LinkOption.NOFOLLOW_LINKS) && !Files.isDirectory(destination,LinkOption.NOFOLLOW_LINKS))
                throw new IOException("Existing resource destination is not a directory");
        }
        Path stage=Files.createTempDirectory(meta,"stage-");
        Path backup=null;List<String> moved=new ArrayList<>();Set<String> previous=new HashSet<>();boolean configWritten=false;
        try {
            int total=packs.length();
            for (int i=0;i<total;i++) {
                JSONObject pack=packs.getJSONObject(i);String id=pack.getString("id");
                progress.update(pack.getString("title"),i,total);
                Path zip=stage.resolve("archive-"+i+".zip");copyVerified(source,pack,zip);
                Path directory=stage.resolve(id);Files.createDirectory(directory);extractor.extract(zip,directory);
                JSONArray files=pack.getJSONArray("files");
                long count;
                try (java.util.stream.Stream<Path> paths=Files.walk(directory)) {count=paths.filter(Files::isRegularFile).count();}
                if (count!=files.length()) throw new IOException("Resource inventory differs");
                for (int j=0;j<files.length();j++) {
                    JSONObject f=files.getJSONObject(j);Path path=safe(directory,f.getString("path"));
                    if (!Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS) || !hash(path).equals(f.getString("sha256")))
                        throw new IOException("Resource file checksum mismatch");
                }
                Files.delete(zip);next.add(id);
            }
            backup=Files.createTempDirectory(meta,"backup-");
            if (before!=null) atomicWrite(backup.resolve("client-before.private.json"),before);
            for (int i=0;i<packs.length();i++) {
                String id=packs.getJSONObject(i).getString("id");Path destination=active.resolve(id);
                if (Files.exists(destination,LinkOption.NOFOLLOW_LINKS)) {ResourcePackInstaller.moveCompatible(destination,backup.resolve(id),false);previous.add(id);}
                try {ResourcePackInstaller.moveCompatible(stage.resolve(id),destination,false);}
                catch (Exception error) {if(previous.contains(id))Files.move(backup.resolve(id),destination);throw error;}
                moved.add(id);
            }
            conf.put("enabledResourcePacks",new JSONArray(next));writeJson(config,conf);configWritten=true;
            progress.update("内置特效已就绪",packs.length(),packs.length());
            writeJson(marker,new JSONObject().put("bundleId",revision).put("packs",new JSONArray(IDS)));
            return true;
        } catch (Exception error) {
            if (configWritten) {if(before!=null)atomicWrite(config,before);else Files.deleteIfExists(config);}
            Collections.reverse(moved);
            for (String id:moved) {
                Files.move(active.resolve(id),stage.resolve(id));
                if (previous.contains(id)) Files.move(backup.resolve(id),active.resolve(id));
            }
            throw error;
        } finally {
            if (!stage.getParent().equals(meta) || !stage.getFileName().toString().startsWith("stage-")) throw new IOException("Unsafe cleanup target");
            try (java.util.stream.Stream<Path> paths=Files.walk(stage)) {
                for (Path path:(Iterable<Path>)paths.sorted(Comparator.reverseOrder())::iterator) Files.deleteIfExists(path);
            }
        }
    }
}
