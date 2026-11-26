// SPDX-License-Identifier: GPL-3.0-or-later
package org.notify.FreeKill;
import android.os.Bundle;
import android.content.Intent;
import org.qtproject.qt.android.bindings.QtActivity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import java.lang.ref.WeakReference;

/** Explicitly runs the managed UI updater before the Qt engine opens QML. */
public final class GameActivity extends QtActivity {
    private static volatile WeakReference<GameActivity> activeActivity = new WeakReference<>(null);
    @Override public void onCreate(Bundle state) {
        activeActivity = new WeakReference<>(this);
        CounterStartup.run(this);
        CounterEmbeddedPacks.prepare(this);
        super.onCreate(state);
        CounterEmbeddedPacks.start();
        CounterPackageSources.start(this);
        CounterResourcePacks.start(this);
    }
    @Override public void onDestroy() {
        if (activeActivity.get() == this) activeActivity.clear();
        CounterEmbeddedPacks.stop();
        CounterResourcePacks.stop();
        CounterPackageSources.stop();
        super.onDestroy();
    }
    @Override protected void onActivityResult(int request, int result, Intent data) {
        if (!CounterBackgroundImages.intercept(this, request, result, data,
                (convertedResult, convertedData) -> finishImageSelection(request, convertedResult, convertedData)))
            super.onActivityResult(request, result, data);
    }
    private void finishImageSelection(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
    }
    public static boolean playGameHaptic(int kind) {
        GameActivity activity = activeActivity.get();
        if (activity == null || activity.isFinishing() || kind < 0 || kind > 2) return false;
        final int effect = kind == 0 ? HapticFeedbackConstants.LONG_PRESS :
                kind == 1 ? HapticFeedbackConstants.CLOCK_TICK : HapticFeedbackConstants.VIRTUAL_KEY;
        activity.runOnUiThread(() -> {
            if (activity.isFinishing() || !activity.hasWindowFocus()) return;
            View view = activity.getWindow().getDecorView();
            // Respect both system and view settings; no ignore-setting flags.
            view.performHapticFeedback(effect);
        });
        return true;
    }
}
