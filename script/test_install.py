import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import tempfile
import unittest


class InstallTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        scripts = self.root / "script"
        self.commands = self.root / "bin"
        scripts.mkdir()
        self.commands.mkdir()
        self.destination = self.root / "Applications/Usage Rings.app"
        self.source = self.root / "dist/Usage Rings.app"
        self.make_app(self.destination, "0.1.8", "26", "existing app")
        self.make_app(self.source, "0.1.8", "27", "new app")
        self.config = self.root / "claude-config"
        self.config.mkdir()
        self.settings = self.config / "settings.json"
        self.settings.write_text("{}\n")
        self.stopped = self.root / "app-stopped"
        self.widgets_checked = self.root / "widgets-checked"
        self.opened = self.root / "app-opened"

        install = Path(__file__).with_name("install.sh").read_text()
        assignment = 'DESTINATION="$HOME/Applications/Usage Rings.app"'
        self.assertEqual(install.count(assignment), 1)
        install = install.replace(assignment, f"DESTINATION={shlex.quote(str(self.destination))}")
        launcher = '/usr/bin/open "$DESTINATION"'
        self.assertEqual(install.count(launcher), 1)
        install = install.replace(launcher, f'{shlex.quote(str(self.commands / "open"))} "$DESTINATION"')
        self.installer = scripts / "install.sh"
        self.installer.write_text(install)
        shutil.copyfile(Path(__file__).with_name("claude-statusline-setup.py"), scripts / "claude-statusline-setup.py")
        self.write_command(scripts / "build.sh", "exit 0")
        self.write_command(self.commands / "plutil", "printf 'work.hayashigoto.UsageRings\\n'")
        self.write_command(self.commands / "pkill", f"touch {shlex.quote(str(self.stopped))}")
        self.write_command(self.commands / "pgrep", f"touch {shlex.quote(str(self.widgets_checked))}\nexit 1")
        self.write_command(self.commands / "ditto", 'mkdir -p "$2"\ncp -R "$1/." "$2/"')
        self.write_command(self.commands / "codesign", "exit 0")
        self.write_command(self.commands / "open", f"touch {shlex.quote(str(self.opened))}")

    @staticmethod
    def make_app(app, version, build, marker):
        (app / "Contents/Helpers").mkdir(parents=True, exist_ok=True)
        (app / "installed.txt").write_text(marker)
        (app / "Contents/Helpers/UsageRingsStatusline").write_text("fixture")
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "work.hayashigoto.UsageRings",
            "CFBundleShortVersionString": version, "CFBundleVersion": build,
        }))

    @staticmethod
    def write_command(path, body):
        path.write_text(f"#!/usr/bin/env bash\nset -euo pipefail\n{body}\n")
        path.chmod(0o755)

    def install(self):
        result = subprocess.run(
            ["bash", str(self.installer)],
            env={**os.environ, "PATH": f"{self.commands}:{os.environ['PATH']}", "CLAUDE_CONFIG_DIR": str(self.config)},
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(list(self.destination.parent.glob(".usage-rings-*")), [])
        return result

    def assert_existing_app_untouched(self):
        self.assertEqual((self.destination / "installed.txt").read_text(), "existing app")
        self.assertFalse(self.stopped.exists())
        self.assertFalse(self.widgets_checked.exists())
        self.assertFalse(self.opened.exists())

    def assert_new_app_opened(self):
        self.assertEqual((self.destination / "installed.txt").read_text(), "new app")
        self.assertTrue(self.opened.exists())
        self.assertTrue(self.widgets_checked.exists())

    def test_failed_copy_preserves_existing_app(self):
        self.write_command(self.commands / "ditto", 'mkdir -p "$2"\ncp -R "$1/." "$2/"\nexit 23')
        self.assertEqual(self.install().returncode, 23)
        self.assert_existing_app_untouched()

    def test_failed_signature_check_preserves_existing_app(self):
        self.write_command(self.commands / "codesign", "exit 24")
        self.assertEqual(self.install().returncode, 24)
        self.assert_existing_app_untouched()

    def test_rejects_older_version_even_with_a_higher_build(self):
        self.make_app(self.source, "0.1.7", "30", "new app")
        result = self.install()
        self.assertEqual(result.returncode, 1)
        self.assertIn("version must not be older", result.stderr)
        self.assert_existing_app_untouched()

    def test_rejects_non_increasing_builds_even_with_a_newer_version(self):
        for version, build in (("0.1.8", "25"), ("0.1.8", "26"), ("0.1.9", "26")):
            with self.subTest(version=version, build=build):
                self.make_app(self.source, version, build, "new app")
                result = self.install()
                self.assertEqual(result.returncode, 1)
                self.assertIn("build must be greater", result.stderr)
                self.assert_existing_app_untouched()

    def test_compares_version_components_numerically(self):
        self.make_app(self.destination, "0.1.9", "26", "existing app")
        self.make_app(self.source, "0.1.10", "27", "new app")
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_new_app_opened()

    def test_custom_statusline_is_preserved_and_app_opens(self):
        original = '{"statusLine":{"type":"command","command":"custom-line"},"model":"opus"}\n'
        self.settings.write_text(original)
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.settings.read_text(), original)
        self.assert_new_app_opened()

    def test_fresh_install_checks_the_future_helper_path(self):
        shutil.rmtree(self.destination)
        self.settings.unlink()
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_new_app_opened()
        self.assertEqual(json.loads(self.settings.read_text())["statusLine"]["command"],
                         shlex.quote(str(self.destination / "Contents/Helpers/UsageRingsStatusline")))

    def test_invalid_settings_are_rejected_before_stopping_the_app(self):
        self.settings.write_text("{")
        result = self.install()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Could not read valid Claude settings", result.stderr)
        self.assertEqual(self.settings.read_text(), "{")
        self.assert_existing_app_untouched()

    def test_late_settings_error_still_opens_the_new_app(self):
        self.write_command(self.commands / "pkill", f"touch {shlex.quote(str(self.stopped))}\nprintf '{{' > {shlex.quote(str(self.settings))}")
        result = self.install()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Claude status line could not be configured", result.stderr)
        self.assert_new_app_opened()

    def test_settings_write_failure_still_opens_the_new_app(self):
        setup = self.installer.with_name("claude-statusline-setup.py")
        implementation = setup.with_name("setup-implementation.py")
        setup.rename(implementation)
        setup.write_text(
            "import runpy\nfrom unittest.mock import patch\n"
            "with patch('os.replace', side_effect=PermissionError):\n"
            f"    runpy.run_path({str(implementation)!r}, run_name='__main__')\n"
        )
        result = self.install()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Could not update Claude settings", result.stderr)
        self.assertEqual(self.settings.read_text(), "{}\n")
        self.assertEqual(list(self.config.glob(".usage-rings-*")), [])
        self.assert_new_app_opened()

    def test_custom_statusline_added_after_preflight_is_preserved(self):
        custom = '{"statusLine":{"type":"command","command":"new-custom-line"}}'
        self.write_command(self.commands / "pkill", f"touch {shlex.quote(str(self.stopped))}\nprintf '%s' {shlex.quote(custom)} > {shlex.quote(str(self.settings))}")
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.settings.read_text(), custom)
        self.assert_new_app_opened()


if __name__ == "__main__":
    unittest.main()
