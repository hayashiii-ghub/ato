#!/usr/bin/env python3
"""Check metadata rejection and distribution trust gates without accessing accounts."""
import importlib.util
import base64
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("distribution", ROOT / "script/package.py")
distribution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distribution)
PUBLIC_KEY = base64.b64encode(bytes(32)).decode()
SPARKLE_CONFIGURATION = {
    "feed_url": "https://github.com/hayashiii-ghub/usage-rings/releases/latest/download/appcast.xml",
    "public_ed_key": PUBLIC_KEY,
    "keychain_account": "work.hayashigoto.UsageRings",
}


class BuildMetadataTests(unittest.TestCase):
    def validate(self, **overrides):
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        environment = dict(os.environ, APP_VERSION="0.1.1", APP_BUILD="2", CONFIGURATION="release",
                           CODE_SIGN_IDENTITY="-", SOURCE_REVISION=revision,
                           SPARKLE_PUBLIC_ED_KEY=PUBLIC_KEY, SPARKLE_FEED_URL=SPARKLE_CONFIGURATION["feed_url"])
        environment.update(overrides)
        return subprocess.run(["bash", "-euo", "pipefail", "-c", 'source script/build-metadata.sh'],
                              cwd=ROOT, env=environment, capture_output=True, text=True)

    def test_valid_metadata(self):
        self.assertEqual(self.validate().returncode, 0)

    def test_rejects_unsafe_or_misleading_inputs_before_build(self):
        for values in ({"APP_VERSION": "0.1.1</string>"}, {"APP_VERSION": ""},
                       {"APP_BUILD": "-1"}, {"APP_BUILD": "10000"},
                       {"CONFIGURATION": "--skip-build"}, {"SOURCE_REVISION": "main"},
                       {"SOURCE_REVISION": "0" * 40}, {"CODE_SIGN_IDENTITY": "Developer ID Application: guessed"},
                       {"SPARKLE_PUBLIC_ED_KEY": ""}, {"SPARKLE_PUBLIC_ED_KEY": "not-a-key"},
                       {"SPARKLE_FEED_URL": "http://example.com/appcast.xml"},
                       {"SPARKLE_FEED_URL": "https://user:password@example.com/appcast.xml"}):
            with self.subTest(values=values):
                self.assertNotEqual(self.validate(**values).returncode, 0)

    def test_unconfigured_debug_builds_are_allowed_without_a_product_key(self):
        self.assertEqual(self.validate(CONFIGURATION="debug", SPARKLE_PUBLIC_ED_KEY="").returncode, 0)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name) / "Usage Rings.app"
        self.widget = self.app / "Contents/PlugIns/UsageRingsWidget.appex"
        self.host = {
            "CFBundleIdentifier": "work.hayashigoto.UsageRings",
            "CFBundleShortVersionString": "0.1.1", "CFBundleVersion": "2",
            "LSMinimumSystemVersion": "26.0", "UsageRingsSourceRevision": "a" * 40,
            "UsageRingsSourceDirty": False, "UsageRingsBuildConfiguration": "release",
            "SUFeedURL": SPARKLE_CONFIGURATION["feed_url"], "SUPublicEDKey": PUBLIC_KEY,
        }
        self.extension = dict(self.host, CFBundleIdentifier="work.hayashigoto.UsageRings.Widget")
        self.write_metadata()
        framework = self.app / "Contents/Frameworks/Sparkle.framework"
        version = framework / "Versions/Current"
        for path in (self.app / "Contents/MacOS/UsageRings", self.widget / "Contents/MacOS/UsageRingsWidget",
                     self.app / "Contents/Helpers/UsageRingsStatusline", self.app / "Contents/Helpers/usage-rings",
                     framework / "Sparkle",
                     version / "Autoupdate", version / "Updater.app/Contents/MacOS/Updater",
                     version / "XPCServices/Downloader.xpc/Contents/MacOS/Downloader",
                     version / "XPCServices/Installer.xpc/Contents/MacOS/Installer"):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture")
        for resource in ("LICENSE", "THIRD_PARTY_NOTICES.md", "AppIcon.icns", "Skills/usage-rings-budget/SKILL.md"):
            path = self.app / "Contents/Resources" / resource
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture")
        self.details = "Signature=adhoc\nCodeDirectory flags=0x2(adhoc)\nTeamIdentifier=not set\n"
        self.details_overrides = {}
        self.architecture_override = None
        self.cli_architecture_override = None
        self.sparkle_architecture_override = None
        self.missing_rpath = False
        self.missing_sparkle_link = False
        self.failed_command = None
        self.failed_signature = None
        self.debug_entitlement = False
        self.mock = patch.object(distribution, "run", side_effect=self.fake_run).start()
        patch.object(distribution, "read_sparkle_configuration", return_value=SPARKLE_CONFIGURATION).start()
        self.addCleanup(patch.stopall)

    def write_metadata(self):
        for bundle, metadata in ((self.app, self.host), (self.widget, self.extension)):
            path = bundle / "Contents/Info.plist"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(plistlib.dumps(metadata))

    def fake_run(self, *args):
        if self.failed_command and self.failed_command in args:
            raise ValueError("fixture trust check failed")
        if self.failed_signature == args[-1] and args[0].endswith("codesign") and "--verify" in args:
            raise ValueError("fixture signature check failed")
        stdout, stderr = "", ""
        if args[0].endswith("lipo"):
            if "Sparkle.framework" in args[-1]:
                stdout = self.sparkle_architecture_override or "arm64 x86_64"
            elif args[-1].endswith("/Contents/Helpers/usage-rings"):
                stdout = self.cli_architecture_override or "arm64"
            else:
                stdout = self.architecture_override if self.architecture_override and "UsageRingsWidget" in args[-1] else "arm64"
        elif args[0].endswith("otool"):
            if "-L" in args:
                stdout = "" if self.missing_sparkle_link else "@rpath/Sparkle.framework/Versions/B/Sparkle"
            else:
                stdout = "" if self.missing_rpath else "path @executable_path/../Frameworks"
        elif "--verbose=4" in args:
            stderr = self.details_overrides.get(args[-1], self.details)
        elif "--entitlements" in args:
            entitlements = {"com.apple.security.get-task-allow": True} if self.debug_entitlement else {}
            if args[-1].endswith(".appex"):
                entitlements.update({"com.apple.security.app-sandbox": True, "com.apple.security.network.client": True})
            stdout = plistlib.dumps(entitlements).decode()
        return subprocess.CompletedProcess(args, 0, stdout, stderr)

    def developer_id(self):
        self.details = ("Authority=Developer ID Application: Fixture (TESTTEAM01)\n"
                        "CodeDirectory flags=0x10000(runtime)\nTimestamp=Oct 7, 2026\nTeamIdentifier=TESTTEAM01\n")

    def test_draft_reports_unnotarized_and_actual_architecture(self):
        manifest = distribution.inspect_bundle(self.app, "draft-unnotarized")
        self.assertEqual(manifest["distribution"], "draft-unnotarized")
        self.assertEqual(manifest["architectures"], ["arm64"])
        self.assertTrue(all(item["type"] == "ad-hoc" for item in manifest["signatures"].values()))
        self.assertIn("cli", manifest["signatures"])
        self.assertFalse(any("stapler" in call.args or "--assess" in call.args for call in self.mock.call_args_list))

    def test_explicit_unnotarized_mode_preserves_integrity_checks(self):
        manifest = distribution.inspect_bundle(self.app, "unnotarized")
        self.assertEqual(manifest["distribution"], "unnotarized")
        self.assertEqual(manifest["notarization"], "not-verified")
        self.assertTrue(all(item["type"] == "ad-hoc" for item in manifest["signatures"].values()))
        self.failed_command = "--verify"
        with self.assertRaisesRegex(ValueError, "trust check"):
            distribution.inspect_bundle(self.app, "unnotarized")

    def test_rejects_unknown_distribution_mode(self):
        with self.assertRaisesRegex(ValueError, "Unknown distribution mode"):
            distribution.inspect_bundle(self.app, "automatic")

    def test_runtime_is_reported_with_combined_signature_flags(self):
        for flags, expected in (("adhoc,runtime", True), ("runtime,adhoc", True), ("adhoc", False)):
            self.details = f"Signature=adhoc\nCodeDirectory flags=0x10002({flags})\n"
            with self.subTest(flags=flags):
                manifest = distribution.inspect_bundle(self.app, "unnotarized")
                self.assertTrue(all(item["hardened_runtime"] == expected for item in manifest["signatures"].values()))

    def test_notarized_packaging_rejects_ad_hoc(self):
        with self.assertRaisesRegex(ValueError, "Developer ID"):
            distribution.inspect_bundle(self.app, "notarized")

    def test_notarized_packaging_requires_runtime_timestamp_ticket_and_gatekeeper(self):
        self.developer_id()
        for missing in ("(runtime)", "Timestamp=Oct 7, 2026"):
            original = self.details
            self.details = original.replace(missing, "")
            with self.subTest(missing=missing), self.assertRaisesRegex(ValueError, "Developer ID"):
                distribution.inspect_bundle(self.app, "notarized")
            self.details = original
        for failed in ("stapler", "--assess"):
            self.failed_command = failed
            with self.subTest(failed=failed), self.assertRaisesRegex(ValueError, "trust check"):
                distribution.inspect_bundle(self.app, "notarized")
        self.failed_command = None
        self.assertEqual(distribution.inspect_bundle(self.app, "notarized")["distribution"], "notarized")

    def test_rejects_different_cpu_or_debugging_entitlements(self):
        self.architecture_override = "x86_64"
        with self.assertRaisesRegex(ValueError, "architectures differ"):
            distribution.inspect_bundle(self.app, "draft-unnotarized")
        self.architecture_override = None
        self.debug_entitlement = True
        with self.assertRaisesRegex(ValueError, "Debugging entitlement"):
            distribution.inspect_bundle(self.app, "draft-unnotarized")

    def test_notarized_packaging_rejects_a_mixed_team_or_unsigned_nested_component(self):
        self.developer_id()
        for name in ("UsageRingsStatusline", "usage-rings"):
            helper = str(self.app / "Contents/Helpers" / name)
            self.details_overrides[helper] = "Signature=adhoc\n"
            with self.subTest(helper=name, signature="ad-hoc"), self.assertRaisesRegex(ValueError, "Developer ID"):
                distribution.inspect_bundle(self.app, "notarized")
            self.details_overrides[helper] = self.details.replace("TESTTEAM01", "OTHERTEAM1")
            with self.subTest(helper=name, signature="different team"), self.assertRaisesRegex(ValueError, "same developer team"):
                distribution.inspect_bundle(self.app, "notarized")
            self.details_overrides.pop(helper)

    def test_requires_bundled_cli(self):
        (self.app / "Contents/Helpers/usage-rings").unlink()
        with self.assertRaisesRegex(ValueError, "Missing executable: cli"):
            distribution.inspect_bundle(self.app, "unnotarized")

    def test_requires_budget_skill(self):
        (self.app / "Contents/Resources/Skills/usage-rings-budget/SKILL.md").unlink()
        with self.assertRaisesRegex(ValueError, "Missing bundled resource: Skills/usage-rings-budget/SKILL.md"):
            distribution.inspect_bundle(self.app, "unnotarized")

    def test_cli_architecture_must_match_the_app(self):
        self.cli_architecture_override = "x86_64"
        with self.assertRaisesRegex(ValueError, "architectures differ"):
            distribution.inspect_bundle(self.app, "unnotarized")

    def test_cli_signature_must_verify(self):
        self.failed_signature = str(self.app / "Contents/Helpers/usage-rings")
        with self.assertRaisesRegex(ValueError, "signature check failed"):
            distribution.inspect_bundle(self.app, "unnotarized")

    def test_rejects_mismatched_metadata_dirty_source_and_debug_builds(self):
        for key, value in (("CFBundleVersion", "3"), ("UsageRingsSourceRevision", "b" * 40)):
            original = self.extension[key]
            self.extension[key] = value
            self.write_metadata()
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "mismatched"):
                distribution.read_metadata(self.app)
            self.extension[key] = original
        for key, value in (("UsageRingsSourceDirty", True), ("UsageRingsBuildConfiguration", "debug")):
            original = self.host[key]
            self.host[key] = self.extension[key] = value
            self.write_metadata()
            with self.subTest(key=key), self.assertRaises(ValueError):
                distribution.read_metadata(self.app)
            self.host[key] = self.extension[key] = original

    def test_requires_matching_update_configuration(self):
        for key, value in (("SUFeedURL", "https://example.com/appcast.xml"),
                           ("SUPublicEDKey", ""), ("SUEnableAutomaticChecks", False)):
            original = self.host.get(key)
            self.host[key] = value
            self.write_metadata()
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "Sparkle"):
                distribution.read_metadata(self.app)
            if original is None:
                self.host.pop(key)
            else:
                self.host[key] = original

    def test_sparkle_may_be_universal_but_must_include_the_host_architecture(self):
        self.assertEqual(distribution.inspect_bundle(self.app, "unnotarized")["architectures"], ["arm64"])
        self.sparkle_architecture_override = "x86_64"
        with self.assertRaisesRegex(ValueError, "Sparkle architecture"):
            distribution.inspect_bundle(self.app, "unnotarized")

    def test_requires_sparkle_code_and_host_linkage(self):
        self.missing_rpath = True
        with self.assertRaisesRegex(ValueError, "locate embedded Sparkle"):
            distribution.inspect_bundle(self.app, "unnotarized")
        self.missing_rpath = False
        self.missing_sparkle_link = True
        with self.assertRaisesRegex(ValueError, "does not link"):
            distribution.inspect_bundle(self.app, "unnotarized")
        self.missing_sparkle_link = False
        (self.app / "Contents/Frameworks/Sparkle.framework/Versions/Current/Updater.app/Contents/MacOS/Updater").unlink()
        with self.assertRaisesRegex(ValueError, "sparkle-updater"):
            distribution.inspect_bundle(self.app, "unnotarized")

    def test_notarized_mode_checks_the_sparkle_team_and_nested_signatures(self):
        self.developer_id()
        installer = str(self.app / "Contents/Frameworks/Sparkle.framework/Versions/Current/XPCServices/Installer.xpc")
        self.details_overrides[installer] = self.details.replace("TESTTEAM01", "OTHERTEAM1")
        with self.assertRaisesRegex(ValueError, "same developer team"):
            distribution.inspect_bundle(self.app, "notarized")


if __name__ == "__main__":
    unittest.main()
