// SPDX-License-Identifier: GPL-3.0-or-later
package org.notify.FreeKill;

import android.app.Activity;
import android.content.Context;
import android.system.Os;
import android.util.Log;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.IOException;
import java.security.MessageDigest;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Refresh only our allowlisted UI payload before Qt loads it, even at equal engine versions.
 *  Applies to both the external files dir (when available) and the app's internal
 *  files dir, which is the working directory when external storage is unavailable.
 */
public final class CounterStartup {
    private CounterStartup() {}
    private static final String[] ORDER = {
        "card-counter/CardCounter.qml", "card-counter/SuitIcon.qml", "card-counter/RoleVoiceControl.qml", "card-counter/CounterHost.qml",
        "card-counter/bootstrap.lua", "card-counter/counter.lua", "card-counter/CounterViewport.qml",
        "card-counter/SocialClient.qml", "card-counter/SocialHost.qml", "card-counter/SocialAuth.js",
        "card-counter/client-shell/main.qml", "Fk/main.qml",
    };
    public static void run(Activity activity) {
        CounterRepoRepair.run(activity);
        try {
            if (activity == null) throw new IOException("Activity unavailable");
            Context context = activity.getApplicationContext();
            if (!"com.cui.freekill.ds".equals(context.getPackageName())) throw new IOException("Unexpected package");
            JSONObject manifest;
            try (InputStream input = context.getAssets().open("res/card-counter/bundled-files.json")) {
                manifest = new JSONObject(new String(read(input), "UTF-8"));
            }
            boolean social = manifest.has("card-counter/SocialHost.qml");
            Map<String, byte[]> payload = new LinkedHashMap<>();
            // Verify the whole payload before changing any installed file.
            for (String relative : ORDER) {
                if (!social && relative.contains("/Social")) continue;
                if (relative.equals("card-counter/RoleVoiceControl.qml") && !manifest.has(relative)) continue;
                String expected = manifest.getString(relative);
                byte[] data;
                try (InputStream input = context.getAssets().open("res/" + relative)) { data = read(input); }
                if (!expected.equals(sha(data))) throw new IOException("Payload checksum mismatch: " + relative);
                payload.put(relative, data);
            }
            Set<File> roots = new LinkedHashSet<>();
            File external = context.getExternalFilesDir(null);
            if (external != null) roots.add(external.getCanonicalFile());
            File internal = context.getFilesDir();
            if (internal != null) roots.add(internal.getCanonicalFile());
            if (roots.isEmpty()) throw new IOException("External files unavailable");
            int updated = 0;
            for (File root : roots) {
                if (!root.isDirectory() && !root.mkdirs()) {
                    Log.w("CounterStartup", "skip unavailable root " + root);
                    continue;
                }
                for (Map.Entry<String, byte[]> entry : payload.entrySet()) {
                    File target = new File(root, entry.getKey());
                    if (Files.isSymbolicLink(target.toPath()) || !target.getCanonicalFile().equals(target.getAbsoluteFile()))
                        throw new IOException("Refusing symlink");
                    if (target.isFile()) {
                        try (InputStream input = new FileInputStream(target)) {
                            if (sha(read(input)).equals(sha(entry.getValue()))) continue;
                        }
                    }
                    File parent = target.getParentFile();
                    if (!parent.isDirectory() && !parent.mkdirs()) throw new IOException("Cannot create payload directory");
                    if (!parent.getCanonicalPath().startsWith(root.getPath() + File.separator)) throw new IOException("Invalid payload path");
                    File stage = new File(parent, target.getName() + ".counter-new");
                    if (Files.isSymbolicLink(stage.toPath()) || !stage.getCanonicalFile().equals(stage.getAbsoluteFile()))
                        throw new IOException("Refusing staging symlink");
                    try (FileOutputStream output = new FileOutputStream(stage)) {
                        output.write(entry.getValue()); output.getFD().sync();
                    }
                    Os.rename(stage.getAbsolutePath(), target.getAbsolutePath());
                    updated++;
                }
                for (String cosmetic : new String[]{"packages/gujianyi_title/GujianyiTitle.qml", "card-counter/gujianyi_title/GujianyiTitle.qml"}) {
                File legacy = new File(root, cosmetic);
                if (legacy.isFile()) {
                    if (Files.isSymbolicLink(legacy.toPath()) || !legacy.getCanonicalFile().equals(legacy.getAbsoluteFile()))
                        throw new IOException("Refusing legacy cosmetic symlink");
                    String oldHash;
                    try (InputStream input = new FileInputStream(legacy)) { oldHash = sha(read(input)); }
                    if ((oldHash.equals("98b0c0cf19b25be4cf768f6f249d4d12b6768888bc58c032f1b9d5fb2d8c7a9f") || oldHash.equals("291cd71455e1ea63f6caa94ce2448db9bf6788f794e833f3447179e0b4ae54e6"))) {
                        if (!legacy.delete()) throw new IOException("Cannot remove old local cosmetic file");
                        File parent = legacy.getParentFile();
                        String[] remaining = parent.list();
                        if (remaining != null && remaining.length == 0) parent.delete();
                    } else Log.w("CounterStartup", "Unrecognized legacy cosmetic retained for manual review");
                }
                }
            }
            Log.i("CounterStartup", "UI payload verified; roots=" + roots.size() + " updated=" + updated);
        } catch (Exception error) {
            Log.e("CounterStartup", "UI update stopped; account and game packages retained", error);
        }
    }
    private static byte[] read(InputStream input) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192]; int count;
        while ((count = input.read(buffer)) != -1) {
            if (output.size() + count > 1048576) throw new IOException("Payload file too large");
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }
    private static String sha(byte[] bytes) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
        StringBuilder result = new StringBuilder();
        for (byte value : digest) result.append(String.format("%02x", value & 255));
        return result.toString();
    }
}
