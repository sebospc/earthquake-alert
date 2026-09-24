#!/usr/bin/env python3
"""Keeps each emulator's GPS on its assigned place while its guest is booting.

Play Services asks the GNSS HAL for a fix once, some 5-7 minutes after boot, and AEA keeps
that position. A `geo fix` sent later is accepted and changes nothing. So the fix has to be
there, repeated, during those first minutes of every boot: emulator start, crash restart,
guest reboot, spot interruption. Watching the guest's uptime covers all of them.

    aea-geofix.py <sensor-map>

Runs for ever as the emulator user (systemd, aws-bootstrap.sh). Reads the same map as
sensor-health.py: "<adb serial> <sensor_id> <lat> <lon> <sensor key>" per line.
"""
import sys
import time

import lab

BOOT_WINDOW_S = 12 * 60
FIX_EVERY_S = 3
IDLE_EVERY_S = 30


def guest_uptime_s(serial):
    """None while adbd is not up yet, which only happens early in a boot."""
    output = lab.adb(serial, "shell", "cat", "/proc/uptime", timeout=5)
    try:
        return float(output.split()[0])
    except (AttributeError, IndexError, ValueError):
        return None


def assignments(map_path):
    try:
        with open(map_path) as handle:
            rows = [line.split() for line in handle if line.strip()]
    except OSError:
        return []
    return [(row[0], row[2], row[3]) for row in rows if len(row) >= 4]


def main(map_path):
    while True:
        booting = False
        for serial, lat, lon in assignments(map_path):
            uptime = guest_uptime_s(serial)
            if uptime is None or uptime < BOOT_WINDOW_S:
                booting = True
                # The console answers even before the guest does, so this lands early.
                lab.adb(serial, "emu", "geo", "fix", lon, lat, timeout=5)
        time.sleep(FIX_EVERY_S if booting else IDLE_EVERY_S)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
