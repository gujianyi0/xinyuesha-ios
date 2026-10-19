// SPDX-License-Identifier: GPL-3.0-or-later
package org.notify.FreeKill;

import android.app.Activity;
import android.content.ContentValues;
import android.database.sqlite.SQLiteDatabase;
import android.system.Os;
import android.util.Log;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.net.URI;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;

/** App-owned bridge for PackMan's missing cross-server origin synchronization.
 * No Lua sandbox changes, shell execution, account access, hash overrides, or
 * game-source edits. QML pauses the stock downloader until this acknowledges.
 */
public final class CounterPackageSources {
    private static ScheduledExecutorService worker;
    private static final Map<String, String> completed = new HashMap<>();
    private CounterPackageSources() {}

    public static synchronized void start(Activity activity) {
        stop();
        if (!"com.cui.freekill.ds".equals(activity.getPackageName())) return;
        final Set<File> roots = new LinkedHashSet<>();
        File external = activity.getExternalFilesDir(null);
        if (external != null) roots.add(external);
        roots.add(activity.getFilesDir());
        worker = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread thread = new Thread(r, "PackageSources"); thread.setDaemon(true); return thread;
        });
        worker.scheduleWithFixedDelay(() -> {
            for (File root : roots) {
                try { process(root.getCanonicalFile()); }
                catch (Exception error) { Log.e("PackageSources", "Source synchronization stopped; resources retained", error); }
            }
        }, 0, 250, TimeUnit.MILLISECONDS);
    }

    public static synchronized void stop() {
        if (worker != null) { worker.shutdown(); worker = null; }
    }

    private static void requireWithin(File file, File root) throws Exception {
        if (!file.getCanonicalPath().startsWith(root.getCanonicalPath() + File.separator)
                || !file.getCanonicalFile().equals(file.getAbsoluteFile())
                || Files.isSymbolicLink(file.toPath())) throw new IOException("Invalid synchronization path");
    }

    private static byte[] read(File file) throws IOException {
        try (InputStream input = new FileInputStream(file); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096]; int size;
            while ((size = input.read(buffer)) != -1) {
                if (output.size() + size > 262144) throw new IOException("Source metadata too large");
                output.write(buffer, 0, size);
            }
            return output.toByteArray();
        }
    }

    private static void writeAtomic(File target, byte[] bytes, File root) throws Exception {
        requireWithin(target, root);
        File stage = new File(target.getParentFile(), target.getName() + ".source-new");
        requireWithin(stage, root);
        try (FileOutputStream output = new FileOutputStream(stage)) { output.write(bytes); output.getFD().sync(); }
        if (!Arrays.equals(read(stage), bytes)) throw new IOException("Source metadata verification failed");
        Os.rename(stage.getAbsolutePath(), target.getAbsolutePath());
    }

    public static String rewrite(String config, String url) throws IOException {
        String newline = config.contains("\r\n") ? "\r\n" : "\n";
        List<String> output = new ArrayList<>();
        boolean origin = false, found = false, wrote = false;
        String normalized = config.replace("\r\n", "\n");
        if (normalized.endsWith("\n")) normalized = normalized.substring(0, normalized.length() - 1);
        for (String line : normalized.split("\n", -1)) {
            if (line.trim().startsWith("[")) {
                if (origin && !wrote) output.add("\turl = " + url);
                origin = line.trim().matches("(?i)\\[\\s*remote\\s+\"origin\"\\s*\\]\\s*([#;].*)?");
                if (origin) {
                    if (found) throw new IOException("Duplicate Git origin section");
                    found = true; wrote = false;
                }
            }
            if (origin && line.matches("(?i)\\s*url\\s*=.*")) {
                if (!wrote) { output.add("\turl = " + url); wrote = true; }
            } else output.add(line);
        }
        if (origin && !wrote) output.add("\turl = " + url);
        if (!found) {
            output.add("[remote \"origin\"]"); output.add("\turl = " + url);
            output.add("\tfetch = +refs/heads/*:refs/remotes/origin/*");
        }
        return String.join(newline, output) + newline;
    }

    private static void validate(String name, String url) throws Exception {
        if (!name.matches("[A-Za-z0-9_-]{1,128}") || url.length() > 2048 || !url.matches("[\\x21-\\x7e]+"))
            throw new IOException("Invalid server package metadata");
        URI uri = new URI(url);
        if (!("https".equals(uri.getScheme()) || "http".equals(uri.getScheme()))
                || uri.getHost() == null || uri.getUserInfo() != null || uri.getFragment() != null
                || url.contains("\"") || url.contains("\\")) throw new IOException("Invalid package source URL");
    }

    private static void process(File root) throws Exception {
        File request = new File(root, "assets/package-sync/request.json");
        if (!request.isFile()) return;
        requireWithin(request, root);
        byte[] raw = read(request);
        String key = root.getPath();
        String digest = Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-256").digest(raw));
        if (digest.equals(completed.get(key))) return;
        JSONObject input = new JSONObject(new String(raw, "UTF-8"));
        String id = input.getString("id");
        if (!id.matches("[A-Za-z0-9_-]{1,96}")) throw new IOException("Invalid request id");
        JSONObject reply = new JSONObject().put("id", id).put("ok", false);
        try {
            JSONArray packages = input.getJSONArray("packages");
            if (packages.length() > 512) throw new IOException("Too many package sources");
            Map<String,String> requested = new LinkedHashMap<>();
            Map<File,byte[]> before = new LinkedHashMap<>(), after = new LinkedHashMap<>();
            for (int index=0; index<packages.length(); index++) {
                JSONObject item = packages.getJSONObject(index);
                String name = item.getString("name"), url = item.getString("url");
                validate(name,url);
                if (requested.put(name,url) != null) throw new IOException("Duplicate package name");
                File git = new File(root, "packages/" + name + "/.git");
                requireWithin(git, root);
                if (!git.exists()) continue; // normal native clone
                File config = new File(git,"config"); requireWithin(config,root);
                byte[] old = read(config), next = rewrite(new String(old,"UTF-8"),url).getBytes("UTF-8");
                if (!Arrays.equals(old,next)) { before.put(config,old); after.put(config,next); }
            }
            for (File config : before.keySet()) {
                if (!Arrays.equals(read(config),before.get(config))) throw new IOException("Git config changed concurrently");
                File backup = new File(config.getParentFile(),"config.before-server-source");
                requireWithin(backup,root);
                if (!backup.exists()) writeAtomic(backup,before.get(config),root);
                writeAtomic(config,after.get(config),root);
            }
            File database = new File(root,"packages/packages.db"); requireWithin(database,root);
            if (database.isFile()) {
                try (SQLiteDatabase db = SQLiteDatabase.openDatabase(database.getPath(),null,SQLiteDatabase.OPEN_READWRITE)) {
                    db.beginTransaction();
                    try {
                        for (Map.Entry<String,String> entry : requested.entrySet()) {
                            ContentValues values = new ContentValues(); values.put("url",entry.getValue());
                            db.update("packages",values,"name = ?",new String[]{entry.getKey()});
                        }
                        db.setTransactionSuccessful();
                    } finally { db.endTransaction(); }
                }
            }
            reply.put("ok",true).put("changed",after.size());
            Log.i("PackageSources","Synchronized " + after.size() + " download sources; native checks retained");
        } catch (Exception error) {
            reply.put("error","扩展包下载源同步失败，资源已保留，请重新启动后重试。");
            Log.e("PackageSources","Preparation failed; native download blocked",error);
        }
        writeAtomic(new File(request.getParentFile(),"reply.json"),reply.toString().getBytes("UTF-8"),root);
        completed.put(key,digest);
    }
}
