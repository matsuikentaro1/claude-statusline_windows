#!/usr/bin/env python
import json, sys, os, subprocess

NO_COLOR = os.environ.get("CC_STATUSLINE_NO_COLOR", "") in ("1", "true", "yes", "on") or \
           os.environ.get("NO_COLOR", "") in ("1", "true", "yes", "on")
USE_ASCII = os.environ.get("CC_STATUSLINE_ASCII", "") in ("1", "true", "yes", "on")
SINGLE_LINE = os.environ.get("CC_STATUSLINE_SINGLE_LINE", "") in ("1", "true", "yes", "on")

def colorize(text, code):
    if NO_COLOR or not text:
        return text
    return f"\033[{code}m{text}\033[0m"

def safe_get(obj, *keys):
    for k in keys:
        if obj is None or not isinstance(obj, dict):
            return None
        obj = obj.get(k)
    return obj

def to_percent(value):
    if value is None:
        return None
    try:
        n = max(0, min(100, round(float(value))))
        return n
    except (ValueError, TypeError):
        return None

def block_meter(pct, filled_code, empty_code):
    if pct is None:
        return colorize("--", empty_code)
    f_sym, e_sym = ("\u2588", "\u2591") if not USE_ASCII else ("#", ".")
    filled = round(pct / 100 * 10)
    filled = max(0, min(10, filled))
    return colorize(f_sym * filled, filled_code) + colorize(e_sym * (10 - filled), empty_code)

def dot_meter(pct, filled_code, empty_code):
    if pct is None:
        return colorize("--", empty_code)
    f_sym, e_sym = ("\u25cf", "\u25cb") if not USE_ASCII else ("#", ".")
    filled = round(pct / 100 * 10)
    filled = max(0, min(10, filled))
    return colorize(f_sym * filled, filled_code) + colorize(e_sym * (10 - filled), empty_code)

def format_reset_at(value, mode):
    if value is None:
        return "--"
    try:
        from datetime import datetime, timezone
        dt = datetime.fromtimestamp(int(value), tz=timezone.utc).astimezone()
        if mode == "current":
            return dt.strftime("%H:%M")
        return dt.strftime("%-m/%d %H:%M").replace("%-m", str(dt.month))
    except (ValueError, TypeError, OSError):
        return "--"

def get_git_info(cwd):
    dir_name = os.path.basename(cwd) if cwd else ""
    repo_name = dir_name
    branch = None
    dirty = False
    try:
        top = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=cwd, stderr=subprocess.DEVNULL, text=True, timeout=3
        ).strip()
        repo_name = os.path.basename(top)
        branch = subprocess.check_output(
            ["git", "symbolic-ref", "--short", "HEAD"],
            cwd=cwd, stderr=subprocess.DEVNULL, text=True, timeout=3
        ).strip()
    except Exception:
        try:
            branch = subprocess.check_output(
                ["git", "rev-parse", "--short", "HEAD"],
                cwd=cwd, stderr=subprocess.DEVNULL, text=True, timeout=3
            ).strip()
        except Exception:
            pass
    try:
        status = subprocess.check_output(
            ["git", "status", "--porcelain", "--untracked-files=normal"],
            cwd=cwd, stderr=subprocess.DEVNULL, text=True, timeout=3
        ).strip()
        dirty = bool(status)
    except Exception:
        pass
    return dir_name, repo_name, branch, dirty

def build_usage_line(label, pct, resets_at, active_color, mode):
    label_text = colorize(label.ljust(7), "38;5;252")
    meter = dot_meter(pct, active_color, "38;5;240")
    pct_text = colorize("--", "38;5;240") if pct is None else colorize(f"{pct:3d}%", active_color)
    reset_text = colorize(format_reset_at(resets_at, mode), "38;5;245")
    return f"{label_text} {meter} {pct_text}  {reset_text}"

try:
    if sys.platform == "win32":
        sys.stdin.reconfigure(encoding="utf-8")
        sys.stdout.reconfigure(encoding="utf-8")

    data = json.load(sys.stdin)

    cwd = safe_get(data, "workspace", "current_dir") or safe_get(data, "cwd") or os.getcwd()

    model = safe_get(data, "model", "display_name") or \
            safe_get(data, "model", "name") or \
            safe_get(data, "model", "id") or "Claude Code"

    dir_name, repo_name, branch, dirty = get_git_info(cwd)
    dir_segment = colorize(dir_name, "38;5;39")
    if branch:
        suffix = "*" if dirty else ""
        git_segment = colorize(repo_name, "38;5;39") + " " + colorize(f"({branch}{suffix})", "38;5;47")
        dir_segment = git_segment if repo_name == dir_name else dir_segment + "  " + git_segment

    context_pct = to_percent(safe_get(data, "context_window", "used_percentage"))
    current_pct = to_percent(safe_get(data, "rate_limits", "five_hour", "used_percentage"))
    current_reset = safe_get(data, "rate_limits", "five_hour", "resets_at")
    weekly_pct = to_percent(safe_get(data, "rate_limits", "seven_day", "used_percentage"))
    weekly_reset = safe_get(data, "rate_limits", "seven_day", "resets_at")

    top_segments = [colorize(model, "38;5;39"), dir_segment]
    top_line = "  |  ".join(s for s in top_segments if s)

    if context_pct is None:
        ctx_color = "38;5;82"
    elif context_pct >= 90:
        ctx_color = "38;5;196"
    elif context_pct >= 80:
        ctx_color = "38;5;208"
    elif context_pct >= 60:
        ctx_color = "38;5;220"
    else:
        ctx_color = "38;5;82"

    ctx_label = colorize("context".ljust(7), "38;5;252")
    ctx_meter = block_meter(context_pct, ctx_color, "38;5;240")
    ctx_pct_text = colorize("--", "38;5;240") if context_pct is None else colorize(f"{context_pct:3d}%", ctx_color)
    context_line = f"{ctx_label} {ctx_meter} {ctx_pct_text}"

    current_line = build_usage_line("current", current_pct, current_reset, "38;5;47", "current")
    weekly_line = build_usage_line("weekly", weekly_pct, weekly_reset, "38;5;220", "weekly")

    if SINGLE_LINE:
        parts = [
            colorize(f"context {context_pct}%" if context_pct is not None else "context --", ctx_color),
            colorize(f"current {current_pct}%" if current_pct is not None else "current --", "38;5;47"),
            colorize(f"weekly {weekly_pct}%" if weekly_pct is not None else "weekly --", "38;5;220"),
        ]
        print("  |  ".join([top_line] + parts))
    else:
        print(top_line)
        print(context_line)
        print(current_line)
        print(weekly_line)

except Exception:
    if os.environ.get("CC_STATUSLINE_DEBUG", "") in ("1", "true", "yes", "on"):
        import traceback
        traceback.print_exc()
    sys.exit(0)
