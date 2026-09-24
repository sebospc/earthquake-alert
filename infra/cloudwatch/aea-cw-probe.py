#!/usr/bin/env python3
"""Feeds the three CloudWatch alarms and ships the listener evidence. Runs every minute.

Every run: GatewayUp and UncoveredReceptors from the local /status, sent first so nothing
later can hold them back. Then DeliveriesFlatSeconds, computed from the state file.
Every SLOW_EVERY_MIN minutes (and on the first run) the slow pass refreshes that state:
earthquake_alerting's delivery total per receptor, and the new bytes of each receptor's
on-device evidence, appended to LISTENER_LOG_DIR for the agent.

Metrics go out as EMF over UDP to the CloudWatch agent, with a Host dimension (one alarm set
per host). Every alarm treats missing data as breaching: a dead probe, agent or host pages.
A slow pass that fails leaves the state stale, so the flat clock keeps growing: loud too.

    AEA_CW_HOST=i-... AEA_CW_GPSKEEPER=quibdo aea-cw-probe.py /etc/earthquake-sensors.map
"""
import json, os, re, socket, subprocess, sys, time, urllib.request

STATUS_URL = "http://127.0.0.1:8787/status"
ADB = "/opt/android-sdk/platform-tools/adb"
EMF_ADDRESS = ("127.0.0.1", 25888)
NAMESPACE = "AeaLab"
STATE_FILE = "/var/lib/aea-cw/probe-state.json"
LISTENER_LOG_DIR = "/var/log/aea-cw"
LISTENER_EVIDENCE = "files/notification-evidence.jsonl"
# ponytail: dumpsys of GMS is not free on a 2 vCPU guest; 15 min is plenty for a 2 h rule.
SLOW_EVERY_MIN = 15
# Receptors with GpsKeeperService: only these must keep getting earthquake_alerting deliveries.
# Set per host by install.sh, no default: a wrong default silently watches the wrong receptor.
GPSKEEPER = set(filter(None, os.environ.get("AEA_CW_GPSKEEPER", "").split(",")))
HOST = os.environ.get("AEA_CW_HOST", "")
# A configured receptor with no reading at all: over any threshold, so it pages.
FLAT_UNKNOWN_S = 10 ** 7
# e.g. "...gms[earthquake_alerting]: total = 2h22m4s, min/max = 0s/30m, deliveries = 4"
DELIVERIES_TOTAL = re.compile(r"earthquake_alerting\]: total.*deliveries = (\d+)")


def receptors(sensor_map_path):
    """serial -> sensor id. The map also holds relay keys: they never leave this function."""
    with open(sensor_map_path) as sensor_map:
        return {fields[0]: fields[1] for fields in (line.split() for line in sensor_map) if len(fields) >= 2}


def uncovered_count(status, expected_ids):
    """No /status = every expected receptor is uncovered."""
    if status is None:
        return len(expected_ids)
    covered_ids = {sensor["id"] for sensor in status.get("sensors", []) if sensor.get("covered")}
    return len(set(expected_ids) - covered_ids)


def update_flat_seconds(state, sensor_id, total, now):
    """Seconds since this receptor's delivery total last changed. A failed read (total None)
    never resets the clock, so an offline receptor also ends up flat; neither does the first
    good read after failed ones. A reboot resets the counter, and that is a change too."""
    previous = state.get(sensor_id)
    if previous is None:
        state[sensor_id] = {"total": total, "changed_at": now}
    elif total is not None and previous["total"] is None:
        previous["total"] = total
    elif total is not None and total != previous["total"]:
        state[sensor_id] = {"total": total, "changed_at": now}
    return now - state[sensor_id]["changed_at"]


def deliveries_flat_seconds(deliveries_state, gpskeeper_ids, now):
    """Worst flat clock over the GpsKeeper receptors. One with no state (not in this host's
    map, or never read) counts as flat: a config slip must page, not go quiet."""
    return max((now - deliveries_state[sensor_id]["changed_at"]) if sensor_id in deliveries_state
               else FLAT_UNKNOWN_S for sensor_id in gpskeeper_ids)


def new_evidence_bytes(state, sensor_id, evidence):
    """The part of the on-device evidence not shipped yet. A shorter file means a reinstall
    or wipe: ship it whole."""
    offset = state.get(sensor_id, 0)
    if len(evidence) < offset:
        offset = 0
    state[sensor_id] = len(evidence)
    return evidence[offset:]


def emf(metrics, receptors_detail):
    return json.dumps({
        "_aws": {"Timestamp": int(time.time() * 1000), "LogGroupName": "/aea-lab/metrics",
                 "CloudWatchMetrics": [{"Namespace": NAMESPACE, "Dimensions": [["Host"]],
                                        "Metrics": [{"Name": name} for name in metrics]}]},
        "Host": HOST, **metrics, "receptors": receptors_detail})


def send(document):
    socket.socket(socket.AF_INET, socket.SOCK_DGRAM).sendto(document.encode(), EMF_ADDRESS)


def adb(serial, *args, timeout=60):
    try:
        done = subprocess.run([ADB, "-s", serial, *args], capture_output=True, timeout=timeout)
        return done.stdout if done.returncode == 0 else None
    except (subprocess.TimeoutExpired, OSError):
        return None


def read_status():
    try:
        with urllib.request.urlopen(STATUS_URL, timeout=10) as response:
            return json.load(response)
    except (OSError, ValueError):
        return None


def slow_pass(serial_to_id, state, now):
    detail = {}
    for serial, sensor_id in serial_to_id.items():
        dump = adb(serial, "shell", "dumpsys activity service com.google.android.gms | grep -m1 'earthquake_alerting\\]: total'")
        match = DELIVERIES_TOTAL.search(dump.decode(errors="replace")) if dump else None
        total = int(match.group(1)) if match else None
        flat = update_flat_seconds(state["deliveries"], sensor_id, total, now)
        detail[sensor_id] = {"deliveries_total": total, "deliveries_flat_s": round(flat)}

        # ponytail: whole file every pass (5 KB today); `tail -c +offset` if it grows to MBs.
        evidence = adb(serial, "exec-out", "run-as", "com.earthquakes.relay", "cat", LISTENER_EVIDENCE)
        if evidence is not None:
            fresh = new_evidence_bytes(state["evidence_offsets"], sensor_id, evidence)
            if fresh:
                with open(os.path.join(LISTENER_LOG_DIR, f"listener-{sensor_id}.jsonl"), "ab") as log:
                    log.write(fresh if fresh.endswith(b"\n") else fresh + b"\n")
    return detail


def load_state():
    try:
        with open(STATE_FILE) as state_file:
            state = json.load(state_file)
    except FileNotFoundError:
        state = {}
    except (OSError, ValueError) as error:
        # Starting over resets the flat clock once: say so where the journal ships it.
        print(f"probe state unreadable, starting over: {error}", file=sys.stderr)
        state = {}
    state.setdefault("deliveries", {})
    state.setdefault("evidence_offsets", {})
    return state


def save_state(state):
    with open(STATE_FILE + ".tmp", "w") as state_file:
        json.dump(state, state_file)
    os.replace(STATE_FILE + ".tmp", STATE_FILE)


def main(sensor_map_path, now=None):
    now = time.time() if now is None else now
    serial_to_id = receptors(sensor_map_path)
    status = read_status()
    send(emf({"GatewayUp": int(status is not None),
              "UncoveredReceptors": uncovered_count(status, serial_to_id.values())}, {}))

    state = load_state()
    detail = {}
    if int(now // 60) % SLOW_EVERY_MIN == 0 or not state["deliveries"]:
        try:
            detail = slow_pass(serial_to_id, state, now)
            save_state(state)
        except Exception as error:  # the fast metrics are out; a stale state now pages on its own
            print(f"slow pass failed: {error!r}", file=sys.stderr)
    if GPSKEEPER:
        send(emf({"DeliveriesFlatSeconds": round(deliveries_flat_seconds(state["deliveries"], GPSKEEPER, now))},
                 detail))
    return 0


if __name__ == "__main__":
    if not HOST or "AEA_CW_GPSKEEPER" not in os.environ:
        sys.exit("set AEA_CW_HOST and AEA_CW_GPSKEEPER (empty when the host has no GpsKeeper receptor)")
    sys.exit(main(sys.argv[1]))
