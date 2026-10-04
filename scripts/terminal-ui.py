#!/usr/bin/env python3
"""Query or change one Windows Terminal profile's line-height ratio from WSL.

Only a set operation changes Terminal settings. Both query and set synchronize
Neovim's local geometry cache. Use --settings/--state for isolated validation.
"""
from __future__ import annotations

import argparse
import contextlib
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile

if os.name == "posix":
    import fcntl
else:
    fcntl = None


MIN_HEIGHT, MAX_HEIGHT = Decimal("1.42"), Decimal("1.65")
DECODER = json.JSONDecoder()


def validate_height(value: str) -> str:
    try:
        number = Decimal(value)
    except InvalidOperation as error:
        raise ValueError("行高必须是 1.42–1.65 之间的数字") from error
    if not number.is_finite() or not MIN_HEIGHT <= number <= MAX_HEIGHT:
        raise ValueError("行高范围为 1.42–1.65")
    if number * 100 != (number * 100).to_integral_value():
        raise ValueError("行高按 0.01 的步长调整，例如 1.42、1.48、1.55、1.60")
    return format(number, ".2f")


def mask_jsonc(text: str) -> str:
    """Mask comments/trailing commas while retaining original character offsets."""
    chars = list(text)
    index, quoted = 0, False
    while index < len(text):
        char = text[index]
        if quoted:
            if char == "\\":
                index += 2
                continue
            if char == '"':
                quoted = False
        elif char == '"':
            quoted = True
        elif text.startswith("//", index):
            end = text.find("\n", index)
            if end < 0:
                end = len(text)
            for pos in range(index, end):
                if text[pos] not in "\r\n":
                    chars[pos] = " "
            index = end
            continue
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            if end < 0:
                raise ValueError("Terminal 设置包含未结束的注释")
            end += 2
            for pos in range(index, end):
                if text[pos] not in "\r\n":
                    chars[pos] = " "
            index = end
            continue
        index += 1
    masked = "".join(chars)
    index, quoted = 0, False
    while index < len(masked):
        char = masked[index]
        if quoted:
            if char == "\\":
                index += 2
                continue
            if char == '"':
                quoted = False
        elif char == '"':
            quoted = True
        elif char == ",":
            next_index = skip_space(masked, index + 1)
            if next_index < len(masked) and masked[next_index] in "}]":
                chars[index] = " "
        index += 1
    return "".join(chars)


def skip_space(text: str, index: int) -> int:
    while index < len(text) and text[index].isspace():
        index += 1
    return index


def members(text: str, start: int):
    index = skip_space(text, start + 1)
    while text[index] != "}":
        name, end = DECODER.raw_decode(text, index)
        index = skip_space(text, end)
        if text[index] != ":":
            raise ValueError("Terminal 设置的对象字段无效")
        value_start = skip_space(text, index + 1)
        value, value_end = DECODER.raw_decode(text, value_start)
        yield name, value_start, value_end, value
        index = skip_space(text, value_end)
        if text[index] == ",":
            index = skip_space(text, index + 1)


def elements(text: str, start: int):
    index = skip_space(text, start + 1)
    while text[index] != "]":
        value, end = DECODER.raw_decode(text, index)
        yield index, end, value
        index = skip_space(text, end)
        if text[index] == ",":
            index = skip_space(text, index + 1)


def profile_spans(masked: str):
    root = skip_space(masked, 0)
    for name, start, _end, value in members(masked, root):
        if name != "profiles":
            continue
        if isinstance(value, list):
            return list(elements(masked, start)), {}
        if not isinstance(value, dict):
            break
        for key, list_start, _list_end, _items in members(masked, start):
            if key == "list":
                defaults = value.get("defaults", {})
                return list(elements(masked, list_start)), defaults if isinstance(defaults, dict) else {}
    raise ValueError("Terminal 设置中没有 profiles.list")


def select_profile(spans, profile_name: str, guid: str | None):
    if guid:
        matches = [s for s in spans if isinstance(s[2], dict) and str(s[2].get("guid", "")).lower() == guid.lower()]
    else:
        matches = [s for s in spans if isinstance(s[2], dict) and s[2].get("name") == profile_name]
    if len(matches) != 1:
        label = guid or profile_name
        raise ValueError(f"需要唯一的 Terminal profile，{label!r} 匹配到 {len(matches)} 项")
    return matches[0]


def default_state_path() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "nvim/workbench-ui.json"


def resolve_settings() -> Path:
    if not (os.environ.get("WSL_DISTRO_NAME") or os.environ.get("WSL_INTEROP")):
        raise ValueError("自动查找 Windows Terminal 设置需要 WSL；POSIX 测试或自定义文件请使用 --settings")
    command = (
        "[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false);"
        "[Environment]::GetFolderPath('LocalApplicationData')"
    )
    try:
        result = subprocess.run(
            ["powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command],
            check=True, capture_output=True, text=True, encoding="utf-8", timeout=20,
        )
        windows_path = result.stdout.strip().lstrip("\ufeff")
        if not re.match(r"^[A-Za-z]:[\\/]", windows_path) or "\n" in windows_path:
            raise ValueError("PowerShell 没有返回有效的 LocalApplicationData 路径")
        converted = subprocess.run(
            ["wslpath", "-u", windows_path], check=True, capture_output=True,
            text=True, encoding="utf-8", timeout=10,
        )
    except (FileNotFoundError, subprocess.SubprocessError) as error:
        raise ValueError("此命令需要在 WSL 中运行，并能调用 powershell.exe 和 wslpath") from error
    local = Path(converted.stdout.strip())
    target = local / "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
    if not target.is_file():
        raise ValueError(f"没有找到 Windows Terminal 设置：{target}")
    return target


def effective_height(profile: dict, defaults: dict):
    font = profile.get("font", {})
    font = font if isinstance(font, dict) else {}
    default_font = defaults.get("font", {})
    default_font = default_font if isinstance(default_font, dict) else {}
    if "cellHeight" in font:
        value, source = font["cellHeight"], "profile"
    elif "cellHeight" in default_font:
        value, source = default_font["cellHeight"], "defaults"
    else:
        value, source = None, "natural"
    if value is None or value == "":
        return 1.32, value, "natural"
    text = str(value).strip()
    match = re.fullmatch(r"([+-]?\d+(?:\.\d+)?)(%|px|pt|ch)?", text)
    if not match:
        return None, value, source
    number = float(match.group(1))
    unit = match.group(2)
    size = float(font.get("size", default_font.get("size", 12)))
    ratio = {
        "%": number / 100,
        "pt": number / size,
        "px": number / (size * 96 / 72),
        "ch": number * 0.6,
    }.get(unit, number)
    return ratio, value, source


def replacement_profile(text: str, start: int, end: int, profile: dict) -> str:
    line_start = text.rfind("\n", 0, start) + 1
    prefix = text[line_start:start]
    indent = re.match(r"[ \t]*", prefix).group()
    sample = re.search(r"\n([ \t]+)\"", text[start:end])
    unit = "    "
    if sample and sample[1].startswith(indent):
        unit = sample[1][len(indent):] or unit
    newline = "\r\n" if "\r\n" in text else "\n"
    serialized = json.dumps(profile, ensure_ascii=False, indent=unit)
    serialized = newline.join(line if index == 0 else indent + line for index, line in enumerate(serialized.splitlines()))
    return text[:start] + serialized + text[end:]


def atomic_write(path: Path, payload: bytes, mode: int | None = None):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        if mode is not None:
            os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def sync_cache(path: Path, result: dict):
    cache = {}
    if path.is_file():
        try:
            old = json.loads(path.read_text(encoding="utf-8-sig"))
            cache = old if isinstance(old, dict) else {}
        except (ValueError, OSError):
            pass
    cache.update({
        "height": result["height"], "cellHeight": result["cellHeight"],
        "profile": result["profile"], "guid": result.get("guid"),
        "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    })
    atomic_write(path, (json.dumps(cache, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))


def run(args):
    if os.name != "posix":
        raise ValueError("此后台仅支持 WSL/POSIX。原生 Windows 请在 Windows Terminal 设置中手动调整行高")
    requested = validate_height(args.set_height) if args.set_height is not None else None
    settings = Path(args.settings).expanduser().resolve() if args.settings else resolve_settings()
    state = Path(args.state).expanduser().resolve() if args.state else default_state_path()
    backups = Path(args.backup_dir).expanduser().resolve() if args.backup_dir else state.parent / "terminal-ui-backups"
    with contextlib.ExitStack() as stack:
        if requested is not None:
            backups.mkdir(parents=True, exist_ok=True)
            lock = stack.enter_context((backups / ".settings.lock").open("a+b"))
            fcntl.flock(lock, fcntl.LOCK_EX)
        original = settings.read_bytes()
        bom = original.startswith(b"\xef\xbb\xbf")
        text = original.decode("utf-8-sig")
        masked = mask_jsonc(text)
        parsed = json.loads(masked)
        if not isinstance(parsed, dict):
            raise ValueError("Terminal 设置必须是 JSON 对象")
        spans, defaults = profile_spans(masked)
        start, end, profile = select_profile(spans, args.profile, args.guid)
        height, configured, source = effective_height(profile, defaults)
        result = {
            "ok": True, "action": "set" if requested is not None else "query",
            "profile": profile.get("name", args.profile), "guid": profile.get("guid"),
            "height": height, "cellHeight": configured, "source": source,
            "settings": str(settings), "state": str(state), "changed": False,
        }
        if requested is not None:
            font = profile.get("font")
            if font is not None and not isinstance(font, dict):
                raise ValueError("目标 profile 的 font 字段不是对象")
            if font is None:
                profile["font"] = {}
            profile["font"]["cellHeight"] = requested
            result.update({"height": float(requested), "cellHeight": requested, "source": "profile"})
            if configured != requested or source != "profile":
                changed = replacement_profile(text, start, end, profile)
                payload = (b"\xef\xbb\xbf" if bom else b"") + changed.encode("utf-8")
                stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
                backup = backups / f"terminal-settings-{stamp}-{os.getpid()}.json"
                shutil.copy2(settings, backup)
                if settings.read_bytes() != original:
                    raise ValueError("Terminal 设置在操作期间被其他程序修改，请重新执行")
                atomic_write(settings, payload, stat.S_IMODE(settings.stat().st_mode))
                result.update({"changed": True, "backup": str(backup)})
        try:
            sync_cache(state, result)
        except OSError as error:
            result["warning"] = f"Terminal 行高已读取或更新，但 Neovim 缓存写入失败：{error}"
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--settings", help="Override settings.json path for isolated validation")
    parser.add_argument("--profile", default="Fedora")
    parser.add_argument("--guid", help="Select one exact profile GUID, even if renamed")
    parser.add_argument("--state", help="Override the workbench-ui.json cache path")
    parser.add_argument("--backup-dir")
    parser.add_argument("--set", dest="set_height", help="Set a ratio between 1.42 and 1.65, in 0.01 steps")
    args = parser.parse_args()
    try:
        result = run(args)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False))
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
