// SPDX-License-Identifier: GPL-3.0-or-later
package org.notify.FreeKill;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.media.ExifInterface;
import android.net.Uri;
import android.system.Os;
import android.util.Log;
import android.widget.Toast;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Import selected still images before Qt attempts to decode the original URI.
 * Keeps provider permissions, large/HDR photos and Qt texture allocations out
 * of the rendering path. Only generated app-owned images are written.
 */
public final class CounterBackgroundImages {
    private CounterBackgroundImages() {}
    public interface Result { void deliver(int result, Intent data); }
    private static final ExecutorService WORKER = Executors.newSingleThreadExecutor(r -> {
        Thread thread = new Thread(r, "BackgroundImageImport"); thread.setDaemon(true); return thread;
    });
    private static final int MAX_EDGE = 2560;
    private static final long MAX_DECODE_PIXELS = 8000000;
    private static final long MAX_OUTPUT_PIXELS = 4000000;

    public static boolean intercept(Activity activity, int request, int result, Intent data, Result callback) {
        // Qt's document picker request, not arbitrary activity results.
        if (request != 1305 || result != Activity.RESULT_OK || data == null || data.getData() == null
                || data.getClipData() != null) return false;
        Uri uri = data.getData();
        String scheme = uri.getScheme();
        if (!("content".equals(scheme) || "file".equals(scheme))) return false;
        String mime = data.getType();
        try { if (mime == null) mime = activity.getContentResolver().getType(uri); }
        catch (Exception ignored) { /* Some providers do not expose MIME metadata. */ }
        String path = String.valueOf(uri.getPath()).toLowerCase(Locale.ROOT);
        if ("image/gif".equals(mime) || path.endsWith(".gif")) return false;
        if (!(mime != null && mime.startsWith("image/")) &&
                !path.matches(".*\\.(png|jpe?g|webp|heic|heif|bmp|avif)$")) return false;
        final Intent original = new Intent(data);
        WORKER.execute(() -> {
            try {
                File root = activity.getExternalFilesDir(null);
                if (root == null) root = activity.getFilesDir();
                File image = importImage(activity.getContentResolver(), uri, root);
                Intent converted = new Intent(original);
                converted.setDataAndType(Uri.fromFile(image), "image/png");
                activity.runOnUiThread(() -> {
                    if (!activity.isFinishing() && !activity.isDestroyed()) callback.deliver(Activity.RESULT_OK, converted);
                });
                Log.i("BackgroundImages", "Selected image normalized and stored in app files");
            } catch (Exception | OutOfMemoryError error) {
                // Do not forward an unreadable or excessively large original.
                // Qt rejects the selection and the existing background survives.
                Log.w("BackgroundImages", "Image import failed; previous background retained: " + error.getClass().getSimpleName());
                activity.runOnUiThread(() -> {
                    if (!activity.isFinishing() && !activity.isDestroyed()) {
                        Toast.makeText(activity, "图片无法读取，已保留原背景；请换一张图片重试", Toast.LENGTH_LONG).show();
                        callback.deliver(Activity.RESULT_CANCELED, null);
                    }
                });
            }
        });
        return true;
    }

    private static InputStream open(ContentResolver resolver, Uri uri) throws IOException {
        InputStream stream = "file".equals(uri.getScheme()) ? new FileInputStream(new File(uri.getPath())) : resolver.openInputStream(uri);
        if (stream == null) throw new IOException("Image stream unavailable");
        return stream;
    }

    static int sampleSize(int width, int height) throws IOException {
        if (width <= 0 || height <= 0) throw new IOException("Unsupported image");
        int sample = 1;
        while (((long)width + sample - 1) / sample * (((long)height + sample - 1) / sample) > MAX_DECODE_PIXELS)
            sample *= 2;
        return sample;
    }

    static File importImage(ContentResolver resolver, Uri uri, File root) throws Exception {
        BitmapFactory.Options options = new BitmapFactory.Options(); options.inJustDecodeBounds = true;
        try (InputStream input = open(resolver, uri)) { BitmapFactory.decodeStream(input, null, options); }
        options.inSampleSize = sampleSize(options.outWidth, options.outHeight);
        options.inJustDecodeBounds = false; options.inPreferredConfig = Bitmap.Config.ARGB_8888;
        int orientation = ExifInterface.ORIENTATION_NORMAL;
        try (InputStream input = open(resolver, uri)) {
            orientation = new ExifInterface(input).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
        } catch (IOException ignored) { /* Valid formats may not contain EXIF. */ }
        Bitmap decoded = null, oriented = null, normalized = null;
        File stage = null;
        try {
            try (InputStream input = open(resolver, uri)) { decoded = BitmapFactory.decodeStream(input, null, options); }
            if (decoded == null) throw new IOException("Image decode failed");
            Matrix transform = new Matrix();
            switch (orientation) {
                case ExifInterface.ORIENTATION_FLIP_HORIZONTAL: transform.setScale(-1, 1); break;
                case ExifInterface.ORIENTATION_ROTATE_180: transform.setRotate(180); break;
                case ExifInterface.ORIENTATION_FLIP_VERTICAL: transform.setScale(1, -1); break;
                case ExifInterface.ORIENTATION_TRANSPOSE: transform.setRotate(90); transform.postScale(-1, 1); break;
                case ExifInterface.ORIENTATION_ROTATE_90: transform.setRotate(90); break;
                case ExifInterface.ORIENTATION_TRANSVERSE: transform.setRotate(-90); transform.postScale(-1, 1); break;
                case ExifInterface.ORIENTATION_ROTATE_270: transform.setRotate(-90); break;
            }
            oriented = Bitmap.createBitmap(decoded, 0, 0, decoded.getWidth(), decoded.getHeight(), transform, true);
            double scale = Math.min(1.0, (double)MAX_EDGE / Math.max(oriented.getWidth(), oriented.getHeight()));
            scale = Math.min(scale, Math.sqrt((double)MAX_OUTPUT_PIXELS / ((long)oriented.getWidth() * oriented.getHeight())));
            int width = Math.max(1, (int)Math.floor(oriented.getWidth() * scale));
            int height = Math.max(1, (int)Math.floor(oriented.getHeight() * scale));
            // A software ARGB target normalizes wide-gamut/HDR metadata to a
            // conventional SDR image that Qt can load on all supported devices.
            normalized = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
            normalized.setHasAlpha(oriented.hasAlpha());
            new Canvas(normalized).drawBitmap(oriented, null, new android.graphics.Rect(0,0,width,height), new Paint(Paint.FILTER_BITMAP_FLAG));
            File directory = new File(root.getCanonicalFile(), "assets/backgrounds");
            if (!directory.getCanonicalPath().startsWith(root.getCanonicalPath() + File.separator)
                    || java.nio.file.Files.isSymbolicLink(directory.toPath())) throw new IOException("Invalid image directory");
            if (!directory.isDirectory() && !directory.mkdirs()) throw new IOException("Image directory unavailable");
            boolean opaque = !oriented.hasAlpha();
            String suffix = opaque ? ".jpg" : ".png";
            stage = new File(directory, "selected-" + UUID.randomUUID() + ".new");
            try (FileOutputStream output = new FileOutputStream(stage)) {
                if (!normalized.compress(opaque ? Bitmap.CompressFormat.JPEG : Bitmap.CompressFormat.PNG, opaque ? 90 : 100, output)) throw new IOException("Image encode failed");
                output.getFD().sync();
            }
            java.security.MessageDigest hash = java.security.MessageDigest.getInstance("SHA-256");
            try (InputStream bytes = new java.io.FileInputStream(stage)) {
                byte[] buffer = new byte[65536]; int count;
                while ((count = bytes.read(buffer)) != -1) hash.update(buffer, 0, count);
            }
            StringBuilder key = new StringBuilder();
            for (byte value : hash.digest()) key.append(String.format(java.util.Locale.ROOT, "%02x", value & 255));
            File image = new File(directory, key.toString() + suffix);
            if (java.nio.file.Files.isSymbolicLink(image.toPath())) throw new IOException("Invalid image target");
            // The key is a digest of these exact encoded bytes. Atomic rename
            // replaces that same owned destination, never an arbitrary path.
            Os.rename(stage.getAbsolutePath(), image.getAbsolutePath()); stage = null;
            return image;
        } finally {
            if (stage != null) stage.delete();
            if (normalized != null) normalized.recycle();
            if (oriented != null && oriented != decoded) oriented.recycle();
            if (decoded != null) decoded.recycle();
        }
    }
}
