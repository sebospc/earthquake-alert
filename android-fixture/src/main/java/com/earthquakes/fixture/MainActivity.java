package com.earthquakes.fixture;

import android.Manifest;
import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

public final class MainActivity extends Activity {
    private static final String NORMAL_CHANNEL = "synthetic_normal";
    private static final String FSI_CHANNEL = "synthetic_full_screen";

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        createChannels(this);
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
        }

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        int padding = dp(20);
        layout.setPadding(padding, padding, padding, padding);

        TextView title = new TextView(this);
        title.setText("AEA Synthetic Fixture");
        title.setTextSize(24);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        layout.addView(title);

        TextView warning = new TextView(this);
        warning.setText("Estas alertas son sintéticas. Nunca prueban recepción de Google AEA.");
        warning.setPadding(0, dp(12), 0, dp(12));
        layout.addView(warning);

        layout.addView(button("Publicar notificación normal", () -> publish(this, false)));
        layout.addView(button("Publicar full-screen intent", () -> publish(this, true)));
        layout.addView(button("Solicitar fijación GPS", this::requestGpsFix));
        if (Build.VERSION.SDK_INT >= 34) {
            layout.addView(button("Configurar permiso full-screen", () -> {
                Intent intent = new Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                        .setData(Uri.parse("package:" + getPackageName()));
                startActivity(intent);
            }));
        }
        setContentView(layout);

        String automatedAction = getIntent().getStringExtra("fixture_action");
        if ("normal".equals(automatedAction)) publish(this, false);
        if ("full_screen".equals(automatedAction)) publish(this, true);
        if ("location".equals(automatedAction)) requestGpsFix();
    }

    private static void createChannels(Context context) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        manager.createNotificationChannel(new NotificationChannel(
                NORMAL_CHANNEL, "Synthetic normal", NotificationManager.IMPORTANCE_DEFAULT));
        NotificationChannel full = new NotificationChannel(
                FSI_CHANNEL, "Synthetic full screen", NotificationManager.IMPORTANCE_HIGH);
        full.setDescription("Lab-only full-screen notification");
        manager.createNotificationChannel(full);
    }

    static void publish(Context context, boolean fullScreen) {
        createChannels(context);
        Notification.Builder builder = new Notification.Builder(
                context, fullScreen ? FSI_CHANNEL : NORMAL_CHANNEL)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("SYNTHETIC — Android Earthquake Alerts System")
                .setContentText(fullScreen
                        ? "SYNTHETIC full-screen fixture"
                        : "SYNTHETIC normal fixture")
                .setCategory(Notification.CATEGORY_ALARM)
                .setAutoCancel(true);

        if (fullScreen) {
            Intent alert = new Intent(context, AlertActivity.class)
                    .putExtra("fixture_id", System.currentTimeMillis());
            PendingIntent pending = PendingIntent.getActivity(
                    context, 20, alert,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            builder.setFullScreenIntent(pending, true);
        }

        context.getSystemService(NotificationManager.class)
                .notify(fullScreen ? 2002 : 2001, builder.build());
        Toast.makeText(context, "Fixture publicado", Toast.LENGTH_SHORT).show();
    }

    private void requestGpsFix() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION}, 2);
            return;
        }
        LocationManager manager = getSystemService(LocationManager.class);
        LocationListener listener = new LocationListener() {
            @Override
            public void onLocationChanged(Location location) {
                Toast.makeText(MainActivity.this,
                        location.getLatitude() + ", " + location.getLongitude(),
                        Toast.LENGTH_LONG).show();
            }
        };
        manager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 0, 0, listener);
    }

    private Button button(String text, Runnable action) {
        Button button = new Button(this);
        button.setText(text);
        button.setOnClickListener(view -> action.run());
        return button;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
