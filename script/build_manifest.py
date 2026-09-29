#!/usr/bin/env python3
"""Build the selected build profiles and write a manifest of what was actually built.

Usage: script/build_manifest.py [--profile NAME]... [--lane Source|Store]

Profiles are the files in Config/Profiles/. A scheme belongs to the profile its application
targets attach (their LAB_BUILD_PROFILE). Every scheme of each selected profile is built from a
fresh derived-data folder in Release, for the Mac or for the generic simulator, and each product
is inspected: Info.plist provenance, linked frameworks (otool -L), declared and signed
entitlement keys, embedded bundles, and purpose strings. Config/ProductPolicy.txt says what a
profile may link and carry. A profile is listed as built only when every one of its schemes
built and every product passed; otherwise it is failed or skipped, with the reason.

Writes build/manifest/manifest.json and one build log per scheme under build/manifest/logs/.
Exits 1 if any selected profile failed. Simulator products are not device installers.
Entitlement values, team identifiers, and a local bundle prefix are never recorded.
"""
import argparse
import datetime
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = "AppleNativeLab.xcodeproj"
OUT = Path("build/manifest")
DERIVED = OUT / "DerivedData"
CONFIGURATION = "Release"
PROFILE_ORDER = ["CoreLocal", "SystemSurfaces", "Companions", "CloudOptional", "FrontierOptional"]
LANES = ["Source", "Store"]
DEFAULT_BUNDLE_PREFIX = "org.example"

# PLATFORM_NAME of a target -> (policy platform, destination, products-folder suffix, installer note)
PLATFORMS = {
    "macosx": ("macos", "platform=macOS", "", "Mac app for local use, not notarized or exported"),
    "iphoneos": ("ios", "generic/platform=iOS Simulator", "-iphonesimulator",
                 "simulator build, not a device installer"),
    "watchos": ("watchos", "generic/platform=watchOS Simulator", "-watchsimulator",
                "simulator build, not a device installer"),
    "appletvos": ("tvos", "generic/platform=tvOS Simulator", "-appletvsimulator",
                  "simulator build, not a device installer"),
    "xros": ("visionos", "generic/platform=visionOS Simulator", "-xrsimulator",
             "simulator build, not a device installer"),
}

BUNDLE_SUFFIXES = (".app", ".appex", ".framework")

# Keys Xcode adds when it signs a local build, beyond what a target declares.
XCODE_INJECTED_ENTITLEMENTS = {
    "com.apple.security.get-task-allow",
    "application-identifier",
    "com.apple.developer.team-identifier",
}


def run(cmd, **kwargs):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kwargs)


def relative(text):
    """Strip this checkout's absolute path from tool output, so the manifest names no local folder."""
    for root in (str(ROOT), str(ROOT).removeprefix("/private")):
        text = text.replace(root + "/", "").replace(root, ".")
    return text


def first_line(cmd):
    result = run(cmd)
    return result.stdout.strip().splitlines()[0] if result.returncode == 0 and result.stdout.strip() else "unknown"


# MARK: - Configuration

def read_xcconfig(path):
    values = {}
    for line in path.read_text().splitlines():
        line = line.split("//", 1)[0].strip()
        match = re.match(r"^([A-Z0-9_]+)\s*=\s*(.*)$", line)
        if match:
            values[match.group(1)] = match.group(2).strip()
    return values


def load_profiles():
    profiles = {}
    for path in sorted((ROOT / "Config/Profiles").glob("*.xcconfig")):
        values = read_xcconfig(path)
        name = values.get("LAB_BUILD_PROFILE")
        if name != path.stem:
            sys.exit(f"error: {path.relative_to(ROOT)} sets LAB_BUILD_PROFILE = {name!r}; it must match the file name")
        profiles[name] = {
            "config": str(path.relative_to(ROOT)),
            "externalSetup": values.get("LAB_PROFILE_EXTERNAL_SETUP", ""),
        }
    ordered = [name for name in PROFILE_ORDER if name in profiles]
    ordered += sorted(set(profiles) - set(ordered))
    return {name: profiles[name] for name in ordered}


def load_policy():
    policy = {"link": set(), "entitlement": set(), "unsupported": set(), "purpose": {}}
    path = ROOT / "Config/ProductPolicy.txt"
    for number, raw in enumerate(path.read_text().splitlines(), 1):
        fields = raw.split("#", 1)[0].split()
        if not fields:
            continue
        kind, args = fields[0], fields[1:]
        if kind in ("link", "entitlement") and len(args) == 3:
            policy[kind].add(tuple(args))
        elif kind == "unsupported" and len(args) == 2:
            policy[kind].add(tuple(args))
        elif kind == "purpose" and len(args) == 2:
            policy["purpose"].setdefault(args[0], []).append(args[1])
        else:
            sys.exit(f"error: Config/ProductPolicy.txt:{number}: cannot read {raw.strip()!r}")
    return policy


def allowed(rules, profile, platform, item):
    return any(p in (profile, "*") and q in (platform, "*") and i == item for p, q, i in rules)


# MARK: - Project

def list_schemes():
    result = run(["xcodebuild", "-list", "-json", "-project", PROJECT])
    if result.returncode != 0:
        sys.exit(f"error: xcodebuild -list failed:\n{result.stderr}")
    return json.loads(result.stdout)["project"]["schemes"]


def scheme_targets(scheme):
    """Build settings for every target the scheme builds, as Release."""
    result = run(["xcodebuild", "-showBuildSettings", "-json", "-project", PROJECT,
                  "-scheme", scheme, "-configuration", CONFIGURATION])
    if result.returncode != 0:
        return None, result.stderr.strip().splitlines()[-1:] or ["xcodebuild -showBuildSettings failed"]
    return [entry for entry in json.loads(result.stdout)], []


def is_app(settings):
    return settings.get("PRODUCT_TYPE", "").startswith("com.apple.product-type.application")


def is_executable(settings):
    """Apps and app extensions: the bundles that carry their own entitlements and links."""
    return is_app(settings) or "extension" in settings.get("PRODUCT_TYPE", "")


# MARK: - Product inspection

def linked_libraries(executable):
    result = run(["otool", "-L", str(executable)])
    frameworks, weak, other = set(), set(), set()
    for line in result.stdout.splitlines():
        match = re.match(r"^\s+(\S+) \(compatibility version [^)]*\)$", line)
        if not match:
            continue
        name = match.group(1)
        framework = re.match(r"^/System/Library/(Private)?Frameworks/([^/]+)\.framework/", name)
        if framework:
            label = ("Private:" if framework.group(1) else "") + framework.group(2)
            frameworks.add(label)
            if ", weak" in line:
                weak.add(label)
        else:
            other.add(name if not name.startswith("/") else Path(name).name)
    return sorted(frameworks), sorted(weak), sorted(other)


def readable_xcode(raw):
    """Xcode records its version as digits, such as 2700 for 27.0 or 2631 for 26.3.1."""
    if len(raw) != 4 or not raw.isdigit():
        return raw
    return f"{int(raw[:2])}.{raw[2]}" + (f".{raw[3]}" if raw[3] != "0" else "")


def architectures(executable):
    result = run(["lipo", "-archs", str(executable)])
    return result.stdout.split() if result.returncode == 0 else []


def simulator_entitlements(executable, arch):
    """A simulator build carries its entitlements in the __TEXT,__entitlements section."""
    result = run(["otool", "-arch", arch, "-X", "-s", "__TEXT", "__entitlements", str(executable)])
    data = bytearray()
    for line in result.stdout.splitlines():
        for word in line.split()[1:]:
            chunk = bytes.fromhex(word)
            data += chunk[::-1] if len(word) == 8 else chunk
    if not data:
        return {}
    return plistlib.loads(bytes(data).rstrip(b"\0"))


def signature(app):
    """How the bundle is signed, without recording any team or certificate name."""
    details = run(["codesign", "-dv", str(app)]).stderr
    if "Signature=adhoc" in details:
        kind = "ad hoc (Sign to Run Locally)"
    elif "TeamIdentifier=" in details and "TeamIdentifier=not set" not in details:
        kind = "signed with a team (identifier not recorded)"
    else:
        kind = "unsigned or unreadable"
    flags = re.search(r"flags=0x[0-9a-f]+\(([^)]*)\)", details)
    return {"kind": kind, "hardenedRuntime": bool(flags and "runtime" in flags.group(1).split(","))}


def signed_entitlements(app, executable, simulator):
    if simulator:
        archs = architectures(executable)
        return simulator_entitlements(executable, archs[0]) if archs else None
    result = run(["codesign", "-d", "--entitlements", "-", "--xml", str(app)])
    if result.returncode != 0:
        return None
    start = result.stdout.find("<?xml")
    return plistlib.loads(result.stdout[start:].encode()) if start >= 0 else {}


def declared_entitlements(settings):
    path = settings.get("CODE_SIGN_ENTITLEMENTS", "")
    if not path:
        return []
    with open(ROOT / path, "rb") as handle:
        return sorted(plistlib.load(handle))


def inspect_bundle(label, bundle, mac, simulator, profile, platform, lane, policy, declared=None):
    """Check one app or extension bundle against the policy for its profile and platform.

    `declared` is the target's own entitlements file, when the bundle is a scheme target. An
    embedded bundle has no known file, so its signed entitlements are checked against the
    profile's allowed entitlements instead."""
    info_path = bundle / "Contents/Info.plist" if mac else bundle / "Info.plist"
    if not info_path.exists():
        return {"path": label}, [f"{label}: no Info.plist"]
    with open(info_path, "rb") as handle:
        info = plistlib.load(handle)
    executable = (bundle / "Contents/MacOS" if mac else bundle) / info.get("CFBundleExecutable", "")
    if not executable.is_file():
        return {"path": label}, [f"{label}: no executable"]

    frameworks, weak, libraries = linked_libraries(executable)
    signed = signed_entitlements(bundle, executable, simulator)
    purpose_keys = sorted(k for k in info if re.match(r"^NS[A-Za-z]+UsageDescription$", k) and str(info[k]).strip())
    required = sorted({key for f in frameworks for key in policy["purpose"].get(f, [])})
    missing = [key for key in required if key not in purpose_keys]
    record = {
        "buildProfile": info.get("LabBuildProfile", "undeclared"),
        "sdk": info.get("DTSDKName", "unknown"),
        "sdkBuild": info.get("DTSDKBuild", "unknown"),
        "platformVersion": info.get("DTPlatformVersion", "unknown"),
        "xcode": readable_xcode(info.get("DTXcode", "unknown")),
        "xcodeBuild": info.get("DTXcodeBuild", "unknown"),
        "minimumOS": info.get("MinimumOSVersion") or info.get("LSMinimumSystemVersion", "unknown"),
        "architectures": architectures(executable),
        "executableSHA256": hashlib.sha256(executable.read_bytes()).hexdigest(),
        "linkedFrameworks": frameworks,
        "weakFrameworks": weak,
        "linkedLibraries": libraries,
        "declaredEntitlements": declared if declared is not None else "not known for an embedded bundle",
        "signature": signature(bundle),
        "signedEntitlements": sorted(signed) if signed is not None else "not readable",
        "purposeStrings": purpose_keys,
        "purposeStringsMissingForStore": missing,
    }

    problems = []
    if record["buildProfile"] != profile:
        problems.append(f"{label}: Info.plist says profile {record['buildProfile']}, expected {profile}")
    for framework in frameworks:
        if framework.startswith("Private:"):
            problems.append(f"{label}: links private framework {framework[8:]}")
        elif (platform, framework) in policy["unsupported"]:
            problems.append(f"{label}: links {framework}, which is unsupported on {platform}")
        elif not allowed(policy["link"], profile, platform, framework):
            problems.append(f"{label}: links {framework}, which Config/ProductPolicy.txt does not allow for {profile} on {platform}")
    for key in declared or []:
        if not allowed(policy["entitlement"], profile, platform, key):
            problems.append(f"{label}: declares entitlement {key}, which Config/ProductPolicy.txt does not allow for {profile} on {platform}")
    if signed is None:
        problems.append(f"{label}: signed entitlements are not readable")
    else:
        extra = sorted(set(signed) - XCODE_INJECTED_ENTITLEMENTS - set(declared or []))
        if declared is not None and extra:
            problems.append(f"{label}: signed with undeclared entitlements {', '.join(extra)}")
        for key in extra if declared is None else []:
            if not allowed(policy["entitlement"], profile, platform, key):
                problems.append(f"{label}: signed with entitlement {key}, which Config/ProductPolicy.txt does not allow for {profile} on {platform}")
    if lane == "Store" and missing:
        problems.append(f"{label}: Store lane is missing purpose strings {', '.join(missing)}")

    # Every app or extension nested inside must belong to the same profile and pass the same checks.
    record["embeddedBundles"] = []
    for nested in sorted(bundle.rglob("*")):
        relative_path = nested.relative_to(bundle)
        if any(Path(part).suffix in BUNDLE_SUFFIXES for part in relative_path.parts[:-1]):
            continue  # inside a nested bundle, which inspects its own contents
        if nested.suffix == ".framework":
            record["embeddedBundles"].append({"path": str(relative_path)})
        elif nested.suffix in (".appex", ".app"):
            nested_record, nested_problems = inspect_bundle(
                f"{label}/{relative_path}", nested, mac, simulator, profile, platform, lane, policy)
            record["embeddedBundles"].append({"path": str(relative_path), **nested_record})
            problems += nested_problems
    return record, problems


def inspect_product(target, settings, profile, platform_key, lane, revision, started, policy):
    """Inspect one built scheme target. Apps must also carry the lane and revision keys."""
    platform, _, suffix, installer = PLATFORMS[platform_key]
    mac = platform == "macos"
    app = ROOT / DERIVED / "Build/Products" / f"{CONFIGURATION}{suffix}" / settings["WRAPPER_NAME"]
    product = {"target": target, "product": str(app.relative_to(ROOT)), "installer": installer}
    info_path = app / "Contents/Info.plist" if mac else app / "Info.plist"
    if not info_path.exists():
        return product, [f"{target}: no product at {product['product']}"]

    record, problems = inspect_bundle(target, app, mac, bool(suffix), profile, platform, lane, policy,
                                      declared=declared_entitlements(settings))
    with open(info_path, "rb") as handle:
        info = plistlib.load(handle)
    executable = (app / "Contents/MacOS" if mac else app) / info.get("CFBundleExecutable", "")
    if not executable.is_file() or executable.stat().st_mtime < started:
        problems.append(f"{target}: the executable was not produced by this run")

    prefix = settings.get("LAB_BUNDLE_PREFIX", "")
    bundle_id = info.get("CFBundleIdentifier", "unknown")
    if prefix and bundle_id.startswith(prefix + "."):
        bundle_id = "$(LAB_BUNDLE_PREFIX)" + bundle_id[len(prefix):]
    product.update({
        "bundleIdentifier": bundle_id,
        "distributionLane": info.get("LabDistributionLane", "undeclared"),
        "sourceRevision": info.get("LabSourceRevision", "undeclared"),
    })
    product.update(record)
    if is_app(settings):
        if product["distributionLane"] != lane:
            problems.append(f"{target}: Info.plist says lane {product['distributionLane']}, expected {lane}")
        if product["sourceRevision"] != revision:
            problems.append(f"{target}: Info.plist says revision {product['sourceRevision']}, expected {revision}")
    return product, problems


# MARK: - Main

def source_revision():
    toplevel = run(["git", "rev-parse", "--show-toplevel"])
    if toplevel.returncode != 0 or Path(toplevel.stdout.strip()).resolve() != ROOT:
        return {"checkout": "not a Git checkout", "revision": "unknown", "commit": None, "dirty": None}
    commit = first_line(["git", "rev-parse", "HEAD"])
    dirty = bool(run(["git", "status", "--porcelain"]).stdout.strip())
    short = first_line(["git", "rev-parse", "--short", "HEAD"])
    return {"checkout": "git", "revision": short + ("-dirty" if dirty else ""), "commit": commit, "dirty": dirty}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--profile", action="append", default=[], metavar="NAME",
                        help="build only this profile (repeatable); default: every profile")
    parser.add_argument("--lane", default="Source", choices=LANES,
                        help="distribution lane passed as LAB_DISTRIBUTION_LANE (default: Source)")
    args = parser.parse_args()

    profiles = load_profiles()
    policy = load_policy()
    unknown = [name for name in args.profile if name not in profiles]
    if unknown:
        parser.error(f"unknown profile {', '.join(unknown)}; known: {', '.join(profiles)}")
    selected = set(args.profile or profiles)

    shutil.rmtree(ROOT / OUT, ignore_errors=True)
    (ROOT / OUT / "logs").mkdir(parents=True)
    started = datetime.datetime.now().timestamp()
    source = source_revision()

    # Map schemes to profiles from the resolved build settings of their application targets.
    by_profile = {name: [] for name in profiles}
    config_problems, library_schemes = [], []
    for scheme in list_schemes():
        targets, errors = scheme_targets(scheme)
        if targets is None:
            config_problems.append(f"{scheme}: {errors[0]}")
            continue
        apps = [t for t in targets if is_app(t["buildSettings"])]
        if not apps:
            library_schemes.append(scheme)  # package schemes; the host schemes build them
            continue
        scheme_profiles = {t["buildSettings"].get("LAB_BUILD_PROFILE") for t in apps}
        if len(scheme_profiles) != 1:
            config_problems.append(f"{scheme}: application targets span profiles {sorted(map(str, scheme_profiles))}")
            continue
        profile = scheme_profiles.pop()
        if profile not in by_profile:
            config_problems.append(f"{scheme}: profile {profile!r} has no file in Config/Profiles")
            continue
        strays = [t["target"] for t in targets if t["buildSettings"].get("LAB_BUILD_PROFILE") != profile]
        problems = [f"builds targets from another profile: {', '.join(strays)}"] if strays else []
        executables = [t for t in targets if is_executable(t["buildSettings"])]
        by_profile[profile].append({"scheme": scheme, "apps": apps, "executables": executables, "problems": problems})

    prefix = ""
    for entries in by_profile.values():
        for entry in entries:
            prefix = prefix or entry["apps"][0]["buildSettings"].get("LAB_BUNDLE_PREFIX", "")

    manifest = {
        "schemaVersion": 1,
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "command": " ".join(["script/build_manifest.py"] + sys.argv[1:]),
        "source": source,
        "toolchain": {
            "xcode": " ".join(run(["xcodebuild", "-version"]).stdout.split()),
            "swift": first_line(["xcrun", "swift", "--version"]),
            "host": f"macOS {first_line(['sw_vers', '-productVersion'])} ({first_line(['sw_vers', '-buildVersion'])})",
        },
        "configuration": CONFIGURATION,
        "lane": args.lane,
        "localConfiguration": "present (values not recorded)" if (ROOT / "Config/Local.xcconfig").exists() else "absent",
        "bundlePrefix": f"{DEFAULT_BUNDLE_PREFIX} (tracked default)" if prefix == DEFAULT_BUNDLE_PREFIX else "local override (not recorded)",
        "configurationProblems": config_problems,
        "librarySchemes": library_schemes,
        "profiles": [],
    }

    for name, profile in profiles.items():
        record = {"name": name, "config": profile["config"], "externalSetup": profile["externalSetup"]}
        manifest["profiles"].append(record)
        if name not in selected:
            record.update(status="skipped", reason="not selected with --profile")
            continue
        if not by_profile[name]:
            record.update(status="skipped", reason="no scheme builds a target attached to this profile yet")
            continue
        record["schemes"] = []
        for entry in by_profile[name]:
            scheme = entry["scheme"]
            platform_key = entry["apps"][0]["buildSettings"].get("PLATFORM_NAME", "")
            if platform_key not in PLATFORMS:
                record["schemes"].append({"scheme": scheme, "status": "failed",
                                          "problems": [f"no destination for platform {platform_key!r}"]})
                continue
            destination = PLATFORMS[platform_key][1]
            log = OUT / "logs" / f"{scheme}.log"
            command = ["xcodebuild", "-project", PROJECT, "-scheme", scheme, "-configuration", CONFIGURATION,
                       "-destination", destination, "-derivedDataPath", str(DERIVED),
                       f"LAB_SOURCE_REVISION={source['revision']}", f"LAB_DISTRIBUTION_LANE={args.lane}", "build"]
            print(f"==> {name}: {scheme} ({destination})", flush=True)
            with open(ROOT / log, "w") as handle:
                exit_status = subprocess.run(command, cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT).returncode
            result = {"scheme": scheme, "destination": destination, "command": " ".join(
                f"'{part}'" if " " in part else part for part in command), "exitStatus": exit_status,
                "log": str(log), "products": [], "problems": list(entry["problems"])}
            if exit_status != 0:
                errors = [relative(line.strip()) for line in (ROOT / log).read_text().splitlines() if ": error:" in line]
                result["problems"].append(f"xcodebuild exited {exit_status}" + (f": {errors[0]}" if errors else ""))
            else:
                for app in entry["executables"]:
                    product, problems = inspect_product(app["target"], app["buildSettings"], name, platform_key,
                                                        args.lane, source["revision"], started, policy)
                    result["products"].append(product)
                    result["problems"] += problems
            result["status"] = "built" if exit_status == 0 and not result["problems"] else "failed"
            record["schemes"].append(result)
        record["status"] = "built" if all(s["status"] == "built" for s in record["schemes"]) else "failed"
        if record["status"] == "failed":
            record["reason"] = "; ".join(p for s in record["schemes"] for p in s.get("problems", []))

    summary = {state: [p["name"] for p in manifest["profiles"] if p["status"] == state]
               for state in ("built", "skipped", "failed")}
    manifest["summary"] = summary
    path = ROOT / OUT / "manifest.json"
    path.write_text(json.dumps(manifest, indent=2) + "\n")

    print(f"\nRevision {source['revision']}, {manifest['toolchain']['xcode']}, {CONFIGURATION}, {args.lane} lane")
    for record in manifest["profiles"]:
        if record["status"] == "built":
            detail = ", ".join(f"{s['scheme']} ({p['sdk']})" for s in record["schemes"] for p in s["products"])
        else:
            detail = record.get("reason", "")
        print(f"  {record['name']:<17} {record['status']:<8} {detail}")
    for problem in config_problems:
        print(f"  configuration: {problem}")
    print(f"Wrote {OUT / 'manifest.json'}")
    return 1 if summary["failed"] or config_problems else 0


if __name__ == "__main__":
    sys.exit(main())
