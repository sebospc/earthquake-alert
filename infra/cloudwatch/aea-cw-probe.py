#!/usr/bin/env python3
"""Feeds the CloudWatch alarms and ships the listener evidence. Runs every minute.

Every run: GatewayUp and UncoveredReceptors from the local /status, sent first so nothing
later can hold them back. Then LocationAgeMaxSeconds: the worst GMS location age over this
host's receptors, read from sensor-health's AEA_LOCATION_AGE lines in the journal (one
source of truth, the probe does not measure it again).
Every SLOW_EVERY_MIN minutes: the new bytes of each receptor's on-device evidence, appended
to LISTENER_LOG_DIR for the agent.

Metrics go out as EMF over UDP to the CloudWatch agent, with a Host dimension (one alarm set
per host). Every alarm treats missing data as breaching: a dead probe, agent or host pages.

    AEA_CW_HOST=i-... aea-cw-probe.py /etc/earthquake-sensors.map
"""
import json, os, re, socket, subprocess, sys, time, urllib.request

STATUS_URL = "http://127.0.0.1:8787/status"
ADB = "/opt/android-sdk/platform-tools/adb"
EMF_ADDRESS = ("127.0.0.1", 25888)
NAMESPACE = "AeaLab"
STATE_FILE = "/var/lib/aea-cw/probe-state.json"
LISTENER_LOG_DIR = "/var/log/aea-cw"
LISTENER_EVIDENCE = "files/notification-evidence.jsonl"
SLOW_EVERY_MIN = 15
HOST = os.environ.get("AEA_CW_HOST", "")
# A receptor with no reading at all: over any threshold, so it pages.
AGE_UNKNOWN_S = 10 ** 7
# sensor-health runs every 5 min; 20 min without a line means it stopped reporting.
LOCATION_AGE_WINDOW_S = 20 * 60
# journalctl -o short-unix, e.g.
# "1727220543.123456 ip-172-31-38-195 python3[48946]: AEA_LOCATION_AGE quibdo (emulator-5556): age_s=22989 source=uptime"
LOCATION_AGE_LINE = re.compile(r"^(\d+(?:\.\d+)?) \S+ \S+: AEA_LOCATION_AGE (\S+) \(\S+\): age_s=(\d+)")


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


def location_age_seconds(journal_lines, expected_ids, now):
    """Worst location age now, over this host's receptors: the last reported age plus the
    time since it was reported. A receptor with no line in the window counts as unknown,
    which pages: sensor-health stopped, or the receptor is not being checked."""
    latest = {}
    for line in journal_lines:
        match = LOCATION_AGE_LINE.match(line)
        if match:
            logged_at, sensor_id, age_s = float(match.group(1)), match.group(2), int(match.group(3))
            latest[sensor_id] = age_s + (now - logged_at)
    ages = {sensor_id: latest.get(sensor_id, AGE_UNKNOWN_S) for sensor_id in expected_ids}
    return (max(ages.values()) if ages else AGE_UNKNOWN_S), ages


def read_journal(now):
    try:
        done = subprocess.run(["journalctl", "-u", "sensor-health", "--since", f"@{int(now - LOCATION_AGE_WINDOW_S)}",
                               "-o", "short-unix", "--no-pager", "-q"],
                              capture_output=True, text=True, timeout=30)
        return done.stdout.splitlines() if done.returncode == 0 else []
    except (subprocess.TimeoutExpired, OSError):
        return []


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


def ship_listener_evidence(serial_to_id, state):
    for serial, sensor_id in serial_to_id.items():
        # ponytail: whole file every pass (5 KB today); `tail -c +offset` if it grows to MBs.
        evidence = adb(serial, "exec-out", "run-as", "com.earthquakes.relay", "cat", LISTENER_EVIDENCE)
        if evidence is not None:
            fresh = new_evidence_bytes(state["evidence_offsets"], sensor_id, evidence)
            if fresh:
                with open(os.path.join(LISTENER_LOG_DIR, f"listener-{sensor_id}.jsonl"), "ab") as log:
                    log.write(fresh if fresh.endswith(b"\n") else fresh + b"\n")


def load_state():
    try:
        with open(STATE_FILE) as state_file:
            state = json.load(state_file)
    except FileNotFoundError:
        state = {}
    except (OSError, ValueError) as error:
        # Starting over re-ships the evidence once: duplicates, never a gap.
        print(f"probe state unreadable, starting over: {error}", file=sys.stderr)
        state = {}
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

    worst_age, ages = location_age_seconds(read_journal(now), serial_to_id.values(), now)
    send(emf({"LocationAgeMaxSeconds": round(worst_age)}, {sensor_id: {"location_age_s": round(age)}
                                                           for sensor_id, age in ages.items()}))

    if int(now // 60) % SLOW_EVERY_MIN == 0:
        try:
            state = load_state()
            ship_listener_evidence(serial_to_id, state)
            save_state(state)
        except Exception as error:  # the metrics are out; the evidence waits for the next pass
            print(f"evidence pass failed: {error!r}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    if not HOST:
        sys.exit("set AEA_CW_HOST")
    sys.exit(main(sys.argv[1]))
