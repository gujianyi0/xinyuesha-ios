// SPDX-License-Identifier: GPL-3.0-or-later
package org.notify.FreeKill;

import android.app.Activity;
import android.content.Context;
import android.util.Log;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.Arrays;
import java.util.concurrent.*;

/** Optional, isolated APK edition. Standard APKs contain no embedded-effects assets. */
final class CounterEmbeddedPacks {
    private static final String PREFIX="embedded-effects/";
    private static Context context;
    private static Path root;
    private static JSONObject catalog;
    private static ExecutorService worker;
    private static int generation;

    static synchronized void prepare(Activity activity) {
        context=activity.getApplicationContext();catalog=null;
        try {
            File external=context.getExternalFilesDir(null);
            root=(external==null?context.getFilesDir():external).getCanonicalFile().toPath();
            String[] assets=context.getAssets().list("embedded-effects");
            if (assets==null || !Arrays.asList(assets).contains("catalog.json")) {
                Files.deleteIfExists(BundledPackInstaller.safe(root,"assets/effect-bundle/state.json"));
                return;
            }
            try (InputStream input=context.getAssets().open(PREFIX+"catalog.json")) {
                ByteArrayOutputStream data=new ByteArrayOutputStream();byte[] buffer=new byte[16384];int count;
                while ((count=input.read(buffer))!=-1) {data.write(buffer,0,count);if(data.size()>512*1024)throw new IOException("Catalog too large");}
                catalog=new JSONObject(new String(data.toByteArray(),StandardCharsets.UTF_8));
                BundledPackInstaller.validate(catalog);
            }
            state("preparing","正在准备内置特效",0,3);
        } catch (Exception error) {
            Log.e("EmbeddedPacks","Cannot prepare effects",error);
            try {state("error","内置资源校验失败，请重新安装完整体验版。",0,3);}catch(Exception ignored){}
        }
    }
    static synchronized JSONArray catalog() throws Exception {
        if (catalog==null) return null;
        JSONArray result=new JSONArray(),packs=catalog.getJSONArray("packs");
        for(int i=0;i<packs.length();i++) {
            JSONObject pack=new JSONObject(packs.getJSONObject(i).toString());pack.remove("files");pack.put("bundled",true);result.put(pack);
        }
        return result;
    }
    static synchronized void copy(JSONObject pack,Path destination) throws Exception {
        if(catalog==null)throw new IOException("Embedded catalog unavailable");
        JSONObject verified=null;JSONArray packs=catalog.getJSONArray("packs");
        for(int i=0;i<packs.length();i++)if(packs.getJSONObject(i).getString("id").equals(pack.getString("id")))verified=packs.getJSONObject(i);
        if(verified==null)throw new IOException("Unknown embedded resource");
        BundledPackInstaller.copyVerified(name->context.getAssets().open(PREFIX+name),verified,destination);
    }
    private static void state(String status,String title,int completed,int total)throws Exception {
        BundledPackInstaller.writeJson(BundledPackInstaller.safe(root,"assets/effect-bundle/state.json"),new JSONObject()
            .put("required",true).put("state",status).put("title",title).put("completed",completed).put("total",total));
    }
    static synchronized void start() {
        if(catalog==null || worker!=null)return;
        final int own=++generation;final Path directory=root;final JSONObject bundle=catalog;final Context app=context;
        worker=Executors.newSingleThreadExecutor();
        worker.submit(()->{
            while(!Thread.currentThread().isInterrupted()) {
                try {
                    BundledPackInstaller.install(directory,bundle,name->app.getAssets().open(PREFIX+name),CounterResourcePacks::extract,
                        (title,completed,total)->{synchronized(CounterEmbeddedPacks.class){if(own!=generation)throw new InterruptedIOException();state("preparing",title,completed,total);}});
                    synchronized(CounterEmbeddedPacks.class){if(own==generation)state("ready","内置特效已就绪",3,3);}
                    return;
                }catch(Exception error){
                    Log.e("EmbeddedPacks","Resource preparation failed",error);
                    synchronized(CounterEmbeddedPacks.class){if(own!=generation)return;try{state("error","资源准备未完成，请确认存储空间后重试。",0,3);}catch(Exception ignored){}}
                    try{
                        Path retry=BundledPackInstaller.safe(directory,"assets/effect-bundle/retry.json");
                        while(!Files.exists(retry,LinkOption.NOFOLLOW_LINKS))Thread.sleep(500);
                        Files.delete(retry);
                    }catch(Exception stopped){return;}
                }
            }
        });
    }
    static synchronized void stop(){generation++;if(worker!=null){worker.shutdownNow();worker=null;}}
}
