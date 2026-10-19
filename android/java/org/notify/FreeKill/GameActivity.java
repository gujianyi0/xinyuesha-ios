// SPDX-License-Identifier: GPL-3.0-or-later
package org.notify.FreeKill;
import android.os.Bundle;
import android.content.Intent;
import org.qtproject.qt.android.bindings.QtActivity;

/** Explicitly runs the managed UI updater before the Qt engine opens QML. */
public final class GameActivity extends QtActivity {
    @Override public void onCreate(Bundle state) {
        CounterStartup.run(this);
        super.onCreate(state);
        CounterPackageSources.start(this);
    }
    @Override public void onDestroy() {
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
}
