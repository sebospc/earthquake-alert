package com.earthquakes.fixture;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.TextView;

public final class AlertActivity extends Activity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        TextView text = new TextView(this);
        text.setText("SYNTHETIC\nFULL-SCREEN TEST\n\nEsto no es una alerta de Google.");
        text.setTextSize(28);
        text.setTypeface(Typeface.DEFAULT_BOLD);
        text.setTextColor(Color.WHITE);
        text.setBackgroundColor(Color.rgb(179, 38, 30));
        text.setGravity(Gravity.CENTER);
        text.setOnClickListener(view -> finish());
        setContentView(text);
    }
}
