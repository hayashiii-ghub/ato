import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("setup", Path(__file__).with_name("claude-statusline-setup.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class SetupTests(unittest.TestCase):
    helper = Path("/Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline")

    def test_setup_preserves_other_settings_and_is_idempotent(self):
        original = {"hooks": {"example": []}, "permissions": {"allow": ["Read"]}, "model": "opus"}
        installed = module.configure(original, self.helper)
        self.assertEqual(installed["hooks"], original["hooks"])
        self.assertEqual(installed["permissions"], original["permissions"])
        self.assertEqual(module.configure(installed, self.helper), installed)
        self.assertEqual(module.configure(installed, self.helper, uninstall=True), original)
        self.assertNotIn("statusLine", original)

    def test_existing_custom_statusline_is_not_replaced(self):
        existing = {"statusLine": {"type": "command", "command": "my-status-line", "padding": 1}}
        with self.assertRaises(ValueError):
            module.configure(existing, self.helper)
        self.assertEqual(module.configure(existing, self.helper, uninstall=True), existing)

    def test_installer_mode_preserves_custom_statusline_and_other_settings(self):
        existing = {"statusLine": {"type": "command", "command": "my-status-line", "padding": 1}, "model": "opus"}
        self.assertEqual(module.configure(existing, self.helper, skip_existing=True), existing)
        installed = module.configure({"model": "opus"}, self.helper, skip_existing=True)
        self.assertEqual(installed["model"], "opus")
        self.assertEqual(installed["statusLine"]["type"], "command")

    def test_preflight_does_not_require_or_write_an_installed_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config"
            helper = Path(directory) / "Usage Rings.app/Contents/Helpers/UsageRingsStatusline"
            result = subprocess.run(
                [sys.executable, str(Path(__file__).with_name("claude-statusline-setup.py")),
                 "--helper", str(helper), "--skip-existing", "--check"],
                env={**os.environ, "CLAUDE_CONFIG_DIR": str(config)}, capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(config.exists())
            self.assertFalse(helper.exists())

    def test_write_failure_preserves_settings_and_cleans_temporary_file(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            settings = config / "settings.json"
            original = {"model": "opus", "permissions": {"allow": ["Read"]}}
            settings.write_text(json.dumps(original))
            helper = config / "helper"
            helper.write_text("fixture")
            with patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": str(config)}), \
                 patch.object(sys, "argv", ["setup", "--helper", str(helper)]), \
                 patch.object(module.os, "replace", side_effect=PermissionError):
                with self.assertRaisesRegex(SystemExit, "Could not update Claude settings"):
                    module.main()
            self.assertEqual(json.loads(settings.read_text()), original)
            self.assertEqual(list(config.glob(".usage-rings-*")), [])

if __name__ == "__main__":
    unittest.main()
