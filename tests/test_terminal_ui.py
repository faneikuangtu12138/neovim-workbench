"""Run: python3 -m unittest discover -s tests -p test_terminal_ui.py"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

script = Path(__file__).resolve().parents[1] / "scripts" / "terminal-ui.py"
spec = importlib.util.spec_from_file_location("terminal_ui", script)
terminal_ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(terminal_ui)


class TerminalUI(unittest.TestCase):
    def test_height_bounds(self):
        self.assertEqual(terminal_ui.validate_height("1.48"), "1.48")
        for invalid in ("1.41", "1.66", "1.481", "NaN"):
            with self.assertRaises(ValueError):
                terminal_ui.validate_height(invalid)

    def test_jsonc(self):
        text = '{ // comment\n "url":"https://example.com", "values":[1,], }'
        self.assertEqual(json.loads(terminal_ui.mask_jsonc(text)),
                         {"url": "https://example.com", "values": [1]})

    def test_duplicate_profiles_require_explicit_guid(self):
        profiles = [(0, 1, {"name": "Fedora", "guid": "one"}),
                    (2, 3, {"name": "Fedora", "guid": "two"})]
        with self.assertRaises(ValueError):
            terminal_ui.select_profile(profiles, "Fedora", None)
        self.assertEqual(terminal_ui.select_profile(profiles, "Fedora", "TWO"), profiles[1])

    def test_isolated_query_and_set(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings, state = root / "settings.json", root / "state.json"
            payload = {"profiles": {"list": [{"name": "Demo", "guid": "demo", "font": {"cellHeight": "1.42"}}]},
                       "unrelated": {"preserve": True}}
            settings.write_text(json.dumps(payload))
            args = argparse.Namespace(settings=str(settings), state=str(state), backup_dir=str(root / "backups"),
                                      profile="Demo", guid=None, set_height=None)
            if os.name != "posix":
                with self.assertRaisesRegex(ValueError, "WSL/POSIX"):
                    terminal_ui.run(args)
                self.assertFalse(state.exists())
                return
            before = settings.read_bytes()
            queried = terminal_ui.run(args)
            self.assertEqual(queried["height"], 1.42)
            self.assertEqual(before, settings.read_bytes())
            args.set_height = "1.55"
            changed = terminal_ui.run(args)
            self.assertTrue(changed["changed"])
            self.assertTrue(Path(changed["backup"]).exists())
            actual = json.loads(settings.read_text())
            self.assertEqual(actual["profiles"]["list"][0]["font"]["cellHeight"], "1.55")
            self.assertEqual(actual["unrelated"], payload["unrelated"])
            self.assertEqual(json.loads(state.read_text())["height"], 1.55)


if __name__ == "__main__":
    unittest.main()
