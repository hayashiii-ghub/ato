import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


class InstallTests(unittest.TestCase):
    def assert_failed_install_preserves_existing_app(self, failed_command):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "script"
            scripts.mkdir()
            destination = root / "Applications/Usage Rings.app"
            destination.mkdir(parents=True)
            marker = destination / "installed.txt"
            marker.write_text("existing app")
            source = root / "dist/Usage Rings.app"
            source.mkdir(parents=True)
            (source / "installed.txt").write_text("new app")

            install = Path(__file__).with_name("install.sh").read_text()
            destination_assignment = 'DESTINATION="$HOME/Applications/Usage Rings.app"'
            self.assertEqual(install.count(destination_assignment), 1)
            install = install.replace(destination_assignment, f"DESTINATION={shlex.quote(str(destination))}")
            (scripts / "install.sh").write_text(install)
            self.write_command(scripts / "build.sh", "exit 0")

            commands = root / "bin"
            commands.mkdir()
            stopped = root / "app-stopped"
            widgets_checked = root / "widgets-checked"
            self.write_command(commands / "plutil", "printf 'work.hayashigoto.UsageRings\\n'")
            self.write_command(commands / "pkill", f"touch {shlex.quote(str(stopped))}")
            self.write_command(commands / "pgrep", f"touch {shlex.quote(str(widgets_checked))}")
            self.write_command(commands / "ditto", 'mkdir -p "$2"; cp -R "$1/." "$2/"' +
                               ("; exit 23" if failed_command == "ditto" else ""))
            self.write_command(commands / "codesign", "exit 24" if failed_command == "codesign" else "exit 0")

            result = subprocess.run(
                ["bash", str(scripts / "install.sh")],
                env={**os.environ, "PATH": f"{commands}:{os.environ['PATH']}"},
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 23 if failed_command == "ditto" else 24, result.stderr)
            self.assertEqual(marker.read_text(), "existing app")
            self.assertFalse(stopped.exists())
            self.assertFalse(widgets_checked.exists())
            self.assertEqual(list(destination.parent.glob(".usage-rings-*")), [])

    @staticmethod
    def write_command(path, body):
        path.write_text(f"#!/usr/bin/env bash\nset -euo pipefail\n{body}\n")
        path.chmod(0o755)

    def test_failed_copy_preserves_existing_app(self):
        self.assert_failed_install_preserves_existing_app("ditto")

    def test_failed_signature_check_preserves_existing_app(self):
        self.assert_failed_install_preserves_existing_app("codesign")


if __name__ == "__main__":
    unittest.main()
