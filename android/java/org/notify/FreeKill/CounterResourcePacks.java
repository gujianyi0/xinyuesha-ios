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
    private static final String HOST = "https://preview.gujianyi-web-preview.pages.dev";
    private static final String CATALOG = HOST + "/xinyuesha/resource-packs/v1/catalog.json";
    private static final long MAX_ARCHIVE = 192L * 1024 * 1024;
    private static final long MAX_UNPACKED = 256L * 1024 * 1024;
    private static final int MAX_CATALOG = 64 * 1024;
    private static ScheduledExecutorService worker;

    private CounterResourcePacks() {}

    static synchronized void start(Activity activity) {
        if (worker != null) return;
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
        Path request = bridge.resolve("request.json");
        if (!Files.isRegularFile(request, LinkOption.NOFOLLOW_LINKS) || Files.size(request) > 1024) return;
        JSONObject input;
        try {
            input = new JSONObject(new String(Files.readAllBytes(request), StandardCharsets.UTF_8));
        } catch (org.json.JSONException unfinishedWrite) {
            return;
        }
        String id = input.getString("id");
        Files.deleteIfExists(request);
        if (!id.matches("[0-9_-]{1,48}")) return;
        JSONObject reply = new JSONObject().put("id", id).put("ok", false);
        try {
            String operation = input.getString("operation");
            JSONArray packs = operation.equals("uninstall") ? new JSONArray() : catalog();
            switch (input.getString("operation")) {
                case "uninstall":
                    String removed = input.getString("pack");
                    uninstall(root, removed);
                    reply.put("pack", removed);
                    break;
                case "catalog":
                    reply.put("packs", packs);
                    break;
                case "install":
                    JSONObject pack = find(packs, input.getString("pack"));
                    install(root, bridge, pack);
                    reply.put("pack", pack.getString("id"));
                    break;
                default:
                    throw new IOException("Invalid request");
            }
            reply.put("ok", true);
        } catch (Exception error) {
            reply.put("error", "资源包请求失败，请检查网络后重试。");
            Log.w("ResourcePacks", "Catalog or download failed", error);
        }
        Path stagedReply = Files.createTempFile(bridge, "reply-", ".json");
        try {
            Files.write(stagedReply, reply.toString().getBytes(StandardCharsets.UTF_8));
            Files.move(stagedReply, bridge.resolve("reply.json"),
                    StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
        } finally {
            Files.deleteIfExists(stagedReply);
        }
    }

    private static JSONArray catalog() throws Exception {
        JSONArray embedded=CounterEmbeddedPacks.catalog();
        if(embedded!=null)return embedded;
        HttpsURLConnection connection = connect(CATALOG);
        try (InputStream input = connection.getInputStream(); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            copy(input, output, MAX_CATALOG);
            JSONObject catalog = new JSONObject(new String(output.toByteArray(), StandardCharsets.UTF_8));
            if (catalog.getInt("schema") != 1) throw new IOException("Unsupported resource catalog schema");
            JSONArray packs = catalog.getJSONArray("packs");
            if (packs.length() > 32) throw new IOException("Too many resource packs");
            for (int index = 0; index < packs.length(); index++) {
                JSONObject pack = packs.getJSONObject(index);
                if (!pack.getString("id").matches("[A-Za-z0-9_\\-\\p{IsHan}]{1,64}")
                        || !pack.getString("archive").matches("[A-Za-z0-9_-]{1,96}\\.zip")
                        || !pack.getString("sha256").matches("[a-f0-9]{64}")
                        || pack.getLong("bytes") <= 0 || pack.getLong("bytes") > MAX_ARCHIVE
                        || pack.getString("title").length() > 80 || pack.getString("version").length() > 32)
                    throw new IOException("Invalid resource pack metadata");
            }
            return packs;
        } finally {
            connection.disconnect();
        }
    }

    private static JSONObject find(JSONArray packs, String id) throws Exception {
        for (int index = 0; index < packs.length(); index++) {
            JSONObject pack = packs.getJSONObject(index);
            if (pack.getString("id").equals(id)) return pack;
        }
        throw new IOException("Resource pack unavailable");
    }

    private static void install(Path root, Path bridge, JSONObject pack) throws Exception {
        Path packs = root.resolve("resource_pak");
        Files.createDirectories(packs);
        Path destination = packs.resolve(pack.getString("id"));
        if (Files.isDirectory(destination, LinkOption.NOFOLLOW_LINKS)) return;

        Path temporary = Files.createTempDirectory(bridge, "install-");
        try {
            Path archive = temporary.resolve("resource.zip");
            download(pack, archive);
            Path extracted = Files.createDirectory(temporary.resolve("pack"));
            extract(archive, extracted);
            Files.move(extracted, destination, StandardCopyOption.ATOMIC_MOVE);
        } finally {
            try (java.util.stream.Stream<Path> paths = Files.walk(temporary)) {
                for (Path path : (Iterable<Path>) paths.sorted(Comparator.reverseOrder())::iterator)
                    Files.deleteIfExists(path);
            }
        }
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

    private static void download(JSONObject pack, Path archive) throws Exception {
        if(pack.optBoolean("bundled",false)){CounterEmbeddedPacks.copy(pack,archive);return;}
        long bytes = pack.getLong("bytes");
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        HttpsURLConnection connection = connect(HOST + "/download/xinyuesha/resource-packs/" + pack.getString("archive"));
        try (InputStream input = new DigestInputStream(connection.getInputStream(), digest);
             OutputStream output = Files.newOutputStream(archive, StandardOpenOption.CREATE_NEW)) {
            if (copy(input, output, bytes) != bytes) throw new IOException("Incomplete resource pack");
        } finally {
            connection.disconnect();
        }
        StringBuilder hash = new StringBuilder();
        for (byte value : digest.digest()) hash.append(String.format(Locale.ROOT, "%02x", value & 255));
        if (!hash.toString().equals(pack.getString("sha256"))) throw new IOException("Resource checksum differs");
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
