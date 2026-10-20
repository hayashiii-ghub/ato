import importlib.util
import json
from pathlib import Path
import shlex
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("antigravity-statusline-setup.py")
spec = importlib.util.spec_from_file_location("antigravity_setup", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SetupTests(unittest.TestCase):
    helper = Path("/Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline")

    def run_setup(self, settings, helper, *arguments):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--settings", str(settings), "--helper", str(helper), *arguments],
            capture_output=True, text=True, check=False,
        )

    def test_setup_preserves_other_settings_and_is_idempotent(self):
        original = {"hooks": {"example": []}, "editorMode": "vim", "theme": "dark"}
        installed = module.configure(original, self.helper)
        self.assertEqual(installed, {
            **original,
            "statusLine": {
                "type": "command",
                "command": shlex.quote(str(self.helper)) + " --provider gemini",
                "stack_with_default": True,
            },
        })
        self.assertEqual(module.configure(installed, self.helper), installed)
        self.assertEqual(module.configure(installed, self.helper, uninstall=True), original)
        self.assertNotIn("statusLine", original)

    def test_existing_custom_statusline_is_not_replaced_or_enabled(self):
        for current in ({"type": "command", "command": "custom", "enabled": False}, None, False):
            with self.subTest(statusLine=current):
                original = {"statusLine": current, "editorMode": "vim"}
                with self.assertRaisesRegex(ValueError, "Existing Antigravity status line preserved"):
                    module.configure(original, self.helper)
                self.assertEqual(module.configure(original, self.helper, skip_existing=True), original)
                self.assertEqual(module.configure(original, self.helper, uninstall=True), original)

    def test_existing_owned_flags_remain_unchanged(self):
        installed = module.configure({}, self.helper)
        installed["statusLine"].update({"enabled": False, "stack_with_default": False, "padding": 2})
        self.assertEqual(module.configure(installed, self.helper), installed)

    def test_helper_path_is_one_shell_argument(self):
        helper = Path("/Applications/ato's $(echo wrong).app/Contents/Helpers/UsageRingsStatusline")
        command = module.configure({}, helper)["statusLine"]["command"]
        self.assertEqual(shlex.split(command), [str(helper), "--provider", "gemini"])

    def test_preflight_does_not_create_config_or_require_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = Path(directory)/"config/antigravity-cli/settings.json"
            helper = Path(directory)/"missing-helper"
            result = self.run_setup(settings, helper, "--check")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(settings.parent.exists())
            self.assertFalse(helper.exists())

    def test_install_creates_private_settings_and_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = Path(directory)/"config/antigravity-cli/settings.json"
            helper = Path(directory)/"helper"
            helper.write_text("fixture")
            result = self.run_setup(settings, helper)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(stat.S_IMODE(settings.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(settings.parent.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(settings.parent.parent.stat().st_mode), 0o700)
            self.assertEqual(list(settings.parent.glob("settings.json.ato-backup-*")), [])

    def test_existing_settings_get_exact_private_backup_and_no_duplicate_on_repeat(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = Path(directory)/"settings.json"
            original = b'{ "editorMode": "vim", "theme": "dark" }\n'
            settings.write_bytes(original)
            settings.chmod(0o644)
            helper = Path(directory)/"helper"
            helper.write_text("fixture")
            result = self.run_setup(settings, helper)
            self.assertEqual(result.returncode, 0, result.stderr)
            backups = list(settings.parent.glob("settings.json.ato-backup-*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), original)
            self.assertEqual(stat.S_IMODE(backups[0].stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(settings.stat().st_mode), 0o600)
            self.assertEqual(json.loads(settings.read_text())["editorMode"], "vim")
            result = self.run_setup(settings, helper)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(list(settings.parent.glob("settings.json.ato-backup-*")), backups)

    def test_custom_settings_skipped_without_changes_or_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = Path(directory)/"settings.json"
            original = b'{"statusLine":{"command":"custom","enabled":false}}\n'
            settings.write_bytes(original)
            result = self.run_setup(settings, Path(directory)/"missing-helper", "--skip-existing")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(settings.read_bytes(), original)
            self.assertEqual(list(settings.parent.glob("settings.json.ato-backup-*")), [])

    def test_invalid_config_and_symlink_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = Path(directory)/"settings.json"
            helper = Path(directory)/"helper"
            helper.write_text("fixture")
            for original in (b"not JSON", b"[]", b"\xff"):
                with self.subTest(original=original):
                    settings.write_bytes(original)
                    result = self.run_setup(settings, helper)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(settings.read_bytes(), original)
            target = Path(directory)/"target.json"
            target.write_text("{}")
            settings.unlink()
            settings.symlink_to(target)
            result = self.run_setup(settings, helper)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(settings.is_symlink())
            self.assertEqual(target.read_text(), "{}")
            self.assertEqual(list(settings.parent.glob("settings.json.ato-backup-*")), [])

    def test_write_failure_preserves_settings_and_cleans_new_files(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = Path(directory)/"settings.json"
            original = b'{"editorMode":"vim"}\n'
            settings.write_bytes(original)
            helper = Path(directory)/"helper"
            helper.write_text("fixture")
            with patch.object(sys, "argv", ["setup", "--settings", str(settings), "--helper", str(helper)]), \
                 patch.object(module.os, "replace", side_effect=PermissionError):
                with self.assertRaisesRegex(SystemExit, "Could not update Antigravity settings"):
                    module.main()
            self.assertEqual(settings.read_bytes(), original)
            self.assertEqual(list(settings.parent.glob(".usage-rings-*")), [])
            self.assertEqual(list(settings.parent.glob("settings.json.ato-backup-*")), [])

    def test_concurrent_change_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = Path(directory)/"settings.json"
            original = b"{}"
            current = b'{"theme":"dark"}'
            settings.write_bytes(current)
            with self.assertRaises(OSError):
                module.write_settings(settings, original, module.configure({}, self.helper))
            self.assertEqual(settings.read_bytes(), current)
            self.assertEqual(list(settings.parent.glob(".usage-rings-*")), [])
            self.assertEqual(list(settings.parent.glob("settings.json.ato-backup-*")), [])

    def test_uninstall_removes_only_owned_statusline_without_installed_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = Path(directory)/"settings.json"
            helper = Path(directory)/"missing-helper"
            original = {"editorMode": "vim"}
            settings.write_text(json.dumps(module.configure(original, helper)))
            result = self.run_setup(settings, helper, "--uninstall")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(settings.read_text()), original)
            self.assertEqual(len(list(settings.parent.glob("settings.json.ato-backup-*"))), 1)


if __name__ == "__main__":
    unittest.main()
