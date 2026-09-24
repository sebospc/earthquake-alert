#!/usr/bin/env python3
"""Checks the logic that decides whether a captured notification is an alert.

Run: python3 scripts/test_lab.py
"""
import importlib.util, os, sys

spec = importlib.util.spec_from_file_location(
    "lab", os.path.join(os.path.dirname(os.path.abspath(__file__)), "lab.py"))
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


def gms(title, text, channel="unknown"):
    return {"event_type": "NOTIFICATION_POSTED", "source_label": "GMS_CANDIDATE",
            "channel_id": channel,
            "selected_extras": {"android.title": title, "android.text": text}}


# A real Colombian BeAware alert reads like this.
assert lab.is_quake_text(gms("Alerta de sismo", "Sismo cerca de Bucaramanga. Protégete."))
assert lab.is_quake_text(gms("Earthquake nearby", "Light shaking expected"))
assert lab.is_quake_text(gms("Temblor", "Magnitud 5.1"))
assert lab.is_quake_text(gms("Aviso", "nada", channel="earthquake_alerts"))

# Play Services posts plenty of unrelated notifications; those must stay quiet.
assert not lab.is_quake_text(gms("Google Play services", "Actualización disponible"))
assert not lab.is_quake_text(gms("Copia de seguridad", "Se completó la copia"))

# Radius table, checked against values read off the published alert list.
assert round(lab.beaware_radius_km(4.5)) == 31
assert round(lab.beaware_radius_km(5.0)) == 78
assert round(lab.beaware_radius_km(6.3)) == 405
assert lab.beaware_radius_km(4.4) == 0, "below M4.5 Google issues no alert"
assert lab.beaware_radius_km(None) == 0
# Interpolation stays inside the bracketing table entries.
assert 78 < lab.beaware_radius_km(5.05) < 94

# Distance: Bucaramanga sits inside the radius of a M5.0 under the nest.
nest_lat, nest_lon = 6.83, -73.09
bucaramanga = next(c for c in lab.FLEET if c[1] == "bucaramanga-a")
distance = lab.km_between(bucaramanga[2], bucaramanga[3], nest_lat, nest_lon)
assert distance <= lab.beaware_radius_km(5.0), f"{distance:.0f}km should be covered"

# Quibdo must not be flagged for that same event.
quibdo = next(c for c in lab.FLEET if c[1] == "quibdo")
assert lab.km_between(quibdo[2], quibdo[3], nest_lat, nest_lon) > lab.beaware_radius_km(5.0)

# Classification against the notifications actually captured on 23/24-sep.
def real(channel, title, text, signer=lab.PLAY_SERVICES_SIGNER):
    event = gms(title, text, channel)
    event["package_signer_sha256"] = signer
    return event

assert lab.classify(real("eew_alert_v2", "Earthquake nearby",
                         "Expect shaking. Initial estimate M4.5 about 12.1 miles away.")) == "ALERT"
assert lab.classify(real("eew_update", "Earthquake at 3:09 PM",
                         "You may have felt shaking. Initial estimate M4.5")) == "UPDATE"
assert lab.classify(real("finder-configuration", "Find My Device",
                         "This device is now part of the network")) is None
# A renamed channel must reach a human, not vanish.
assert lab.classify(real("eew_alert_v3", "Earthquake nearby", "x")) == "ALERT"
assert lab.classify(real("seismic_new", "Earthquake nearby", "Expect shaking")) == "REVIEW"
# Same package name, wrong signer: never counted as a real alert.
assert lab.classify(real("eew_alert_v2", "Earthquake nearby", "x", signer="00" * 32)) == "REVIEW"
assert lab.classify(real("eew_alert_v2", "Earthquake nearby", "x", signer="UNAVAILABLE:X")) == "REVIEW"

print("PASS quake text classification")
print("PASS radius table and edges")
print("PASS coverage geometry per device")
