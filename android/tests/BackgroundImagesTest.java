// SPDX-License-Identifier: GPL-3.0-or-later
package org.notify.FreeKill;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.media.ExifInterface;
import android.net.Uri;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.file.Files;
public final class BackgroundImagesTest {
    static void require(boolean result, String message) { if (!result) throw new AssertionError(message); }
    public static void main(String[] args) throws Exception {
        System.out.println("TEST: starting Android image fixture");
        File root = new File(args[0]); root.mkdirs();
        File ordinary = new File(root, "orientation.jpg");
        Bitmap fixture = Bitmap.createBitmap(80, 40, Bitmap.Config.ARGB_8888);fixture.eraseColor(Color.RED);
        try (FileOutputStream output = new FileOutputStream(ordinary)) { fixture.compress(Bitmap.CompressFormat.JPEG,95,output); }
        fixture.recycle();
        ExifInterface exif = new ExifInterface(ordinary.getAbsolutePath());
        exif.setAttribute(ExifInterface.TAG_ORIENTATION,"6");exif.saveAttributes();
        System.out.println("TEST: importing oriented JPEG");
        File imported = CounterBackgroundImages.importImage(null,Uri.fromFile(ordinary),root);
        require(imported.getName().endsWith(".jpg"),"opaque photo uses JPEG");
        File repeated = CounterBackgroundImages.importImage(null,Uri.fromFile(ordinary),root);
        require(repeated.equals(imported),"repeated photo reuses content-addressed file");
        Bitmap decoded = BitmapFactory.decodeFile(imported.getAbsolutePath());
        require(decoded.getWidth()==40 && decoded.getHeight()==80,"EXIF orientation preserved");
        int pixel=decoded.getPixel(20,40);
        require(Color.red(pixel)>220 && Color.green(pixel)<40 && Color.blue(pixel)<40,"normalized image preserves visible color");
        require(!decoded.hasGainmap(),"output is an ordinary SDR image");decoded.recycle();
        int sample=CounterBackgroundImages.sampleSize(8160,6120);
        require((long)((8160+sample-1)/sample)*((6120+sample-1)/sample)<=8000000,"50 MP decode memory bound");
        File large = new File(args[1]);
        System.out.println("TEST: importing 40 MP PNG with bounded sampling");
        File largeOutput=CounterBackgroundImages.importImage(null,Uri.fromFile(large),root);
        decoded=BitmapFactory.decodeFile(largeOutput.getAbsolutePath());
        require(decoded.getWidth()<=2560 && decoded.getHeight()<=2560,"large texture edge bound");
        require((long)decoded.getWidth()*decoded.getHeight()<=4000000,"large output pixel bound");
        pixel=decoded.getPixel(0,0);
        require(Color.red(pixel)<60 && Color.green(pixel)>140 && Color.green(pixel)<220 && Color.blue(pixel)<100,"large image not white or blank");decoded.recycle();
        File bad = new File(root,"bad.png");Files.write(bad.toPath(),new byte[]{1,2,3});
        long before=imported.length();
        try { CounterBackgroundImages.importImage(null,Uri.fromFile(bad),root);throw new AssertionError("corrupt image must fail"); }
        catch (java.io.IOException expected) {}
        require(imported.isFile() && imported.length()==before,"failed import preserves previous generated image");
        System.out.println("PASS: image import, EXIF, SDR, 50 MP sampling, bounded textures and failed-import preservation");
    }
}
