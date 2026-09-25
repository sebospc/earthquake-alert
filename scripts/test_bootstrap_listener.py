#!/usr/bin/env python3
"""Checks aws-bootstrap.sh's listener step without root, adb or emulators: which emulator
each sensor goes to, and that the sensor map keeps the sensors it was not asked about.

Run: python3 scripts/test_bootstrap_listener.py
"""
import json, os, subprocess, tempfile

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
BOOTSTRAP = os.path.join(SCRIPTS, "aws-bootstrap.sh")
MAP = "emulator-5554 chaparral 3.7236 -75.4836 chaparral-key\nemulator-5556 quibdo 5.6947 -76.6611 quibdo-key\n"


def bash(snippet, map_text=MAP):
    """Sources the bootstrap (functions only) and runs snippet with $MAP set."""
    with tempfile.TemporaryDirectory() as directory:
        map_path = os.path.join(directory, "sensors.map")
        if map_text is not None:
            with open(map_path, "w") as handle:
                handle.write(map_text)
        done = subprocess.run(["bash", "-c", f'source "{BOOTSTRAP}"; MAP="{map_path}"; {snippet}'],
                              capture_output=True, text=True, cwd=directory)
        return done.returncode, done.stdout, done.stderr


def resolve(*targets, map_text=MAP):
    return bash('resolve_listener_targets "$MAP" ' + " ".join(targets), map_text)


# --- which emulator each sensor goes to --------------------------------------------------

assert resolve("quibdo") == (0, "emulator-5556 quibdo\n", ""), "quibdo went by position"
assert resolve("quibdo", "chaparral")[1] == "emulator-5556 quibdo\nemulator-5554 chaparral\n"
code, _, error = resolve("bogota")
assert code != 0 and "emulator-NNNN=bogota" in error, "an unmapped sensor was guessed"
assert resolve("emulator-5558=bogota") == (0, "emulator-5558 bogota\n", "")
assert resolve("emulator-5556=quibdo")[0] == 0, "restating the map must pass"
code, _, error = resolve("emulator-5554=quibdo")
assert code != 0 and "emulator-5554 is chaparral" in error, "a mapped emulator was taken over"
code, _, error = resolve("emulator-5558=quibdo")
assert code != 0 and "quibdo is on emulator-5556" in error, "one sensor on two emulators"
assert resolve("5554=chaparral")[0] != 0 and resolve("emulator-5554=")[0] != 0
# First install on a host: no map yet, so every pairing is explicit.
assert resolve("quibdo", map_text=None)[0] != 0
assert resolve("emulator-5554=chaparral", map_text=None) == (0, "emulator-5554 chaparral\n", "")
print("PASS the emulator comes from the map, never from the argument position")


# --- the map keeps what it was not asked about -------------------------------------------

def merge(new_lines, map_text=MAP):
    code, out, error = bash(f"merge_sensor_map \"$MAP\" $'{new_lines}'", map_text)
    assert code == 0, error
    return out


merged = merge("emulator-5556 quibdo 5.6947 -76.6611 new-key\\n")
assert merged == "emulator-5554 chaparral 3.7236 -75.4836 chaparral-key\nemulator-5556 quibdo 5.6947 -76.6611 new-key\n", merged
merged = merge("emulator-5558 bogota 4.61 -74.08 bogota-key\\n")
assert merged.count("\n") == 3 and "chaparral-key" in merged and "quibdo-key" in merged
assert merge("emulator-5554 chaparral 3.7236 -75.4836 k\\n", map_text=None) == "emulator-5554 chaparral 3.7236 -75.4836 k\n"
print("PASS the map is merged, not rewritten")


# --- the whole step, for one sensor: devops' trap --------------------------------------

with tempfile.TemporaryDirectory() as directory:
    os.makedirs(os.path.join(directory, "gateway", "public"))
    with open(os.path.join(directory, "gateway", "public", "sensors.json"), "w") as handle:
        json.dump({"sensors": [{"id": "chaparral", "lat": 3.7236, "lon": -75.4836},
                               {"id": "quibdo", "lat": 5.6947, "lon": -76.6611}]}, handle)
    for name, text in (("gateway.env", "RELAY_HMAC_SECRET=master\n"), ("listener.apk", "apk"),
                       ("sensors.map", MAP)):
        with open(os.path.join(directory, name), "w") as handle:
            handle.write(text)
    stubs = f'''
      GATEWAY_DIR="{directory}/gateway"; GATEWAY_ENV="{directory}/gateway.env"
      SENSOR_MAP="{directory}/sensors.map"
      aea_adb() {{
        echo "$*" >> "{directory}/adb.log"
        case "$*" in
          *boot_completed*) echo 1 ;;
          *"dumpsys package"*) echo "android.permission.ACCESS_FINE_LOCATION: granted=true" ;;
          *exec-in*) cat > /dev/null ;;
        esac
      }}
      aea_adb_with_input() {{ aea_adb "$@"; }}
      restart_foreign_adb_server() {{ :; }}
      systemctl() {{ :; }}
      mktemp() {{ command mktemp "{directory}/tmp.XXXXXX"; }}
      install() {{ cp "${{@: -2:1}}" "${{@: -1}}"; }}
    '''
    done = subprocess.run(["bash", "-c", f'source "{BOOTSTRAP}"\n{stubs}\ninstall_listener "{directory}/listener.apk" quibdo'],
                          capture_output=True, text=True, cwd=directory)
    assert done.returncode == 0, done.stderr
    serials = {line.split()[1] for line in open(os.path.join(directory, "adb.log"))}
    assert serials == {"emulator-5556"}, f"touched {serials}"
    with open(os.path.join(directory, "sensors.map")) as handle:
        lines = handle.read().splitlines()
    assert lines[0] == "emulator-5554 chaparral 3.7236 -75.4836 chaparral-key", "chaparral dropped"
    serial, sensor_id, lat, lon, key = lines[1].split()
    assert (serial, sensor_id, lat, lon) == ("emulator-5556", "quibdo", "5.6947", "-76.6611")
    assert len(key) == 64 and key != "quibdo-key", "the per-sensor key was not derived"
print("PASS installing one sensor touches only its emulator and keeps the other in the map")


# --- three pairs, three installs: adb must not eat the loop's input ------------------------

FAKE_ADB = """#!/bin/bash
echo "$*" >> "$ADB_LOG"
case "$*" in
  *boot_completed*) cat > /dev/null; echo 1 ;;
  *"dumpsys package"*) cat > /dev/null; echo "android.permission.ACCESS_FINE_LOCATION: granted=true" ;;
  *exec-in*) cat > "$ADB_LOG.relay.$2" ;;
  *) cat > /dev/null ;;
esac
"""


def install_three(extra_stubs=""):
    """Runs the real aea_adb against a fake adb that, like `adb shell`, reads all of stdin."""
    with tempfile.TemporaryDirectory() as directory:
        os.makedirs(os.path.join(directory, "gateway", "public"))
        os.makedirs(os.path.join(directory, "sdk", "platform-tools"))
        adb = os.path.join(directory, "sdk", "platform-tools", "adb")
        with open(adb, "w") as handle:
            handle.write(FAKE_ADB)
        os.chmod(adb, 0o755)
        with open(os.path.join(directory, "gateway", "public", "sensors.json"), "w") as handle:
            json.dump({"sensors": [{"id": "chaparral", "lat": 3.7236, "lon": -75.4836},
                                   {"id": "quibdo", "lat": 5.6947, "lon": -76.6611},
                                   {"id": "general-santos", "lat": 6.11, "lon": 125.17}]}, handle)
        for name, text in (("gateway.env", "RELAY_HMAC_SECRET=master\n"), ("listener.apk", "apk"),
                           ("sensors.map", MAP)):
            with open(os.path.join(directory, name), "w") as handle:
                handle.write(text)
        stubs = f'''
          GATEWAY_DIR="{directory}/gateway"; GATEWAY_ENV="{directory}/gateway.env"
          SENSOR_MAP="{directory}/sensors.map"; SDK_ROOT="{directory}/sdk"; EMULATOR_USER=aea
          export ADB_LOG="{directory}/adb.log"
          sudo() {{ shift 3; "$@"; }}
          restart_foreign_adb_server() {{ :; }}
          systemctl() {{ :; }}
          mktemp() {{ command mktemp "{directory}/tmp.XXXXXX"; }}
          install() {{ cp "${{@: -2:1}}" "${{@: -1}}"; }}
          {extra_stubs}
        '''
        done = subprocess.run(["bash", "-c", f'source "{BOOTSTRAP}"\n{stubs}\ninstall_listener "{directory}/listener.apk" '
                               "emulator-5554=chaparral emulator-5556=quibdo emulator-5558=general-santos"],
                              capture_output=True, text=True, cwd=directory)
        log = open(os.path.join(directory, "adb.log")).read().splitlines()
        relays = {name.rsplit(".", 1)[1] for name in os.listdir(directory) if name.startswith("adb.log.relay.")}
        return done, log, relays, open(os.path.join(directory, "sensors.map")).read()


done, log, relays, sensor_map = install_three()
assert done.returncode == 0, done.stderr
installs = [line.split()[1] for line in log if " install -r -g " in line]
assert installs == ["emulator-5554", "emulator-5556", "emulator-5558"], f"installed on {installs}"
assert relays == {"emulator-5554", "emulator-5556", "emulator-5558"}, "relay.json did not reach every emulator"
assert "emulator-5558 general-santos" in sensor_map
print("PASS three pairs give three installs, although adb reads stdin")

# Any future step in the loop that swallows the loop's input must fail loudly, not exit 0.
done, log, relays, sensor_map = install_three('''
  real_aea_adb() { sudo -u "$EMULATOR_USER" -H "$SDK_ROOT/platform-tools/adb" "$@" </dev/null; }
  aea_adb() { cat <&3 > /dev/null; real_aea_adb "$@"; }''')
assert done.returncode != 0, "a short install exited 0"
assert "installed 1 of 3 listeners" in done.stderr, done.stderr
assert sensor_map == MAP, "the sensor map changed after a short install"
print("PASS fewer installs than targets dies and leaves the sensor map alone")
