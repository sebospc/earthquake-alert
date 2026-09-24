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

line = "10144/com.google.android.gms[earthquake_alerting]: total = 2h22m4s, min/max = 0s/30m, deliveries = 4"
assert probe.DELIVERIES_TOTAL.search(line).group(1) == "4"
state = {}
assert probe.update_flat_seconds(state, "quibdo", 4, 1000) == 0
assert probe.update_flat_seconds(state, "quibdo", 4, 8200) == 7200
assert probe.update_flat_seconds(state, "quibdo", None, 9000) == 8000, "failed read must not reset the clock"
assert probe.update_flat_seconds(state, "quibdo", 1, 9100) == 0, "reboot resets the counter: counts as a change"
state = {}
assert probe.update_flat_seconds(state, "quibdo", None, 1000) == 0
assert probe.update_flat_seconds(state, "quibdo", 3, 5000) == 4000, "first good read after failures is not a change"
assert probe.deliveries_flat_seconds(state, {"quibdo"}, 9000) == 8000
assert probe.deliveries_flat_seconds(state, {"quibdo", "elsewhere"}, 9000) == probe.FLAT_UNKNOWN_S, \
    "a GpsKeeper receptor with no state must page"
print("PASS deliveries flat clock")

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

# main(): no network, no adb, no agent. Metrics captured from what would go over UDP.
work = tempfile.mkdtemp()
probe.STATE_FILE = os.path.join(work, "state.json")
probe.LISTENER_LOG_DIR = work
probe.HOST = "i-test"
probe.GPSKEEPER = {"quibdo"}
sent = []
probe.send = lambda document: sent.append(json.loads(document))
deliveries = {"emulator-5554": 7, "emulator-5556": 4}


def fake_adb(serial, *args, timeout=60):
    if args[0] == "shell":
        return f"gms[earthquake_alerting]: total = 1h, min/max = 0s/30m, deliveries = {deliveries[serial]}".encode()
    return b'{"event":"x"}\n'


def run(now, status):
    sent.clear()
    probe.read_status = lambda: status
    probe.main(sensor_map.name, now=now)
    return {key: value for document in sent for key, value in document.items()
            if key in ("GatewayUp", "UncoveredReceptors", "DeliveriesFlatSeconds")}


probe.adb = fake_adb
up = {"sensors": [{"id": "chaparral", "covered": True}, {"id": "quibdo", "covered": True}]}
assert run(900, up) == {"GatewayUp": 1, "UncoveredReceptors": 0, "DeliveriesFlatSeconds": 0}
assert run(960, None) == {"GatewayUp": 0, "UncoveredReceptors": 2, "DeliveriesFlatSeconds": 60}, \
    "gateway down must send GatewayUp 0, not skip it"
assert open(os.path.join(work, "listener-quibdo.jsonl")).read() == '{"event":"x"}\n'

deliveries["emulator-5556"] = 5  # quibdo moves, chaparral (no GpsKeeper) stays flat 2 h
assert run(900 + 7200, up)["DeliveriesFlatSeconds"] == 0, "chaparral is flat but has no GpsKeeper: must not page"


def broken_adb(*args, **kwargs):
    raise RuntimeError("adb exploded")


probe.adb = broken_adb
metrics = run(900 + 7200 + 9000, up)  # a slow minute: the slow pass runs and fails
assert metrics["GatewayUp"] == 1 and metrics["DeliveriesFlatSeconds"] == 9000, \
    "a failing slow pass must not hold back the fast metrics, and the flat clock keeps growing"

probe.GPSKEEPER = {"not-on-this-host"}
assert run(900 + 7200 + 9060, up)["DeliveriesFlatSeconds"] == probe.FLAT_UNKNOWN_S
print("PASS main: fast metrics first, failures page, GpsKeeper filter")
os.unlink(sensor_map.name)
