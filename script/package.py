#!/usr/bin/env python3
"""Package verified macOS bundles with an explicit notarized or unnotarized mode."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
METADATA_KEYS = (
    "CFBundleShortVersionString", "CFBundleVersion", "LSMinimumSystemVersion",
    "UsageRingsSourceRevision", "UsageRingsSourceDirty", "UsageRingsBuildConfiguration",
)
SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def read_sparkle_configuration():
    configuration = json.loads((ROOT / "script/sparkle-config.json").read_text())
    configuration["feed_url"] = os.environ.get("SPARKLE_FEED_URL", configuration["feed_url"])
    configuration["public_ed_key"] = os.environ.get("SPARKLE_PUBLIC_ED_KEY", configuration["public_ed_key"])
    feed = urlsplit(configuration["feed_url"])
    if feed.scheme != "https" or not feed.hostname or feed.username or feed.password or feed.fragment:
        raise ValueError("Sparkle feed must be an HTTPS URL without credentials or a fragment.")
    try:
        key = base64.b64decode(configuration["public_ed_key"], validate=True)
    except (ValueError, TypeError) as error:
        raise ValueError("Sparkle public key is not configured correctly.") from error
    if len(key) != 32:
        raise ValueError("Sparkle public key is not configured; release packaging is disabled.")
    if not re.fullmatch(r"[A-Za-z0-9._-]+", configuration["keychain_account"]):
        raise ValueError("Sparkle keychain account is invalid.")
    return configuration


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f"{args[0]} failed: {result.stderr.strip() or result.stdout.strip()}")
    return result


def read_metadata(app):
    with (app / "Contents/Info.plist").open("rb") as file:
        host = plistlib.load(file)
    widget = app / "Contents/PlugIns/UsageRingsWidget.appex"
    with (widget / "Contents/Info.plist").open("rb") as file:
        extension = plistlib.load(file)
    if host.get("CFBundleIdentifier") != "work.hayashigoto.UsageRings" or \
            extension.get("CFBundleIdentifier") != "work.hayashigoto.UsageRings.Widget":
        raise ValueError("Unexpected app or widget bundle identifier.")
    for key in METADATA_KEYS:
        if key not in host or host[key] != extension.get(key):
            raise ValueError(f"App/widget metadata missing or mismatched: {key}")
    if not re.fullmatch(r"(?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]{0,3})",
                        str(host["CFBundleShortVersionString"])):
        raise ValueError("Invalid app version.")
    if not re.fullmatch(r"[1-9][0-9]{0,3}", str(host["CFBundleVersion"])):
        raise ValueError("Invalid build number.")
    if not re.fullmatch(r"[0-9a-f]{40}", str(host["UsageRingsSourceRevision"])):
        raise ValueError("Missing full source commit hash.")
    if host["UsageRingsSourceDirty"] is not False:
        raise ValueError("Packaging requires an app built from a clean source checkout.")
    if host["UsageRingsBuildConfiguration"] != "release":
        raise ValueError("Packaging requires CONFIGURATION=release.")
    if host["LSMinimumSystemVersion"] != "26.0":
        raise ValueError("Unexpected minimum macOS version.")
    if host.get("CFBundleIconName") != "AppIcon" or host.get("CFBundleIconFile") not in ("AppIcon", "AppIcon.icns"):
        raise ValueError("Missing appearance-aware app icon metadata.")
    sparkle = read_sparkle_configuration()
    if host.get("SUFeedURL") != sparkle["feed_url"] or host.get("SUPublicEDKey") != sparkle["public_ed_key"]:
        raise ValueError("Sparkle feed or public key is missing or differs from the build configuration.")
    if host.get("SUEnableAutomaticChecks") is False:
        raise ValueError("Release Sparkle update checks are not configured.")
    return host, widget


def inspect_bundle(app, mode):
    if mode not in ("notarized", "unnotarized", "draft-unnotarized"):
        raise ValueError("Unknown distribution mode.")
    require_notarization = mode == "notarized"
    metadata, widget = read_metadata(app)
    components = {
        "app": (app, app / "Contents/MacOS/UsageRings"),
        "widget": (widget, widget / "Contents/MacOS/UsageRingsWidget"),
        "statusline": (app / "Contents/Helpers/UsageRingsStatusline",) * 2,
        "cli": (app / "Contents/Helpers/usage-rings",) * 2,
        "budget-hook": (app / "Contents/Helpers/UsageRingsBudgetHook",) * 2,
    }
    framework = app / "Contents/Frameworks/Sparkle.framework"
    version = framework / "Versions/Current"
    sparkle_components = {
        "sparkle": (framework, framework / "Sparkle"),
        "sparkle-autoupdate": (version / "Autoupdate",) * 2,
        "sparkle-updater": (version / "Updater.app", version / "Updater.app/Contents/MacOS/Updater"),
        "sparkle-downloader": (version / "XPCServices/Downloader.xpc", version / "XPCServices/Downloader.xpc/Contents/MacOS/Downloader"),
        "sparkle-installer": (version / "XPCServices/Installer.xpc", version / "XPCServices/Installer.xpc/Contents/MacOS/Installer"),
    }
    components.update(sparkle_components)
    dependencies = run("/usr/bin/otool", "-L", str(app / "Contents/MacOS/UsageRings")).stdout
    if not re.search(r"@rpath/Sparkle\.framework/Versions/[^/]+/Sparkle", dependencies):
        raise ValueError("The host executable does not link the embedded Sparkle.framework.")
    rpaths = run("/usr/bin/otool", "-l", str(app / "Contents/MacOS/UsageRings")).stdout
    if "@executable_path/../Frameworks" not in rpaths:
        raise ValueError("The host executable cannot locate embedded Sparkle.framework.")
    for resource in ("LICENSE", "THIRD_PARTY_NOTICES.md", "AppIcon.icns", "Assets.car", "Skills/usage-rings-budget/SKILL.md"):
        if not (app / "Contents/Resources" / resource).is_file():
            raise ValueError(f"Missing bundled resource: {resource}")
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
    architecture = None
    signatures = {}
    teams = set()
    for name, (code, executable) in components.items():
        if not executable.is_file():
            raise ValueError(f"Missing executable: {name}")
        archs = sorted(run("/usr/bin/lipo", "-archs", str(executable)).stdout.split())
        if not archs or not set(archs) <= {"arm64", "x86_64"}:
            raise ValueError(f"Unsupported architecture: {name}")
        if name in sparkle_components:
            if not set(architecture or []) <= set(archs):
                raise ValueError(f"Sparkle architecture is incompatible with the app: {name}")
            if not executable.resolve().is_relative_to(app.resolve()):
                raise ValueError(f"Sparkle code points outside the app: {name}")
        else:
            if architecture is not None and architecture != archs:
                raise ValueError("App, widget, and helper architectures differ.")
            architecture = archs
        run("/usr/bin/codesign", "--verify", "--strict", str(code))
        details = run("/usr/bin/codesign", "-d", "--verbose=4", str(code)).stderr
        developer_id = "Authority=Developer ID Application:" in details
        flags = re.search(r"\bflags=0x[0-9a-fA-F]+\(([^)]*)\)", details)
        signature = {
            "type": "developer-id" if developer_id else "ad-hoc" if "Signature=adhoc" in details else "other",
            "hardened_runtime": bool(flags and "runtime" in flags.group(1).split(",")),
            "secure_timestamp": bool(re.search(r"^Timestamp=.+", details, re.MULTILINE)),
        }
        signatures[name] = signature
        entitlements_xml = run("/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(code)).stdout.strip()
        entitlements = plistlib.loads(entitlements_xml.encode()) if entitlements_xml else {}
        if entitlements.get("com.apple.security.get-task-allow"):
            raise ValueError(f"Debugging entitlement present: {name}")
        if name == "widget" and (entitlements.get("com.apple.security.app-sandbox") is not True or
                                 entitlements.get("com.apple.security.network.client") is not True):
            raise ValueError("Widget sandbox/network entitlements are missing.")
        if require_notarization:
            if not developer_id or not signature["hardened_runtime"] or not signature["secure_timestamp"]:
                raise ValueError("Notarized packaging requires Developer ID, hardened runtime, and secure timestamps on all code. Select --unnotarized explicitly for an unnotarized release.")
            run("/usr/bin/codesign", "--verify", "--strict", "-R",
                "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists", str(code))
            team = re.search(r"^TeamIdentifier=([A-Z0-9]+)$", details, re.MULTILINE)
            if not team:
                raise ValueError(f"Developer team identifier missing: {name}")
            teams.add(team.group(1))
    if require_notarization:
        if len(teams) != 1:
            raise ValueError("All code must be signed by the same developer team.")
        run("/usr/bin/xcrun", "stapler", "validate", str(app))
        run("/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", str(app))
    return {
        "version": metadata["CFBundleShortVersionString"],
        "build": metadata["CFBundleVersion"],
        "source_revision": metadata["UsageRingsSourceRevision"],
        "source_dirty": False,
        "configuration": "release",
        "minimum_macos": metadata["LSMinimumSystemVersion"],
        "architectures": architecture,
        "signatures": signatures,
        "notarization": "stapled-and-gatekeeper-accepted" if require_notarization else "not-verified",
        "distribution": mode,
        "updater": {"feed_url": metadata["SUFeedURL"], "public_ed_key": metadata["SUPublicEDKey"]},
    }


def validate_appcast(appcast, archive, manifest, expected_url, staging):
    root = ET.parse(appcast).getroot()
    items = root.findall("./channel/item")
    if len(items) != 1:
        raise ValueError("The generated appcast must contain exactly this release.")
    item = items[0]
    enclosure = item.find("enclosure")
    signature = enclosure.get(f"{{{SPARKLE_NAMESPACE}}}edSignature", "") if enclosure is not None else ""
    try:
        signature_bytes = base64.b64decode(signature, validate=True)
    except ValueError as error:
        raise ValueError("The generated update has no valid Ed25519 signature.") from error
    if enclosure is None or len(signature_bytes) != 64:
        raise ValueError("The generated update has no valid Ed25519 signature.")
    version = enclosure.get(f"{{{SPARKLE_NAMESPACE}}}version") or item.findtext(f"{{{SPARKLE_NAMESPACE}}}version")
    short_version = enclosure.get(f"{{{SPARKLE_NAMESPACE}}}shortVersionString") or item.findtext(f"{{{SPARKLE_NAMESPACE}}}shortVersionString")
    minimum_system = item.findtext(f"{{{SPARKLE_NAMESPACE}}}minimumSystemVersion")
    if (enclosure.get("url") != expected_url or enclosure.get("length") != str(archive.stat().st_size)
            or version != manifest["build"] or short_version != manifest["version"]
            or minimum_system != manifest["minimum_macos"]):
        raise ValueError("The generated appcast does not match this verified archive.")
    # Verify against the key embedded in the app rather than accepting a valid
    # signature from a different keychain account.
    run("/usr/bin/swift", "-module-cache-path", str(staging / "swift-module-cache"),
        str(ROOT / "script/verify_sparkle_update.swift"), manifest["updater"]["public_ed_key"],
        signature, str(archive))
    return signature


def create_appcast(archive, appcast, manifest, staging):
    configuration = read_sparkle_configuration()
    executable = ROOT / ".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
    if not executable.is_file():
        raise ValueError("Sparkle generate_appcast is missing; resolve the package dependency first.")
    archives = staging / "sparkle-archives"
    archives.mkdir()
    run("/usr/bin/ditto", str(archive), str(archives / archive.name))
    prefix = os.environ.get("SPARKLE_DOWNLOAD_URL_PREFIX",
                            f"https://github.com/hayashiii-ghub/ato/releases/download/v{manifest['version']}/")
    parsed = urlsplit(prefix)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
        raise ValueError("Sparkle download prefix must be an HTTPS URL without credentials or a fragment.")
    if not prefix.endswith("/"):
        raise ValueError("Sparkle download prefix must end in a slash.")
    # Sparkle otherwise derives the feed title from the retained app folder name.
    appcast.write_text(
        f'<rss xmlns:sparkle="{SPARKLE_NAMESPACE}" version="2.0">'
        '<channel><title>ato?</title></channel></rss>', encoding="utf-8",
    )
    args = [str(executable), "--download-url-prefix", prefix, "--maximum-deltas", "0",
            "--link", "https://github.com/hayashiii-ghub/ato/releases", "-o", str(appcast)]
    private_key = os.environ.get("SPARKLE_ED_PRIVATE_KEY")
    if private_key:
        args += ["--ed-key-file", "-"]
    else:
        args += ["--account", configuration["keychain_account"]]
    args.append(str(archives))
    result = subprocess.run(args, input=private_key, text=True, capture_output=True)
    if result.returncode or not appcast.is_file():
        # Signing diagnostics can include key data. Never copy them into logs.
        raise ValueError("Sparkle appcast generation failed; the expected signing key may be unavailable.")
    return validate_appcast(appcast, archive, manifest, prefix + archive.name, staging)


def create_disk_image(app, staging, destination, mode):
    metadata = inspect_bundle(app, mode)
    architecture = ", ".join(metadata["architectures"])
    contents = staging / "dmg-contents"
    contents.mkdir()
    run("/usr/bin/ditto", str(app), str(contents / "Usage Rings.app"))
    (contents / "Applications").symlink_to("/Applications")
    (contents / "INSTALL.txt").write_text(
        f"ato? — macOS 26+, {architecture}\n\n"
        "Quit an existing copy, then drag ato? to Applications.\n"
        "Open the installed app and add ato? > AI Usage using Edit Widgets.\n"
        "Keep the app running to refresh usage. Xcode is not needed.\n\n"
        "This release is not notarized by Apple.\n"
        "macOS may block the first launch. If you trust this source, see Apple's\n"
        "per-app approval instructions: https://support.apple.com/102445\n"
        "Do not disable Gatekeeper or remove quarantine attributes.\n\n"
        "Claude Code status-line setup is optional and is not run automatically.\n"
        "Instructions: https://github.com/hayashiii-ghub/ato#accounts\n",
        encoding="utf-8",
    )
    run("/usr/bin/hdiutil", "create", "-volname", "ato?", "-srcfolder",
        str(contents), "-fs", "HFS+", "-format", "UDZO", str(destination))
    run("/usr/bin/hdiutil", "verify", str(destination))
    mount = staging / "dmg-mount"
    mount.mkdir()
    run("/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
        "-mountpoint", str(mount), str(destination))
    try:
        shortcut = mount / "Applications"
        if not shortcut.is_symlink() or shortcut.readlink() != Path("/Applications"):
            raise ValueError("Disk image Applications shortcut is missing or incorrect.")
        if inspect_bundle(mount / "Usage Rings.app", mode) != inspect_bundle(app, mode):
            raise ValueError("Disk image changed bundle metadata or signing state.")
    finally:
        run("/usr/bin/hdiutil", "detach", str(mount))


def package(app, output, mode):
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".package-", dir=output) as temporary:
        staging = Path(temporary)
        staged_app = staging / "Usage Rings.app"
        run("/usr/bin/ditto", str(app), str(staged_app))
        manifest = inspect_bundle(staged_app, mode)
        architecture = "universal" if len(manifest["architectures"]) == 2 else manifest["architectures"][0]
        name = (f"Usage-Rings-{manifest['version']}-build{manifest['build']}-"
                f"{manifest['source_revision'][:12]}-macOS-{architecture}-{manifest['distribution']}")
        # Stable asset names support GitHub's releases/latest/download URLs. A
        # versioned local directory keeps previous build artifacts intact.
        destination = output / name if mode == "unnotarized" else output
        basename = "usage-rings-macos" if mode == "unnotarized" else name
        files = [basename + suffix for suffix in (".zip", ".json", ".sha256")]
        if mode == "unnotarized":
            files.append(basename + ".dmg")
        if mode != "draft-unnotarized":
            files.append("appcast.xml")
        if (mode == "unnotarized" and destination.exists()) or any((destination / file).exists() for file in files):
            raise ValueError("An artifact with this version/build/revision already exists; use a new build number or remove the old local artifact deliberately.")
        archive = staging / files[0]
        run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(staged_app), str(archive))
        extracted = staging / "roundtrip"
        run("/usr/bin/ditto", "-x", "-k", str(archive), str(extracted))
        if inspect_bundle(extracted / "Usage Rings.app", mode) != manifest:
            raise ValueError("Archive round-trip changed bundle metadata or signing state.")
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        manifest.update({"archive": files[0], "sha256": digest})
        checksums = [f"{digest}  {files[0]}"]
        if mode == "unnotarized":
            disk_image = staging / files[3]
            create_disk_image(staged_app, staging, disk_image, mode)
            image_digest = hashlib.sha256(disk_image.read_bytes()).hexdigest()
            manifest.update({"disk_image": files[3], "disk_image_sha256": image_digest})
            checksums.append(f"{image_digest}  {files[3]}")
        if mode != "draft-unnotarized":
            appcast = staging / "appcast.xml"
            signature = create_appcast(archive, appcast, manifest, staging)
            appcast_digest = hashlib.sha256(appcast.read_bytes()).hexdigest()
            manifest.update({"appcast": "appcast.xml", "appcast_sha256": appcast_digest,
                             "update_ed_signature": signature})
            checksums.append(f"{appcast_digest}  appcast.xml")
        (staging / files[1]).write_text(json.dumps(manifest, indent=2) + "\n")
        manifest_digest = hashlib.sha256((staging / files[1]).read_bytes()).hexdigest()
        checksums.append(f"{manifest_digest}  {files[1]}")
        (staging / files[2]).write_text("\n".join(checksums) + "\n")
        ready = staging / "ready"
        ready.mkdir()
        for file in files:
            (staging / file).replace(ready / file)
        if mode == "unnotarized":
            ready.replace(destination)
        else:
            for file in files:
                (ready / file).replace(destination / file)
        return destination / (files[3] if mode == "unnotarized" else files[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--draft", action="store_true", help="Create an unnotarized review ZIP.")
    modes.add_argument("--unnotarized", action="store_true", help="Create an explicitly unnotarized DMG and ZIP for distribution.")
    parser.add_argument("--app", type=Path, default=ROOT / "dist/Usage Rings.app")
    parser.add_argument("--output", type=Path, default=ROOT / "dist/packages")
    args = parser.parse_args()
    try:
        mode = "draft-unnotarized" if args.draft else "unnotarized" if args.unnotarized else "notarized"
        archive = package(args.app.resolve(), args.output.resolve(), mode)
    except (ValueError, OSError, KeyError, TypeError, plistlib.InvalidFileException, ET.ParseError) as error:
        parser.exit(1, f"Packaging: {error}\n")
    print(archive)


if __name__ == "__main__":
    main()
