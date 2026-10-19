// SPDX-License-Identifier: GPL-3.0-or-later
package org.notify.FreeKill;
import android.os.Bundle;
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
}
