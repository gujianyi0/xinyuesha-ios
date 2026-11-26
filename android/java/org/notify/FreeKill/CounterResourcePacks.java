// SPDX-License-Identifier: GPL-3.0-or-later
package org.notify.FreeKill;

import android.app.Activity;
import android.util.Log;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.util.Comparator;
import java.util.Locale;
import java.util.concurrent.*;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import javax.net.ssl.HttpsURLConnection;

/** Installs visual resources in the stock resource-pack directory. */
final class CounterResourcePacks {
    private static final String HOST = "https://gujianyi-xinyuesha-resources.pages.dev";
    private static final String CATALOG = HOST + "/catalog.json";
    private static final long MAX_ARCHIVE = 192L * 1024 * 1024;
    private static final long MAX_UNPACKED = 256L * 1024 * 1024;
    private static final int MAX_CATALOG = 64 * 1024;
    private static ScheduledExecutorService worker;
    private static android.content.Context context;

    private CounterResourcePacks() {}

    static synchronized void start(Activity activity) {
        if (worker != null) return;
        context=activity.getApplicationContext();
        File external = activity.getExternalFilesDir(null);
        Path internal = activity.getFilesDir().toPath();
        worker = Executors.newSingleThreadScheduledExecutor();
        worker.scheduleWithFixedDelay(() -> {
            for (Path root : external == null ? new Path[] {internal} : new Path[] {external.toPath(), internal}) {
                try {
                    process(root);
                } catch (Exception error) {
                    Log.w("ResourcePacks", "Resource package request failed", error);
                }
            }
        }, 0, 400, TimeUnit.MILLISECONDS);
    }

    static synchronized void stop() {
        if (worker != null) {
            worker.shutdownNow();
            worker = null;
        }
    }

    private static void process(Path root) throws Exception {
        Path bridge = root.resolve("assets/resource-pack-download");
        for (String legacy : new String[] {"轻特效v1-20261119-1", "轻特效v1-20261119-2", "轻特效v1-20261120-3"}) {
            Path old = root.resolve("resource_pak").resolve(legacy);
            Path retired = bridge.resolve("retired").resolve(legacy);
            if (Files.isDirectory(old, LinkOption.NOFOLLOW_LINKS) && !Files.exists(retired)) {
                Files.createDirectories(retired.getParent());
                Files.move(old, retired);
            }
        }
        Path request=bridge.resolve("request.json"), active=bridge.resolve("active.json");
        Path inputFile=Files.isRegularFile(active,LinkOption.NOFOLLOW_LINKS)?active:request;
        if(!Files.isRegularFile(inputFile,LinkOption.NOFOLLOW_LINKS)||Files.size(inputFile)>1024)return;
        JSONObject input;
        try{input=new JSONObject(new String(Files.readAllBytes(inputFile),StandardCharsets.UTF_8));}catch(org.json.JSONException unfinished){return;}
        String id=input.getString("id"),operation=input.getString("operation");
        if(!id.matches("[0-9_-]{1,48}")){Files.deleteIfExists(inputFile);return;}
        if(operation.equals("install"))BundledPackInstaller.writeJson(active,input);
        if(inputFile.equals(request))Files.deleteIfExists(request);
        JSONObject reply=new JSONObject().put("id",id).put("operation",operation).put("ok",false);
        try {
            if(operation.equals("catalog"))reply.put("packs",catalog());
            else if(operation.equals("uninstall")){uninstall(root,input.getString("pack"));reply.put("pack",input.getString("pack"));}
            else if(operation.equals("install")) {
                JSONObject pack=find(catalog(),input.getString("pack"));
                ResourcePackInstaller installer=new ResourcePackInstaller(root,HOST,id,(stage,done,total,part,parts)->
                    BundledPackInstaller.writeJson(bridge.resolve("progress.json"),new JSONObject().put("id",id).put("stage",stage).put("done",done).put("total",total).put("part",part).put("parts",parts)));
                installer.install(pack,pack.optBoolean("bundled",false)?(part,path)->CounterEmbeddedPacks.copy(pack,path):null);
                reply.put("pack",pack.getString("id"));
            }else throw new IOException("Invalid request");
            reply.put("ok",true);
        }catch(ResourcePackInstaller.Cancelled cancelled){reply.put("cancelled",true).put("error",cancelled.getMessage());}
        catch(Exception error){if(Thread.currentThread().isInterrupted())return;reply.put("error","资源包请求失败："+error.getMessage());Log.w("ResourcePacks","Resource request failed",error);}
        BundledPackInstaller.writeJson(bridge.resolve("reply.json"),reply);
        if(operation.equals("install"))Files.deleteIfExists(active);
    }

    static JSONArray catalog() throws Exception {
        JSONObject data;
        try {
            HttpsURLConnection connection=connect(CATALOG);
            try(InputStream input=connection.getInputStream();ByteArrayOutputStream output=new ByteArrayOutputStream()) {
                copy(input,output,MAX_CATALOG);data=new JSONObject(new String(output.toByteArray(),StandardCharsets.UTF_8));
            }finally{connection.disconnect();}
            ResourcePackInstaller.validate(data);
        }catch(Exception unavailable) {
            try(InputStream input=context.getAssets().open("res/card-counter/resource-catalog.json");ByteArrayOutputStream output=new ByteArrayOutputStream()) {
                copy(input,output,MAX_CATALOG);data=new JSONObject(new String(output.toByteArray(),StandardCharsets.UTF_8));
            }
        }
        JSONArray packs=ResourcePackInstaller.validate(data),embedded=CounterEmbeddedPacks.catalog();
        // Local copies replace downloads only for the exact same immutable data.
        if(embedded!=null)for(int i=0;i<packs.length();i++) {
            JSONObject row=packs.getJSONObject(i);JSONArray parts=row.getJSONArray("parts");if(parts.length()!=1)continue;
            for(int j=0;j<embedded.length();j++){JSONObject local=embedded.getJSONObject(j);if(local.getString("id").equals(row.getString("id"))&&local.getString("sha256").equals(parts.getJSONObject(0).getString("sha256")))row.put("bundled",true);}
        }
        return packs;
    }

    private static JSONObject find(JSONArray packs, String id) throws Exception {
        for (int index = 0; index < packs.length(); index++) {
            JSONObject pack = packs.getJSONObject(index);
            if (pack.getString("id").equals(id)) return pack;
        }
        throw new IOException("Resource pack unavailable");
    }

    private static void uninstall(Path root, String id) throws Exception {
        if (!id.matches("[A-Za-z0-9_\\-\\p{IsHan}]{1,64}")) throw new IOException("Invalid resource pack name");
        Path packs = root.resolve("resource_pak").toAbsolutePath().normalize();
        Path destination = packs.resolve(id).normalize();
        if (!packs.equals(destination.getParent()) || Files.isSymbolicLink(destination))
            throw new IOException("Invalid resource pack directory");
        Path config = root.resolve("freekill.client.config.json");
        if (Files.isRegularFile(config)) {
            JSONArray enabled = new JSONObject(new String(Files.readAllBytes(config), StandardCharsets.UTF_8))
                    .optJSONArray("enabledResourcePacks");
            if (enabled != null) for (int i = 0; i < enabled.length(); ++i)
                if (id.equals(enabled.getString(i))) throw new IOException("Disable the resource pack before deleting it");
        }
        if (!Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) return;
        // Files.walk does not follow symlinks, and the resolved root was checked above.
        try (java.util.stream.Stream<Path> paths = Files.walk(destination)) {
            for (Path path : (Iterable<Path>) paths.sorted(Comparator.reverseOrder())::iterator)
                Files.delete(path);
        }
    }

    static void extract(Path archive, Path destination) throws IOException {
        long remaining = MAX_UNPACKED;
        int files = 0;
        try (ZipFile zip = new ZipFile(archive.toFile())) {
            if (zip.size() > 2048) throw new IOException("Too many resource files");
            for (java.util.Enumeration<? extends ZipEntry> entries = zip.entries(); entries.hasMoreElements();) {
                ZipEntry entry = entries.nextElement();
                if (entry.isDirectory()) continue;
                String name = entry.getName();
                if (name.length() > 320 || !name.matches("[\\p{L}\\p{N}_ ./-]+")
                        || !name.matches("(?i)(icon\\.png|packages/.+\\.(png|jpe?g|webp|gif|mp4|webm|ogg|wav|mp3|atlas|skel|json))"))
                    throw new IOException("Unsupported resource file");
                for (String part : name.split("/", -1)) {
                    if (part.isEmpty() || part.startsWith("."))
                        throw new IOException("Invalid resource path");
                }
                Path file = destination.resolve(name).normalize();
                if (!file.startsWith(destination)) throw new IOException("Invalid resource path");
                Files.createDirectories(file.getParent());
                try (InputStream input = zip.getInputStream(entry);
                     OutputStream output = Files.newOutputStream(file, StandardOpenOption.CREATE_NEW)) {
                    remaining -= copy(input, output, remaining);
                }
                if (name.startsWith("packages/")) files++;
            }
        }
        if (files == 0) throw new IOException("Empty resource pack");
    }

    private static HttpsURLConnection connect(String url) throws IOException {
        HttpsURLConnection connection = (HttpsURLConnection) new URL(url).openConnection();
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(12000);
        connection.setReadTimeout(18000);
        if (connection.getResponseCode() != 200) {
            connection.disconnect();
            throw new IOException("Resource endpoint unavailable");
        }
        return connection;
    }

    private static long copy(InputStream input, OutputStream output, long limit) throws IOException {
        byte[] buffer = new byte[16384];
        long total = 0;
        for (int bytes; (bytes = input.read(buffer)) != -1;) {
            total += bytes;
            if (total > limit || Thread.currentThread().isInterrupted()) throw new IOException("Resource transfer stopped");
            output.write(buffer, 0, bytes);
        }
        return total;
    }
}
