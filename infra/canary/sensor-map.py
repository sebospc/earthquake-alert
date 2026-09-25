#!/usr/bin/env python3
"""Prints /etc/earthquake-sensors.map lines for a canary host. Runs on the MAIN host, as root,
fed over ssh stdin by write-map.sh: the master secret never leaves that host.

    sensor-map.py <sensor_id for emulator-5554> [<sensor_id for emulator-5556>]
"""
import hashlib, hmac, json, os, sys

GATEWAY_ENV = os.environ.get("GATEWAY_ENV", "/etc/earthquake-gateway.env")
SENSORS_JSON = os.environ.get("SENSORS_JSON", "/opt/earthquake-gateway/public/sensors.json")


def map_lines(master, sensors, sensor_ids):
    """Serials follow the bootstrap: sensor-i listens on 5552 + 2i. The key is the one
    aws-bootstrap.sh derives: HMAC-SHA256(master, sensor_id), hex."""
    missing = [sensor_id for sensor_id in sensor_ids if sensor_id not in sensors]
    if missing:
        raise SystemExit(f"not in the main gateway's sensors.json: {missing}")
    return [f"emulator-{5552 + 2 * index} {sensor_id} {sensors[sensor_id]['lat']} {sensors[sensor_id]['lon']} "
            f"{hmac.new(master, sensor_id.encode(), hashlib.sha256).hexdigest()}"
            for index, sensor_id in enumerate(sensor_ids, start=1)]


if __name__ == "__main__":
    with open(GATEWAY_ENV) as env_file:
        env = dict(line.strip().split("=", 1) for line in env_file if "=" in line)
    with open(SENSORS_JSON) as sensors_file:
        sensors = {sensor["id"]: sensor for sensor in json.load(sensors_file)["sensors"]}
    print("\n".join(map_lines(env["RELAY_HMAC_SECRET"].encode(), sensors, sys.argv[1:])))
