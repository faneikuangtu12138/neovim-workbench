"""Exercise actual GTK -> terminal -> Neovim key decoding in isolated Xvfb.

Run: xvfb-run -a python tests/gui_keys.py ghostty|kgx /path/report.json
Requires the terminal, xdotool and xwininfo; no user files are edited.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def run(args):
    return subprocess.run(args, text=True, capture_output=True, timeout=10)


def main():
    terminal, destination = sys.argv[1], Path(sys.argv[2])
    result = {
        "terminal": terminal,
        "checks": [],
        "scope": "Actual XTest keys through GTK/X11 and terminal TUI; temporary files; simple input method",
    }
    with tempfile.TemporaryDirectory(prefix="workbench-key-test-") as temporary:
        root = Path(temporary)
        socket, ready = root / "nvim.sock", root / "ready"
        fixture, sample = root / "fixture.lua", root / "sample.v"
        sample.write_text("module sample;\nendmodule\n")
        fixture.write_text(
            "vim.defer_fn(function() vim.cmd.edit(vim.fn.fnameescape("
            + json.dumps(str(sample))
            + ")); vim.fn.writefile({'ready'}, "
            + json.dumps(str(ready))
            + ") end, 600)\n"
        )
        command = ["nvim", "-i", "NONE", "--listen", str(socket), "-S", str(fixture)]
        # Do not connect the isolated X server to the desktop's Fcitx/IBus.
        env = dict(
            os.environ,
            GDK_BACKEND="x11",
            GSK_RENDERER="gl" if terminal == "ghostty" else "cairo",
            GTK_A11Y="none",
            NO_AT_BRIDGE="1",
            GTK_IM_MODULE="simple",
            XMODIFIERS="@im=none",
        )
        if terminal == "ghostty":
            command = ["ghostty", "--gtk-single-instance=false", "--title=Workbench-Key-Test", "-e", *command]
        elif terminal == "kgx":
            command = ["dbus-run-session", "--", "kgx", "--title=Workbench-Key-Test", "--", *command]
        else:
            raise ValueError(terminal)

        def expression(value):
            response = run(["nvim", "--server", str(socket), "--remote-expr", "json_encode(" + value + ")"])
            assert response.returncode == 0, response.stderr
            return json.loads(response.stdout)

        with (root / "app.log").open("w") as log:
            app = subprocess.Popen(command, env=env, stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 10
                while not ready.exists() and time.monotonic() < deadline:
                    assert app.poll() is None, "Terminal quit early"
                    time.sleep(0.1)
                assert ready.exists(), "No Neovim startup"
                identifiers = run(["xdotool", "search", "--name", "^Workbench-Key-Test$"]).stdout.splitlines()
                window = None
                for identifier in identifiers:
                    geometry = run(["xdotool", "getwindowgeometry", "--shell", identifier]).stdout
                    values = dict(line.split("=", 1) for line in geometry.splitlines() if "=" in line)
                    if int(values.get("WIDTH", "0")) > 400:
                        window = identifier
                        break
                assert window, "No test window"
                assert run(["xdotool", "windowfocus", "--sync", window]).returncode == 0
                # Xvfb has no window manager. Click the terminal widget too.
                assert run(["xdotool", "mousemove", "--window", window, "650", "200", "click", "1"]).returncode == 0
                time.sleep(1)
                for iteration in range(6):
                    for key, mode in [("i", "i"), ("Escape", "n"), ("colon", "c"), ("Escape", "n")]:
                        sent = run(["xdotool", "key", "--clearmodifiers", key])
                        assert sent.returncode == 0, sent.stderr
                        time.sleep(0.12)
                        actual = expression("nvim_get_mode()")["mode"]
                        assert actual.startswith(mode), (iteration, key, actual)
                        if mode == "c":
                            assert expression("luaeval('require(\"noice.ui.cmdline\").win() ~= nil')"), "No command popup"
                    result["checks"].append("real keyboard insert/Esc/colon/Esc " + str(iteration + 1))
                result["ok"] = True
            except Exception as error:
                result["ok"], result["error"] = False, str(error)
            finally:
                if socket.exists():
                    run(["nvim", "--server", str(socket), "--remote-expr", 'execute("qa!")'])
                try:
                    app.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    app.terminate()
                    app.wait(timeout=3)
                result["app_log_tail"] = (root / "app.log").read_text()[-1500:]
        destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ["terminal", "ok", "checks"]}))
    if not result["ok"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
