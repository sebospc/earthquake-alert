#!/usr/bin/env python3
"""Watchdog for the AEA emulator fleet.

Four jobs, all of which have to keep working for a months-long passive run to
mean anything:

  captures   pull each emulator's evidence log and surface new GMS notifications
  heartbeat  notice when an emulator dies instead of reading silence as "no quake"
  canary     inject a synthetic alert daily; if it stops arriving the chain broke
  expect     poll USGS and, using Google's own published alert radii, flag the
             events that should have alerted a device, so a miss is detectable
"""
import json, math, os, re, subprocess, sys, time, urllib.request, urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SDK = os.environ.get("ANDROID_SDK_ROOT", "/opt/homebrew/share/android-commandlinetools")
ADB = os.path.join(SDK, "platform-tools", "adb")
STATE_FILE = os.path.join(ROOT, "evidence", "lab-state.json")
LOG_FILE = os.path.join(ROOT, "evidence", "lab-log.jsonl")
CONFIG_FILE = os.path.join(ROOT, "scripts", "lab.config.json")

FLEET = [
    ("5554", "bucaramanga-a", 7.1193, -73.1227),
    ("5556", "hinatuan",      8.3667, 126.3333),
    ("5558", "chaparral",     3.7236, -75.4836),
    ("5560", "quibdo",        5.6947, -76.6611),
]

# BeAware alert radius vs magnitude, read straight off the 1279 real alerts in
# Allen et al. 2025 (Zenodo 15498729). The relation is near-deterministic, so a
# lookup with interpolation beats fitting a curve to it.
RADIUS_KM = {
    4.5: 31, 4.6: 37, 4.7: 45, 4.8: 53, 4.9: 64, 5.0: 78, 5.1: 94, 5.2: 113,
    5.3: 136, 5.4: 164, 5.5: 197, 5.6: 236, 5.7: 279, 5.8: 310, 5.9: 328,
    6.0: 346, 6.1: 367, 6.2: 385, 6.3: 405, 6.4: 424, 6.5: 443, 6.6: 462,
    6.7: 472, 6.8: 499, 7.7: 645, 7.8: 669,
}
MIN_ALERT_MAG = 4.5
# Google alerts from M4.5 using its OWN magnitude estimate, which disagrees with
# USGS by a few tenths either way. Pulling from 4.0 keeps the near misses on
# record, so a USGS M4.3 that Google called M4.6 is not invisible to us.
CATALOG_MIN_MAG = 4.0
NEAR_MISS_KM = 45
STALE_DEVICE_MIN = 45
CANARY_EVERY_H = 24
AEA_SILENT_H = 3          # the alerting subsystem re-registers for location every 30m
AEA_GRACE_MIN = 15        # Play Services needs a few minutes after boot to bring AEA up
CORROBORATE_AFTER_H = 24  # give the press a day to report whether alerts fired
QUAKE_WORDS = ("sismo", "terremoto", "temblor", "earthquake", "quake", "seismic")
ALERT_WORDS = ("alerta", "alert", "aviso", "notificacion", "notificación")
NEWS_LOCALES = {
    "co": ("es-419", "CO", "CO:es-419", '"alerta sismica" OR "alerta de sismo" Colombia celular'),
    "ph": ("en-PH", "PH", "PH:en", '"earthquake alert" Philippines phone Android Google'),
}
DEVICE_REGION = {"bucaramanga-a": "co", "chaparral": "co", "quibdo": "co",
                 "hinatuan": "ph"}


def beaware_radius_km(mag):
    """Interpolate Google's BeAware radius; below M4.5 no alert is issued."""
    if mag is None or mag < MIN_ALERT_MAG:
        return 0.0
    keys = sorted(RADIUS_KM)
    if mag >= keys[-1]:
        return RADIUS_KM[keys[-1]]
    lo = max(k for k in keys if k <= mag)
    hi = min(k for k in keys if k >= mag)
    if lo == hi:
        return RADIUS_KM[lo]
    span = (mag - lo) / (hi - lo)
    return RADIUS_KM[lo] + span * (RADIUS_KM[hi] - RADIUS_KM[lo])


def km_between(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * 6371.0 * math.asin(math.sqrt(a))


def now():
    return datetime.now(timezone.utc)


def load(path, default):
    try:
        with open(path) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return default


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as handle:
        json.dump(data, handle, indent=2)
    os.replace(tmp, path)


def log(record):
    record["at"] = now().isoformat()
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    with open(LOG_FILE, "a") as handle:
        handle.write(json.dumps(record) + "\n")


def notify(title, message, priority="default", tags=""):
    config = load(CONFIG_FILE, {})
    topic = config.get("ntfy_topic")
    log({"type": "NOTIFY", "title": title, "message": message, "priority": priority})
    print(f"[notify] {title}: {message}", flush=True)
    if not topic:
        return
    request = urllib.request.Request(
        f"https://ntfy.sh/{topic}",
        data=message.encode("utf-8"),
        headers={"Title": title, "Priority": priority, "Tags": tags},
    )
    try:
        urllib.request.urlopen(request, timeout=15).read()
    except Exception as error:  # a dead notifier must not stop the watch
        log({"type": "NOTIFY_FAILED", "error": str(error)})


def adb(serial, *args, timeout=60):
    try:
        done = subprocess.run([ADB, "-s", serial, *args], capture_output=True,
                              text=True, timeout=timeout)
        return done.stdout if done.returncode == 0 else None
    except (subprocess.TimeoutExpired, OSError):
        return None


def device_online(serial):
    return adb(serial, "shell", "getprop", "sys.boot_completed", timeout=20) is not None


def read_evidence(serial):
    out = adb(serial, "exec-out", "run-as", "com.earthquakes.relay",
              "cat", "files/notification-evidence.jsonl", timeout=120)
    if out is None:
        return None
    events = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except ValueError:
            continue
    return events


def aea_health(serial):
    """Is the Play Services earthquake subsystem alive and eating our fake location?

    It registers a 30-minute location request under the name earthquake_alerting
    and logs each delivery. A device that is up but whose AEA component went
    quiet would look healthy to every other check here, and would silently stop
    being able to receive an alert.
    """
    dump = adb(serial, "shell", "dumpsys", "activity", "service",
               "com.google.android.gms", timeout=90)
    if dump is None:
        return None
    registered = "earthquake_alerting" in dump
    deliveries = [line for line in dump.splitlines()
                  if "delivered locations" in line and "earthquake_alerting" in line]
    location = adb(serial, "shell", "dumpsys", "location", timeout=60) or ""
    match = re.search(r"gps ([0-9.-]+),([0-9.-]+)", location)
    return {
        "registered": registered,
        "deliveries": len(deliveries),
        "last_delivery": deliveries[-1].strip()[:23] if deliveries else None,
        "lat": float(match.group(1)) if match else None,
        "lon": float(match.group(2)) if match else None,
    }


PLAY_SERVICES_SIGNER = "5f2391277b1dbd489000467e4c2fa6af802430080457dce2f618992e9dfb5402"
CLOCK_SKEW_MAX_S = 30  # the gateway window is +2/-3 min around captured_at; stay far inside it


def classify(event):
    """ALERT, UPDATE, REVIEW or None for a GMS notification.

    Only a Play Services signature plus an eew_* channel counts as real. A
    quake-looking GMS notification on any other channel is REVIEW, never dropped:
    if Google renames the channel, a silent drop is a missed alert.
    """
    signer = event.get("package_signer_sha256")
    channel = str(event.get("channel_id") or "")
    if signer != PLAY_SERVICES_SIGNER:
        return "REVIEW" if is_quake_text(event) else None
    if channel.startswith("eew_alert"):
        return "ALERT"
    if channel.startswith("eew_"):
        return "UPDATE"
    return "REVIEW" if is_quake_text(event) else None


def is_quake_text(event):
    extras = event.get("selected_extras") or {}
    blob = " ".join(str(v) for v in extras.values()).lower()
    blob += " " + str(event.get("channel_id", "")).lower()
    return any(word in blob for word in QUAKE_WORDS)


def describe(event):
    extras = event.get("selected_extras") or {}
    title = extras.get("android.title", "(sin titulo)")
    text = extras.get("android.text") or extras.get("android.bigText") or ""
    return f"{title} | {text}"[:300]


def poll_devices(state):
    for port, name, lat, lon in FLEET:
        serial = f"emulator-{port}"
        device = state["devices"].setdefault(name, {"seen": 0, "last_seen": None, "alerted_down": False})
        # A device cannot miss an alert issued before it existed. Without this
        # the corroboration pass reports false negatives for events that predate
        # the emulator, and sends us hunting a bug that is not there.
        device.setdefault("online_since", now().isoformat())
        if not device_online(serial):
            last = device.get("last_seen")
            if last:
                down_min = (now() - datetime.fromisoformat(last)).total_seconds() / 60
                if down_min > STALE_DEVICE_MIN and not device["alerted_down"]:
                    device["alerted_down"] = True
                    notify("Device caido", f"{name} lleva {down_min:.0f} min sin responder",
                           priority="high", tags="warning")
            continue

        if device["alerted_down"]:
            notify("Device recuperado", f"{name} volvio", tags="white_check_mark")
        device["alerted_down"] = False
        device["last_seen"] = now().isoformat()

        # Emulator GPS is re-asserted each cycle; a cold restart loses the fix.
        adb(serial, "emu", "geo", "fix", str(lon), str(lat), timeout=20)

        # Play Services brings the alerting subsystem up minutes after boot, so a
        # freshly started emulator would otherwise trip the alarm every restart.
        uptime = adb(serial, "shell", "cat", "/proc/uptime", timeout=20)
        try:
            booted_min = float(uptime.split()[0]) / 60 if uptime else 999
        except (ValueError, IndexError):
            booted_min = 999

        health = aea_health(serial)
        if health and booted_min < AEA_GRACE_MIN and not health["registered"]:
            log({"type": "AEA_WARMING", "device": name, "uptime_min": round(booted_min, 1)})
        elif health:
            device["aea"] = health
            drifted = (health["lat"] is not None
                       and km_between(health["lat"], health["lon"], lat, lon) > 25)
            if not health["registered"] and not device.get("alerted_aea"):
                device["alerted_aea"] = True
                notify("AEA apagado", f"{name}: el subsistema earthquake_alerting de GMS "
                       "ya no esta registrado. Este device no puede recibir alertas.",
                       priority="high", tags="warning")
            elif drifted and not device.get("alerted_aea"):
                device["alerted_aea"] = True
                notify("Ubicacion perdida", f"{name}: GMS reporta {health['lat']:.3f},"
                       f"{health['lon']:.3f} en vez de {lat},{lon}.",
                       priority="high", tags="warning")
            elif health["registered"] and not drifted:
                device["alerted_aea"] = False

        guest_clock = adb(serial, "shell", "date", "+%s", timeout=20)
        try:
            skew_s = abs(int(guest_clock.strip()) - time.time()) if guest_clock else None
        except ValueError:
            skew_s = None
        if skew_s is not None and skew_s > CLOCK_SKEW_MAX_S and not device.get("alerted_clock"):
            device["alerted_clock"] = True
            notify("Reloj desfasado", f"{name}: {skew_s:.0f}s de diferencia con el host. "
                   "Las latencias medidas no sirven y el gateway rechazaria sus alertas.",
                   priority="high", tags="warning")
        elif skew_s is not None and skew_s <= CLOCK_SKEW_MAX_S:
            device["alerted_clock"] = False

        events = read_evidence(serial)
        if events is None:
            continue
        # A wiped or recreated evidence file restarts at zero; without this reset
        # every capture is skipped until the file outgrows the old count.
        if len(events) < device["seen"]:
            log({"type": "EVIDENCE_RESET", "device": name, "was": device["seen"], "now": len(events)})
            device["seen"] = 0
        for event in events[device["seen"]:]:
            if event.get("event_type") != "NOTIFICATION_POSTED":
                continue
            label = event.get("source_label")
            if label == "SYNTHETIC_FIXTURE":
                state["canary"]["last_ok"] = now().isoformat()
                # Per device: one healthy emulator must not hide four dead listeners.
                state["canary"].setdefault("last_ok_by_device", {})[name] = now().isoformat()
                continue
            if label != "GMS_CANDIDATE":
                continue
            record = {"type": "GMS_NOTIFICATION", "device": name, "event": event}
            log(record)
            kind = classify(event)
            if kind in ("ALERT", "UPDATE"):
                notify(f"ALERTA SISMICA ({kind}) capturada en {name}", describe(event),
                       priority="urgent", tags="rotating_light")
                state["hits"].append({"at": now().isoformat(), "device": name,
                                      "kind": kind, "text": describe(event)})
            elif kind == "REVIEW":
                notify(f"Revisar a mano: {name}", "GMS publico algo que parece sismo fuera de "
                       f"los canales eew_ conocidos o con firma distinta. {describe(event)}",
                       priority="urgent", tags="warning")
            else:
                log({"type": "GMS_OTHER", "device": name, "text": describe(event)})
        device["seen"] = len(events)


def run_canary(state):
    last = state["canary"].get("last_fired")
    if last and (now() - datetime.fromisoformat(last)) < timedelta(hours=CANARY_EVERY_H):
        return
    fired = []
    for port, name, _, _ in FLEET:
        serial = f"emulator-{port}"
        if not device_online(serial):
            continue
        out = adb(serial, "shell", "am", "broadcast", "-n",
                  "com.earthquakes.fixture/.FixtureReceiver",
                  "-a", "com.earthquakes.fixture.POST_NORMAL", timeout=30)
        if out is not None:
            fired.append(name)
    state["canary"]["last_fired"] = now().isoformat()
    log({"type": "CANARY_FIRED", "devices": fired})

    seen_by_device = state["canary"].get("last_ok_by_device", {})
    # A listener that never caught one counts from when the device came online.
    broken = [name for name in fired
              if (last_ok := seen_by_device.get(name)
                  or state["devices"].get(name, {}).get("online_since"))
              and (now() - datetime.fromisoformat(last_ok)) > timedelta(hours=CANARY_EVERY_H * 2)]
    if broken:
        notify("Cadena rota", f"El canario no aparece hace mas de 48h en: {', '.join(broken)}. "
               "Esos listeners no estan capturando; su silencio no significa nada.",
               priority="urgent", tags="rotating_light")


def poll_catalog(state):
    last = state["catalog"].get("last_poll")
    if last and (now() - datetime.fromisoformat(last)) < timedelta(minutes=30):
        return
    start = (now() - timedelta(days=3)).strftime("%Y-%m-%dT%H:%M:%S")
    query = urllib.parse.urlencode({
        "format": "geojson", "starttime": start, "minmagnitude": CATALOG_MIN_MAG,
        "minlatitude": -5, "maxlatitude": 16, "minlongitude": -84, "maxlongitude": -64,
    })
    try:
        with urllib.request.urlopen(
                f"https://earthquake.usgs.gov/fdsnws/event/1/query?{query}", timeout=30) as response:
            feed = json.load(response)
    except Exception as error:
        log({"type": "CATALOG_FAILED", "error": str(error)})
        return
    state["catalog"]["last_poll"] = now().isoformat()

    for feature in feed.get("features", []):
        quake_id = feature["id"]
        if quake_id in state["catalog"]["seen"]:
            continue
        state["catalog"]["seen"].append(quake_id)
        props, coords = feature["properties"], feature["geometry"]["coordinates"]
        mag, lon, lat = props.get("mag"), coords[0], coords[1]
        radius = beaware_radius_km(mag)
        quake_time = datetime.fromtimestamp(props["time"] / 1000, timezone.utc)
        reached = []
        for _, name, clat, clon in FLEET:
            if km_between(clat, clon, lat, lon) > radius:
                continue
            online_since = state["devices"].get(name, {}).get("online_since")
            if online_since and datetime.fromisoformat(online_since) > quake_time:
                log({"type": "PREDATES_DEVICE", "id": quake_id, "device": name})
                continue
            reached.append(name)
        entry = {"id": quake_id, "mag": mag, "place": props.get("place"),
                 "radius_km": round(radius), "expected_devices": reached,
                 "time": quake_time.isoformat()}
        log({"type": "CATALOG_EVENT", **entry})

        if not reached and mag is not None and mag < MIN_ALERT_MAG:
            close = [name for _, name, clat, clon in FLEET
                     if km_between(clat, clon, lat, lon) <= NEAR_MISS_KM]
            if close:
                log({"type": "NEAR_MISS", **entry, "near_devices": close,
                     "note": "bajo el umbral de USGS pero cerca; Google pudo estimarlo mas alto"})

        if reached:
            state["expected"].append(entry)
            notify("Alerta esperada",
                   f"M{mag} {props.get('place')} - radio {radius:.0f}km alcanza: {', '.join(reached)}. "
                   f"Revisar si el listener la capturo.",
                   priority="high", tags="warning")
    state["catalog"]["seen"] = state["catalog"]["seen"][-500:]


def usgs_detail(quake_id):
    """Full USGS record, including the products attached after the event."""
    url = ("https://earthquake.usgs.gov/fdsnws/event/1/query"
           f"?eventid={urllib.parse.quote(quake_id)}&format=geojson")
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "aea-lab"})
        return json.load(urllib.request.urlopen(request, timeout=30))
    except Exception as error:
        log({"type": "DETAIL_FAILED", "id": quake_id, "error": str(error)})
        return None


def felt_intensity(detail, lat, lon, max_km=30):
    """What people at this spot actually reported feeling.

    USGS "Did You Feel It?" aggregates public reports into 10 km cells. This is
    observed intensity from humans, not a model, so it is the closest thing to
    an independent answer to whether shaking there crossed the MMI 3 that
    Google needs to send a BeAware alert.
    """
    products = (detail or {}).get("properties", {}).get("products", {})
    dyfi = products.get("dyfi")
    if not dyfi:
        return None
    contents = dyfi[0].get("contents", {})
    entry = contents.get("dyfi_geo_10km.geojson") or contents.get("dyfi_geo_1km.geojson")
    if not entry:
        return None
    try:
        request = urllib.request.Request(entry["url"], headers={"User-Agent": "aea-lab"})
        grid = json.load(urllib.request.urlopen(request, timeout=45))
    except Exception as error:
        log({"type": "DYFI_FAILED", "error": str(error)})
        return None

    best = None
    for feature in grid.get("features", []):
        ring = feature["geometry"]["coordinates"][0]
        clat = sum(point[1] for point in ring) / len(ring)
        clon = sum(point[0] for point in ring) / len(ring)
        distance = km_between(lat, lon, clat, clon)
        if distance <= max_km and (best is None or distance < best[0]):
            props = feature["properties"]
            best = (distance, props.get("cdi"), props.get("nresp"),
                    (props.get("name") or "").split("<br>")[-1])
    if best is None or best[1] is None:
        return None
    return {"mmi": best[1], "responses": best[2], "cell": best[3], "km": round(best[0])}


def google_news_localized(query, hl, gl, ceid, when_days=3):
    return google_news(query, when_days=when_days, hl=hl, gl=gl, ceid=ceid)


def google_news(query, when_days=7, hl="es-419", gl="CO", ceid="CO:es-419"):
    """Colombian press coverage as an outside check on whether alerts fired.

    Google News exposes a plain RSS search with no key, which is enough. It only
    helps for events big enough to be written about, so it corroborates the
    strong ones and says nothing about the M4.5-5.5 bulk.
    """
    q = urllib.parse.quote(f"{query} when:{when_days}d")
    url = f"https://news.google.com/rss/search?q={q}&hl={hl}&gl={gl}&ceid={ceid}"
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        root = ET.fromstring(urllib.request.urlopen(request, timeout=25).read())
    except Exception as error:
        log({"type": "NEWS_FAILED", "error": str(error)})
        return []
    return [(item.findtext("title") or "", item.findtext("pubDate") or "")
            for item in root.iter("item")]


def corroborate(state):
    """Decide, for each alert we expected, what the outside world says happened.

    Two independent things have to be true before a miss means anything: the
    shaking there really crossed the alert threshold, and Google's radius
    covered the device. DYFI answers the first with reports from actual people,
    which beats any model we could run here.
    """
    for entry in state["expected"]:
        if entry.get("corroboration") is not None:
            continue
        if now() - datetime.fromisoformat(entry["time"]) < timedelta(hours=CORROBORATE_AFTER_H):
            continue

        detail = usgs_detail(entry["id"])
        props = (detail or {}).get("properties", {})
        verdicts = {}
        for _, name, lat, lon in FLEET:
            if name not in entry["expected_devices"]:
                continue
            felt = felt_intensity(detail, lat, lon)
            captured = any(hit["device"] == name and hit["at"] > entry["time"]
                           for hit in state["hits"])
            if felt is None:
                verdict = "sin reportes"
            elif felt["mmi"] >= 3.0 and not captured:
                verdict = "FALSO NEGATIVO"
            elif felt["mmi"] >= 3.0:
                verdict = "capturado"
            else:
                verdict = "bajo umbral"
            verdicts[name] = {"verdict": verdict, "felt": felt, "captured": captured}

        regions = {DEVICE_REGION.get(n, "co") for n in entry["expected_devices"]}
        headlines = []
        for region in regions:
            hl, gl, ceid, query = NEWS_LOCALES[region]
            headlines += [title for title, _ in google_news_localized(query, hl, gl, ceid)
                          if any(w in title.lower() for w in ALERT_WORDS)
                          and any(w in title.lower() for w in QUAKE_WORDS)]

        entry["corroboration"] = {
            "checked_at": now().isoformat(),
            "felt_reports": props.get("felt"),
            "cdi_max": props.get("cdi"),
            "devices": verdicts,
            "headlines": headlines[:6],
        }
        log({"type": "CORROBORATION", "event": entry["id"], "mag": entry["mag"],
             **entry["corroboration"]})

        missed = [n for n, v in verdicts.items() if v["verdict"] == "FALSO NEGATIVO"]
        if missed:
            worst = max(verdicts[n]["felt"]["mmi"] for n in missed)
            notify("FALSO NEGATIVO confirmado",
                   f"M{entry['mag']} {entry['place']}: la gente en {', '.join(missed)} "
                   f"reporto MMI {worst:.1f}, sobre el umbral de alerta, y la flota no "
                   "capturo nada. El emulador es el problema.",
                   priority="urgent", tags="rotating_light")
        elif any(v["verdict"] == "capturado" for v in verdicts.values()):
            notify("Positivo corroborado",
                   f"M{entry['mag']} {entry['place']}: capturado y confirmado por reportes de gente.",
                   tags="white_check_mark")


def report(state):
    print(f"--- estado {now().isoformat(timespec='seconds')} ---")
    for _, name, _, _ in FLEET:
        device = state["devices"].get(name, {})
        aea = device.get("aea") or {}
        estado = "activo" if aea.get("registered") else "APAGADO" if aea else "?"
        coords = f"{aea['lat']:.3f},{aea['lon']:.3f}" if aea.get("lat") is not None else "-"
        print(f"  {name:<16} eventos={device.get('seen', 0):<4} AEA={estado:<8} "
              f"pos={coords:<18} ultimo={device.get('last_seen', 'nunca')}")
    canary = state["canary"]
    print(f"  canario  disparado={canary.get('last_fired', 'nunca')} visto={canary.get('last_ok', 'nunca')}")
    print(f"  alertas esperadas: {len(state['expected'])}   capturas reales: {len(state['hits'])}")
    for hit in state["hits"][-5:]:
        print(f"    HIT {hit.get('kind', '?'):<6} {hit['at']} {hit['device']}: {hit['text']}")
    for item in state["expected"][-5:]:
        print(f"    ESPERADA {item['time']} M{item['mag']} {item['place']} -> {item['expected_devices']}")


def main():
    state = load(STATE_FILE, {"devices": {}, "canary": {}, "catalog": {"seen": []},
                              "expected": [], "hits": []})
    command = sys.argv[1] if len(sys.argv) > 1 else "once"
    if command == "report":
        report(state)
        return
    while True:
        poll_devices(state)
        run_canary(state)
        poll_catalog(state)
        corroborate(state)
        save(STATE_FILE, state)
        if command == "once":
            report(state)
            return
        time.sleep(300)


if __name__ == "__main__":
    main()
