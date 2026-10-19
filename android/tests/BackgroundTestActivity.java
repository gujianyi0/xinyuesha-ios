// SPDX-License-Identifier: GPL-3.0-or-later
package org.notify.FreeKill;
import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;
import android.content.Intent;
import android.net.Uri;
import android.os.Looper;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import java.io.*;
import java.nio.file.Files;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
public final class BackgroundTestActivity extends Activity {
    private Intent select(Uri uri, int expected) throws Exception {
        CountDownLatch complete = new CountDownLatch(1);
        AtomicReference<Intent> delivered = new AtomicReference<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();
        runOnUiThread(() -> {
            boolean accepted = CounterBackgroundImages.intercept(this, 1305, RESULT_OK, new Intent().setData(uri), (code, data) -> {
                try {
                    BackgroundImagesTest.require(Looper.myLooper() == Looper.getMainLooper(), "result delivered on UI thread");
                    BackgroundImagesTest.require(code == expected, "correct activity result");
                    delivered.set(data);
                } catch (Throwable error) { failure.set(error); }
                finally { complete.countDown(); }
            });
            if (!accepted) { failure.set(new AssertionError("document URI must be intercepted")); complete.countDown(); }
        });
        BackgroundImagesTest.require(complete.await(30, TimeUnit.SECONDS), "asynchronous import completes");
        if (failure.get() != null) throw new AssertionError("activity result failure", failure.get());
        return delivered.get();
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        TextView text=new TextView(this);text.setText("Running image import tests");setContentView(text);
        new Thread(() -> {
            String result;
            try {
                File large=new File(getFilesDir(),"large.png");
                try (InputStream in=getAssets().open("large.png");FileOutputStream out=new FileOutputStream(large)) {
                    byte[] buffer=new byte[8192];int count;while((count=in.read(buffer))!=-1)out.write(buffer,0,count);
                }
                BackgroundImagesTest.main(new String[]{new File(getFilesDir(),"outputs").getAbsolutePath(),large.getAbsolutePath()});
                Intent selected = select(Uri.parse("content://" + getPackageName() + ".images/document/42"), RESULT_OK);
                BackgroundImagesTest.require("file".equals(selected.getData().getScheme()), "Qt receives persistent file URI");
                BackgroundImagesTest.require("image/png".equals(selected.getType()), "Qt receives standard PNG MIME type");
                File saved = new File(selected.getData().getPath());
                BackgroundImagesTest.require(saved.isFile() && saved.getCanonicalPath().contains("/assets/backgrounds/"), "image saved in app background directory");
                Bitmap reopened = BitmapFactory.decodeFile(saved.getAbsolutePath());
                BackgroundImagesTest.require(reopened != null && reopened.getWidth() > 0, "forwarded URI reopens independently of document provider");
                reopened.recycle();
                BackgroundImagesTest.require(select(Uri.parse("content://" + getPackageName() + ".images/document/missing"), RESULT_CANCELED) == null, "failed document read cancels Qt selection");
                BackgroundImagesTest.require(saved.isFile(), "failed selection retains existing imported image");
                BackgroundImagesTest.require(!CounterBackgroundImages.intercept(this, 44, RESULT_OK, selected, (code, data) -> {}), "unrelated activity results unchanged");
                result="PASS: real Android document URI, async UI callback, persistent PNG reload, EXIF, SDR, 40 MP input, 50 MP sampling, texture limits and failure preservation";
            } catch(Throwable error) {
                StringWriter writer=new StringWriter();error.printStackTrace(new PrintWriter(writer));result="FAIL: "+writer;
            }
            final String display=result;
            try { Files.write(new File(getFilesDir(),"result.txt").toPath(),result.getBytes("UTF-8")); }
            catch(Exception error) { android.util.Log.e("BackgroundImageTest","Result write failed",error); }
            runOnUiThread(() -> text.setText(display));
        },"ImageFixtureTest").start();
    }
}
