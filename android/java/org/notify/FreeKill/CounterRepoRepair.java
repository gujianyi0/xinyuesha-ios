// SPDX-License-Identifier: GPL-3.0-or-later
package org.notify.FreeKill;

import android.content.Context;
import android.app.Activity;
import android.os.Process;
import android.system.Os;
import android.system.OsConstants;
import android.util.Log;
import java.io.File;
import java.io.IOException;
import java.util.Arrays;
import java.util.Comparator;

/** Recreate only repository directory inodes using this app's own UID.
 * File contents, Git commits, ownership validation and server checks are kept.
 * A same-filesystem rename of children avoids copying gigabytes of assets.
 * Deterministic staging directories let a subsequent launch roll back an
 * interrupted transition before retrying. No nonempty directory is deleted.
 */
public final class CounterRepoRepair {
    private static final String TAG = "CounterRepoRepair";
    private static final String PREFIX = ".counter-owner-";
    private CounterRepoRepair() {}

    public static synchronized void run(Activity activity) {
        try {
            if (activity == null) throw new IOException("Qt activity unavailable");
            Context context = activity.getApplicationContext();
            if (!"com.cui.freekill.ds".equals(context.getPackageName()))
                throw new IOException("Unexpected package; no files changed");
            File files = context.getExternalFilesDir(null);
            if (files == null) throw new IOException("External files directory unavailable");
            File packages = new File(files.getCanonicalFile(), "packages");
            if (!packages.isDirectory()) return; // normal first install
            File[] children = list(packages);
            // Recover interrupted top-level transitions even if the original
            // repository name was absent from the first directory listing.
            for (File child : children) {
                String name = child.getName();
                if (name.startsWith(PREFIX) && (name.endsWith(".new") || name.endsWith(".old"))) {
                    String repo = name.substring(PREFIX.length(), name.length() - 4);
                    if (validName(repo)) recover(new File(packages, repo));
                }
            }
            children = list(packages);
            Arrays.sort(children, Comparator.comparing(File::getName));
            int checked = 0, repaired = 0;
            for (File repo : children) {
                if (!validName(repo.getName()) || !repo.isDirectory()) continue;
                requireRealDirectory(repo, packages);
                File git = new File(repo, ".git");
                // Recover an interrupted .git transition before testing it.
                recover(git);
                if (!git.isDirectory()) continue; // builtin packs have no repo
                requireRealDirectory(git, repo);
                // ZIP/ADB transports may discard empty refs directories. Git
                // requires refs/ even when every reference is in packed-refs.
                // Recreate directory structure as the application UID, before
                // native libgit2 opens the repository. Never change commits.
                for (String relative : new String[]{"refs", "refs/heads", "refs/tags"}) {
                    File directory = new File(git, relative);
                    if (!directory.isDirectory() && !directory.mkdirs())
                        throw new IOException("Cannot restore Git reference directory");
                    if (!directory.getCanonicalPath().startsWith(git.getCanonicalPath() + File.separator)
                        || OsConstants.S_ISLNK(Os.lstat(directory.getAbsolutePath()).st_mode))
                        throw new IOException("Invalid Git reference directory");
                }
                checked++;
                boolean changed = reown(repo);
                changed = reown(new File(repo, ".git")) || changed;
                if (owner(repo) != Process.myUid() || owner(new File(repo, ".git")) != Process.myUid())
                    throw new IOException("Owner verification failed for " + repo.getName());
                if (changed) {
                    repaired++;
                    Log.i(TAG, "repaired " + repo.getName() + " uid=" + Process.myUid());
                }
            }
            Log.i(TAG, "complete checked=" + checked + " repaired=" + repaired + " uid=" + Process.myUid());
        } catch (Exception error) {
            // Preserve files/staging for a later recovery; never silently relax
            // Git's ownership check or erase a failed package.
            Log.e(TAG, "repair stopped; data retained", error);
        }
    }

    private static boolean validName(String name) {
        return name.matches("[A-Za-z0-9_-]+") && !name.startsWith(".");
    }

    private static File[] list(File dir) throws IOException {
        File[] entries = dir.listFiles();
        if (entries == null) throw new IOException("Cannot list " + dir.getName());
        return entries;
    }

    private static int owner(File file) throws Exception {
        return Os.stat(file.getAbsolutePath()).st_uid;
    }

    private static void requireRealDirectory(File file, File parent) throws Exception {
        if (!file.getCanonicalFile().getParentFile().equals(parent.getCanonicalFile())
            || OsConstants.S_ISLNK(Os.lstat(file.getAbsolutePath()).st_mode))
            throw new IOException("Refusing path outside expected directory: " + file.getName());
    }

    private static void move(File from, File to) throws IOException {
        if (to.exists() || !from.renameTo(to))
            throw new IOException("Rename failed: " + from.getName() + " -> " + to.getName());
    }

    private static void moveChildren(File from, File to) throws IOException {
        for (File child : list(from)) move(child, new File(to, child.getName()));
    }

    private static void removeEmpty(File file) throws IOException {
        if (file.exists() && (list(file).length != 0 || !file.delete()))
            throw new IOException("Refusing to remove nonempty directory: " + file.getName());
    }

    private static void recover(File dir) throws Exception {
        File parent = dir.getParentFile();
        File stage = new File(parent, PREFIX + dir.getName() + ".new");
        File old = new File(parent, PREFIX + dir.getName() + ".old");
        if (!stage.exists() && !old.exists()) return;
        if (stage.exists()) requireRealDirectory(stage, parent);
        if (old.exists()) requireRealDirectory(old, parent);
        if (dir.exists()) requireRealDirectory(dir, parent);
        if (dir.exists()) {
            // Before the final switch, children may be split between the
            // original directory and the stage. Restore the original layout.
            if (stage.exists()) { moveChildren(stage, dir); removeEmpty(stage); }
            if (old.exists()) removeEmpty(old); // completed switch
        } else if (old.exists()) {
            if (stage.exists()) { moveChildren(stage, old); removeEmpty(stage); }
            move(old, dir);
        } else {
            throw new IOException("Unexpected staging state: " + dir.getName());
        }
        Log.i(TAG, "recovered interrupted transition for " + dir.getName());
    }

    private static boolean reown(File dir) throws Exception {
        recover(dir);
        if (owner(dir) == Process.myUid()) return false;
        File parent = dir.getParentFile();
        File stage = new File(parent, PREFIX + dir.getName() + ".new");
        File old = new File(parent, PREFIX + dir.getName() + ".old");
        if (!stage.mkdir()) throw new IOException("Cannot create owned staging directory");
        try {
            if (owner(stage) != Process.myUid()) throw new IOException("Staging ownership mismatch");
            moveChildren(dir, stage);
            move(dir, old); // original inode is now an empty rollback marker
            move(stage, dir);
            removeEmpty(old);
            return true;
        } catch (Exception error) {
            try { recover(dir); } catch (Exception rollback) { error.addSuppressed(rollback); }
            throw error;
        }
    }
}
