#!/usr/bin/env python3
"""Offline checks of aea-cw-probe.py: no adb, no network, no agent.

    python3 infra/cloudwatch/test_cw_probe.py
"""
import importlib.util, json, os, tempfile

spec = importlib.util.spec_from_file_location(
    "probe", os.path.join(os.path.dirname(os.path.abspath(__file__)), "aea-cw-probe.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

with tempfile.NamedTemporaryFile("w", suffix=".map", delete=False) as sensor_map:
    sensor_map.write("emulator-5554 chaparral 3.7 -75.4 secretkey1\nemulator-5556 quibdo 5.6 -76.6 secretkey2\n\n")
serial_to_id = probe.receptors(sensor_map.name)
assert serial_to_id == {"emulator-5554": "chaparral", "emulator-5556": "quibdo"}
assert "secretkey" not in json.dumps(serial_to_id), "relay keys must never leave receptors()"
print("PASS sensor map parsing keeps only serial and id")

status = {"sensors": [{"id": "chaparral", "covered": True}, {"id": "quibdo", "covered": False},
                      {"id": "hinatuan", "covered": False}]}
assert probe.uncovered_count(status, serial_to_id.values()) == 1, "receptors not on this host do not count"
assert probe.uncovered_count(None, serial_to_id.values()) == 2, "no /status = all uncovered"
print("PASS uncovered count")

now = 1_000_000.0
journal = [
    f"{now - 600:.6f} ip-1 python3[1]: AEA_LOCATION_AGE quibdo (emulator-5556): age_s=100 source=uptime",
    f"{now - 300:.6f} ip-1 python3[1]: AEA_LOCATION_AGE quibdo (emulator-5556): age_s=50 source=eventlog",
    f"{now - 300:.6f} ip-1 python3[1]: AEA_LOCATION_AGE chaparral (emulator-5554): age_s=70000 source=eventlog",
    f"{now - 300:.6f} ip-1 python3[1]: AEA_NOT_OK chaparral (emulator-5554): reason=x",
]
worst, ages = probe.location_age_seconds(journal, ["chaparral", "quibdo"], now)
assert ages == {"chaparral": 70300, "quibdo": 350}, "latest line per receptor, plus the time since it was logged"
assert worst == 70300
worst, ages = probe.location_age_seconds(journal, ["chaparral", "quibdo", "elsewhere"], now)
assert worst == probe.AGE_UNKNOWN_S, "a receptor with no AEA_LOCATION_AGE line must page"
assert probe.location_age_seconds([], ["quibdo"], now)[0] == probe.AGE_UNKNOWN_S, "no journal = unknown, pages"
print("PASS location age from sensor-health's journal lines")

offsets = {}
assert probe.new_evidence_bytes(offsets, "quibdo", b"a\nb\n") == b"a\nb\n"
assert probe.new_evidence_bytes(offsets, "quibdo", b"a\nb\nc\n") == b"c\n"
assert probe.new_evidence_bytes(offsets, "quibdo", b"a\nb\nc\n") == b""
assert probe.new_evidence_bytes(offsets, "quibdo", b"x\n") == b"x\n", "shorter file = reinstall: ship whole"
print("PASS evidence offsets")

document = json.loads(probe.emf({"GatewayUp": 1, "UncoveredReceptors": 0}, {}))
directive = document["_aws"]["CloudWatchMetrics"][0]
assert [metric["Name"] for metric in directive["Metrics"]] == ["GatewayUp", "UncoveredReceptors"]
assert document["GatewayUp"] == 1 and directive["Dimensions"] == [["Host"]] and "Host" in document
print("PASS EMF document")

meminfo = "MemTotal: 16079000 kB\nMemAvailable: 1258291 kB\nSwapTotal: 4194300 kB\nSwapFree: 4091900 kB\n"
assert probe.memory_metrics(meminfo) == {"SwapUsedMB": 100, "MemAvailableMB": 1228}
assert probe.memory_metrics("MemAvailable: 2048 kB\n")["SwapUsedMB"] == 0, "no swap configured = 0 used"
print("PASS memory metrics from /proc/meminfo")

# main(): no network, no adb, no agent, no journal. Metrics captured from what would go over UDP.
work = tempfile.mkdtemp()
probe.STATE_FILE = os.path.join(work, "state.json")
probe.LISTENER_LOG_DIR = work
probe.HOST = "i-test"
sent = []
probe.send = lambda document: sent.append(json.loads(document))
probe.adb = lambda serial, *args, timeout=60: b'{"event":"x"}\n'
journal_now = []
probe.read_journal = lambda now: journal_now
probe.read_meminfo = lambda: "MemAvailable: 4096000 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n"


def run(now, status):
    sent.clear()
    probe.read_status = lambda: status
    probe.main(sensor_map.name, now=now)
    return {key: value for document in sent for key, value in document.items()
            if key in ("GatewayUp", "UncoveredReceptors", "LocationAgeMaxSeconds")}


up = {"sensors": [{"id": "chaparral", "covered": True}, {"id": "quibdo", "covered": True}]}
journal_now[:] = [f"{900 - 60}.0 h python3[1]: AEA_LOCATION_AGE chaparral (emulator-5554): age_s=10 source=eventlog",
                  f"{900 - 60}.0 h python3[1]: AEA_LOCATION_AGE quibdo (emulator-5556): age_s=20 source=uptime"]
assert run(900, up) == {"GatewayUp": 1, "UncoveredReceptors": 0, "LocationAgeMaxSeconds": 80}
assert open(os.path.join(work, "listener-quibdo.jsonl")).read() == '{"event":"x"}\n', "900 s is a slow minute"
assert run(960, None) == {"GatewayUp": 0, "UncoveredReceptors": 2, "LocationAgeMaxSeconds": 140}, \
    "gateway down must send GatewayUp 0, not skip it"

journal_now[:] = journal_now[:1]  # quibdo's line gone: sensor-health stopped checking it
assert run(1020, up)["LocationAgeMaxSeconds"] == probe.AGE_UNKNOWN_S


def broken_adb(*args, **kwargs):
    raise RuntimeError("adb exploded")


probe.adb = broken_adb
metrics = run(1800, up)  # a slow minute: the evidence pass runs and fails
assert metrics["GatewayUp"] == 1 and "LocationAgeMaxSeconds" in metrics, \
    "a failing evidence pass must not hold back any metric"
print("PASS main: every metric every minute, a missing reading pages, failures do not block")
os.unlink(sensor_map.name)
