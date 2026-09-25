#!/usr/bin/env python3
"""Offline check of sensor-map.py: same key as aws-bootstrap.sh's openssl, serial order,
unknown ids refused.

    python3 infra/canary/test_sensor_map.py
"""
import importlib.util, os, subprocess

spec = importlib.util.spec_from_file_location(
    "sensor_map", os.path.join(os.path.dirname(os.path.abspath(__file__)), "sensor-map.py"))
sensor_map = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sensor_map)

sensors = {"general-santos": {"lat": 6.11, "lon": 125.17}, "la-serena": {"lat": -29.9, "lon": -71.25}}
lines = sensor_map.map_lines(b"master-secret", sensors, ["general-santos", "la-serena"])
bootstrap_key = subprocess.run(["openssl", "dgst", "-sha256", "-hmac", "master-secret", "-hex"], input=b"la-serena",
                               capture_output=True, check=True).stdout.decode().split()[-1]
assert lines[1] == f"emulator-5556 la-serena -29.9 -71.25 {bootstrap_key}", lines[1]
assert lines[0].startswith("emulator-5554 general-santos 6.11 125.17 ")
print("PASS same key as the bootstrap, serials in order")

try:
    sensor_map.map_lines(b"m", sensors, ["glan"])
    raise AssertionError("unknown id accepted")
except SystemExit as refusal:
    assert "glan" in str(refusal)
print("PASS an id missing from sensors.json is refused")
