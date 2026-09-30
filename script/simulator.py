#!/usr/bin/env python3
"""Create and delete throwaway simulators for script/test.sh.

    script/simulator.py create PLATFORM NAME   print the new simulator's UDID
    script/simulator.py delete UDID            shut it down and delete it

PLATFORM is iOS, watchOS, or tvOS. `create` uses the newest installed runtime for that platform
and the first device type that runtime lists for the platform's family (Xcode lists the newest
model first), so it names no model and no device of anyone's. It exits 69 when no runtime for the
platform is installed: install one with Xcode > Settings > Components. A test run deletes every
simulator it created, so it never reuses or disturbs one it did not make. Python 3 standard
library only.
"""
import json
import subprocess
import sys

FAMILIES = {"iOS": "iPhone", "watchOS": "Apple Watch", "tvOS": "Apple TV"}


def simctl(*arguments):
    return subprocess.run(["xcrun", "simctl", *arguments], capture_output=True, text=True)


def version_key(runtime):
    return tuple(int(part) for part in runtime.get("version", "0").split(".") if part.isdigit())


def create(platform, name):
    family = FAMILIES.get(platform)
    if family is None:
        sys.exit(f"error: unknown platform {platform!r}; expected one of {', '.join(FAMILIES)}")
    listed = simctl("list", "runtimes", "--json", "available")
    if listed.returncode != 0:
        sys.exit(f"error: simctl could not list runtimes: {listed.stderr.strip()}")
    runtimes = [runtime for runtime in json.loads(listed.stdout)["runtimes"]
                if runtime.get("platform") == platform and runtime.get("isAvailable")]
    if not runtimes:
        print(f"error: no {platform} simulator runtime is installed; add one in Xcode > Settings > Components",
              file=sys.stderr)
        sys.exit(69)
    runtime = max(runtimes, key=version_key)
    device_types = [kind for kind in runtime.get("supportedDeviceTypes", []) if kind.get("productFamily") == family]
    if not device_types:
        sys.exit(f"error: the {platform} {runtime['version']} runtime lists no {family} device type")
    device_type = device_types[0]
    made = simctl("create", name, device_type["identifier"], runtime["identifier"])
    if made.returncode != 0:
        sys.exit(f"error: simctl could not create {name!r}: {made.stderr.strip()}")
    print(f"created {name!r}: {device_type['name']}, {platform} {runtime['version']} ({runtime.get('buildversion', '?')})",
          file=sys.stderr)
    print(made.stdout.strip())


def delete(udid):
    simctl("shutdown", udid)  # Fails harmlessly when it is not booted.
    removed = simctl("delete", udid)
    if removed.returncode != 0:
        sys.exit(f"error: simctl could not delete {udid}: {removed.stderr.strip()}")


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "create":
        create(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3 and sys.argv[1] == "delete":
        delete(sys.argv[2])
    else:
        sys.exit(__doc__.split("\n\n")[1])


if __name__ == "__main__":
    main()
