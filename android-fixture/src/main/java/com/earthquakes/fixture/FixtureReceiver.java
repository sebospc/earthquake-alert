package com.earthquakes.fixture;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class FixtureReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if ("com.earthquakes.fixture.POST_NORMAL".equals(action)) {
            MainActivity.publish(context, false);
        } else if ("com.earthquakes.fixture.POST_FULL_SCREEN".equals(action)) {
            MainActivity.publish(context, true);
        }
    }
}
