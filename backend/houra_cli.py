#!/usr/bin/env python3
"""
Houra backend for Omarchy (Python 3 stdlib only).
Maintains 100% SQLite schema and feature compatibility with upstream macOS Houra:
  - ~/.local/share/houra/houra.sqlite (override via HOURA_DB)
  - ~/.config/houra/settings.json     (override via HOURA_CONFIG)
  - ~/.cache/houra/chime.wav          (override via HOURA_CACHE_DIR)
"""

from __future__ import annotations

import calendar
import csv
import datetime as dt
import fnmatch
import json
import locale
import math
import os
import random
import re
import sqlite3
import ssl
import struct
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import wave
from pathlib import Path
from typing import Any

PALETTE = [
    "#e5675c", "#e8894a", "#e6b450", "#dccf6e", "#93c46c",
    "#4fbf95", "#4bb3c9", "#4c8df0", "#6f7cf2", "#9a7bea",
    "#de7ab2", "#c98f73", "#a0a3ad", "#e9e9ee", "#3a3f4d",
]

DEFAULT_SETTINGS: dict[str, Any] = {
    "language": "system",          # "system" | "tr" | "en"
    "widgetStyle": "tag",          # "tag" | "strip" | "capsule" | "card" | "ring" | "none"
    "widgetLeft": False,           # False -> right screen edge
    "tagY": -1.0,                  # -1 -> default 300px / vertically centered
    "positions": {
        "capsule": [-1, -1],
        "card": [-1, -1],
        "ring": [-1, -1],
    },
    "lastTopic": 0,
    "rhythmMode": "50",            # "25" | "50" | "custom" | "free"
    "rhythmWork": 50,              # 25 | 50 | customWork | 0 (Free)
    "customWork": 45,              # user-customizable focus duration (1..240 min)
    "customRest": 10,              # user-customizable break duration (1..90 min)
    "weeklyOn": True,
    "weeklyTemplate": "",
    "todoistOn": False,
    "todoistFilter": "today | overdue",
    "themeMode": "omarchy",        # "omarchy" | "classic"
    "focusDnd": False,
    "widgetScreen": "",            # pinned monitor name ("HDMI-A-1", "eDP-1", ...), "" -> first monitor
}


def resolve_lang(pref: str) -> str:
    override = os.environ.get("HOURA_LANG", "").strip().lower()
    if override.startswith("tr"):
        return "tr"
    if override.startswith("en"):
        return "en"
    if pref in ("tr", "en"):
        return pref
    env_lang = (
        os.environ.get("LC_ALL")
        or os.environ.get("LC_MESSAGES")
        or os.environ.get("LANG")
        or ""
    ).lower()
    if env_lang.startswith("tr"):
        return "tr"
    try:
        loc = (locale.getlocale()[0] or "").lower()
        if loc.startswith("tr"):
            return "tr"
    except Exception:
        pass
    return "en"


def tr_en(lang: str, tr_text: str, en_text: str) -> str:
    return tr_text if lang == "tr" else en_text


def _rhythm_label(work_min: int, rest_min: int, lang: str) -> str:
    if work_min <= 0:
        return tr_en(lang, "serbest", "free")
    return f"{work_min} + {rest_min}"


def db_path() -> Path:
    override = os.environ.get("HOURA_DB", "").strip()
    if override:
        p = Path(override).expanduser()
        p.parent.mkdir(parents=True, exist_ok=True)
        return p
    xdg_data = os.environ.get("XDG_DATA_HOME", "").strip()
    base = Path(xdg_data).expanduser() if xdg_data else (Path.home() / ".local" / "share")
    folder = base / "houra"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / "houra.sqlite"


def config_path() -> Path:
    override = os.environ.get("HOURA_CONFIG", "").strip()
    if override:
        p = Path(override).expanduser()
        p.parent.mkdir(parents=True, exist_ok=True)
        return p
    xdg_cfg = os.environ.get("XDG_CONFIG_HOME", "").strip()
    base = Path(xdg_cfg).expanduser() if xdg_cfg else (Path.home() / ".config")
    folder = base / "houra"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / "settings.json"


def cache_dir() -> Path:
    override = os.environ.get("HOURA_CACHE_DIR", "").strip()
    if override:
        p = Path(override).expanduser()
        p.mkdir(parents=True, exist_ok=True)
        return p
    xdg_cache = os.environ.get("XDG_CACHE_HOME", "").strip()
    base = Path(xdg_cache).expanduser() if xdg_cache else (Path.home() / ".cache")
    folder = base / "houra"
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def state_dir() -> Path:
    override = os.environ.get("HOURA_STATE_DIR", "").strip()
    if override:
        p = Path(override).expanduser()
    else:
        xdg_state = os.environ.get("XDG_STATE_HOME", "").strip()
        base = Path(xdg_state).expanduser() if xdg_state else (Path.home() / ".local" / "state")
        p = base / "houra"
    p.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(p, 0o700)
    except OSError:
        pass
    return p


def _write_private_file(target: Path, text: str) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(target.suffix + ".tmp")
    fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
    except Exception:
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass
        raise
    os.chmod(tmp, 0o600)
    tmp.replace(target)
    os.chmod(target, 0o600)


def load_settings() -> dict[str, Any]:
    cfg = dict(DEFAULT_SETTINGS)
    cfg["positions"] = {k: list(v) for k, v in DEFAULT_SETTINGS["positions"].items()}
    p = config_path()
    if p.is_file():
        try:
            raw = json.loads(p.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                for k, v in raw.items():
                    if k == "positions" and isinstance(v, dict):
                        for pk, pv in v.items():
                            if isinstance(pv, (list, tuple)) and len(pv) == 2:
                                cfg["positions"][pk] = [float(pv[0]), float(pv[1])]
                    elif k in cfg:
                        cfg[k] = v
        except Exception:
            pass
    return cfg


def save_settings(patch: dict[str, Any]) -> dict[str, Any]:
    cfg = load_settings()
    for k, v in patch.items():
        if k == "positions" and isinstance(v, dict):
            for pk, pv in v.items():
                if isinstance(pv, (list, tuple)) and len(pv) == 2:
                    cfg["positions"][pk] = [float(pv[0]), float(pv[1])]
        elif k in cfg:
            cfg[k] = v
    p = config_path()
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(p)
    return cfg


def open_db(lang: str = "en") -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path()))
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            emoji TEXT,
            icon TEXT,
            position INTEGER NOT NULL DEFAULT 0,
            icon_color TEXT
        );
        CREATE TABLE IF NOT EXISTS todos (
            id INTEGER PRIMARY KEY,
            day TEXT NOT NULL,
            title TEXT NOT NULL,
            detail TEXT NOT NULL DEFAULT '',
            state INTEGER NOT NULL DEFAULT 0,
            session_id INTEGER,
            position INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS todos_day ON todos(day);
        CREATE TABLE IF NOT EXISTS sessions (
            id INTEGER PRIMARY KEY,
            category_id INTEGER NOT NULL,
            goal TEXT NOT NULL,
            work_min INTEGER NOT NULL,
            rest_min INTEGER NOT NULL,
            start REAL NOT NULL,
            end REAL,
            focus_sec INTEGER NOT NULL DEFAULT 0,
            note TEXT NOT NULL DEFAULT '',
            emergency INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS sessions_start ON sessions(start);
        """
    )
    cols = {r["name"] for r in conn.execute("PRAGMA table_info(categories)").fetchall()}
    if "icon_color" not in cols:
        conn.execute("ALTER TABLE categories ADD COLUMN icon_color TEXT")

    todo_cols = {r["name"] for r in conn.execute("PRAGMA table_info(todos)").fetchall()}
    todo_migrations = [
        ("priority", "INTEGER NOT NULL DEFAULT 1"),
        ("scope", "TEXT NOT NULL DEFAULT 'day'"),
        ("end_day", "TEXT NOT NULL DEFAULT ''"),
        ("due_time", "TEXT NOT NULL DEFAULT ''"),
        ("recurrence", "TEXT NOT NULL DEFAULT ''"),
        ("category_id", "INTEGER NOT NULL DEFAULT 0"),
        ("spawned_next_id", "INTEGER NOT NULL DEFAULT 0"),
    ]
    for col_name, col_def in todo_migrations:
        if col_name not in todo_cols:
            conn.execute(f"ALTER TABLE todos ADD COLUMN {col_name} {col_def}")
    conn.execute("CREATE INDEX IF NOT EXISTS todos_scope_day ON todos(scope, day, end_day)")

    cnt = conn.execute("SELECT COUNT(*) AS c FROM categories").fetchone()["c"]
    if cnt == 0:
        default_name = tr_en(lang, "Genel", "General")
        conn.execute(
            "INSERT INTO categories (name, color, emoji, icon, position, icon_color) VALUES (?, ?, NULL, NULL, 1, NULL)",
            (default_name, "#4c8df0"),
        )
        conn.commit()
    return conn


def close_abandoned(conn: sqlite3.Connection, active_session_id: int | None = None) -> int:
    now_ts = time.time()
    cutoff = now_ts - 3 * 86400
    rows = conn.execute(
        "SELECT id, start, work_min, focus_sec FROM sessions WHERE end IS NULL AND start >= ?",
        (cutoff,),
    ).fetchall()
    closed = 0
    for r in rows:
        if active_session_id is not None and int(r["id"]) == int(active_session_id):
            continue
        wmin = int(r["work_min"])
        fsec = int(r["focus_sec"])
        s_ts = float(r["start"])
        # Do not prematurely close a session that is still within its live window
        # (unless it was started in the past beyond its planned duration / free-mode heartbeat).
        if wmin > 0 and 0 <= (now_ts - s_ts) < wmin * 60:
            continue
        if wmin == 0 and 0 <= (now_ts - (s_ts + fsec)) < 180:
            continue
        planned = wmin * 60 if wmin > 0 else fsec
        end_ts = s_ts + max(0, planned)
        conn.execute(
            "UPDATE sessions SET end = ?, focus_sec = ? WHERE id = ?",
            (end_ts, max(0, planned), int(r["id"])),
        )
        closed += 1
    if closed:
        conn.commit()
    return closed


# ---------------------------------------------------------------------------
# Audio Chime (exact synthesis from Chime.swift: E5 659Hz + B5 988Hz)
# ---------------------------------------------------------------------------

def ensure_chime() -> Path:
    wav_path = cache_dir() / "chime.wav"
    if wav_path.is_file() and wav_path.stat().st_size > 1024:
        return wav_path

    rate = 44100
    duration = 4.0
    frames = int(rate * duration)
    bells = [
        (659.0, 0.16, 0.0),   # E5
        (988.0, 0.12, 0.45),  # B5
    ]
    buf = bytearray(frames * 2)
    two_pi = 2.0 * math.pi
    for i in range(frames):
        t = i / rate
        sample = 0.0
        for freq, amp, delay in bells:
            if t >= delay:
                local = t - delay
                attack = min(1.0, local / 0.03)
                decay = math.exp(-local / 0.7)
                sample += math.sin(two_pi * freq * local) * amp * attack * decay
        if duration - t < 0.3:
            sample *= max(0.0, (duration - t) / 0.3)
        clamped = max(-0.95, min(0.95, sample))
        pcm = int(round(clamped * 32767.0))
        struct.pack_into("<h", buf, i * 2, pcm)

    tmp = wav_path.with_suffix(".tmp.wav")
    with wave.open(str(tmp), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(bytes(buf))
    tmp.replace(wav_path)
    return wav_path


# ---------------------------------------------------------------------------
# Weekly Markdown Parser (exact parity with Weekly.swift)
# ---------------------------------------------------------------------------

def _tr_lower(s: str) -> str:
    return s.replace("İ", "i").replace("I", "ı").lower()


def _norm_topic(s: str) -> str:
    cleaned = "".join(ch for ch in _tr_lower(s.strip()) if ch.isalnum())
    if len(cleaned) > 3 and cleaned.endswith("s"):
        cleaned = cleaned[:-1]
    return cleaned


def resolve_weekly_path(template: str, ref_date: dt.date | None = None) -> Path | None:
    tmpl = (template or "").strip()
    if not tmpl:
        return None
    d = ref_date or dt.date.today()
    iso_year, iso_week, _ = d.isocalendar()

    expanded = tmpl
    if expanded.startswith("~"):
        expanded = str(Path.home()) + expanded[1:]

    expanded = (
        expanded.replace("{YYYY}", f"{iso_year:04d}")
        .replace("{WW}", f"{iso_week:02d}")
        .replace("{W}", f"{iso_week}")
        .replace("{MM}", f"{d.month:02d}")
    )

    return _expand_wildcards(expanded)


def _safe_mtime(p: Path) -> float:
    try:
        return p.stat().st_mtime
    except OSError:
        return 0.0


def _expand_wildcards(pattern_path: str) -> Path | None:
    is_abs = pattern_path.startswith("/")
    parts = [p for p in pattern_path.split("/") if p]
    roots = [Path("/")] if is_abs else [Path(".")]

    for idx, comp in enumerate(parts):
        is_last = idx == len(parts) - 1
        next_roots: list[Path] = []
        if "*" in comp or "?" in comp:
            for base in roots:
                if not base.is_dir():
                    continue
                try:
                    entries = sorted(base.iterdir(), key=lambda p: (-_safe_mtime(p), p.name.lower()))
                except OSError:
                    continue
                for entry in entries:
                    if fnmatch.fnmatchcase(entry.name, comp):
                        if is_last or entry.is_dir():
                            next_roots.append(entry)
        else:
            for base in roots:
                cand = base / comp
                if cand.exists():
                    next_roots.append(cand)
        roots = next_roots
        if not roots:
            return None
    files = [r for r in roots if r.is_file()]
    if not files:
        return None
    files.sort(key=lambda p: (-_safe_mtime(p), p.name.lower()))
    return files[0]


_HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
_TASK_RE = re.compile(r"^(\s*)[-*+]\s+\[([ /wWxX])\]\s+(.+?)\s*$")
_BULLET_RE = re.compile(r"^(\s*)[-*+]\s+(.+?)\s*$")
_WIKILINK_RE = re.compile(r"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]")
_TAG_RE = re.compile(r"(?:^|\s)#([\w\-/çğıöşüÇĞİÖŞÜ]+)")
_ARROW_TAIL_RE = re.compile(r"\s+(?:→|->)\s+.*$")
_DONE_TAIL_RE = re.compile(r"\s*✅.*$")


def _clean_task_title(raw: str) -> tuple[str, list[str]]:
    tags = _TAG_RE.findall(raw)
    text = _WIKILINK_RE.sub(lambda m: m.group(2) if m.group(2) else m.group(1), raw)
    text = _ARROW_TAIL_RE.sub("", text)
    text = _DONE_TAIL_RE.sub("", text)
    text = _TAG_RE.sub(" ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text, tags


def load_weekly_tasks(
    settings: dict[str, Any],
    categories: list[dict[str, Any]],
    ref_date: dt.date | None = None,
    lang: str = "en",
) -> dict[str, Any]:
    tmpl = str(settings.get("weeklyTemplate") or "").strip()
    enabled = bool(settings.get("weeklyOn"))
    if not enabled or not tmpl:
        return {
            "enabled": enabled,
            "templateSet": bool(tmpl),
            "resolvedPath": "",
            "fileName": "",
            "rawFileName": "",
            "exists": False,
            "openCount": 0,
            "tasks": [],
            "groups": [],
        }

    resolved = resolve_weekly_path(tmpl, ref_date=ref_date)
    if resolved is None or not resolved.is_file():
        return {
            "enabled": enabled,
            "templateSet": True,
            "resolvedPath": "",
            "fileName": "",
            "rawFileName": "",
            "exists": False,
            "openCount": 0,
            "tasks": [],
            "groups": [],
        }

    cat_by_norm: dict[str, dict[str, Any]] = {}
    for c in categories:
        n = _norm_topic(c["name"])
        if n and n not in cat_by_norm:
            cat_by_norm[n] = c

    try:
        lines = resolved.read_text(encoding="utf-8").splitlines()
    except Exception:
        lines = []

    current_group = ""
    current_subgroup = ""
    tasks: list[dict[str, Any]] = []

    for line_no, line in enumerate(lines, start=1):
        hm = _HEADING_RE.match(line)
        if hm:
            raw_h = hm.group(2).strip()
            clean_h, _ = _clean_task_title(raw_h)
            current_group = clean_h or raw_h
            current_subgroup = ""
            continue

        tm = _TASK_RE.match(line)
        if tm:
            indent_raw, marker, body = tm.group(1), tm.group(2), tm.group(3)
            indent_spaces = len(indent_raw.replace("\t", "    "))
            depth = indent_spaces // 2
            title, tags = _clean_task_title(body)

            if indent_spaces < 2:
                current_subgroup = title

            if marker in ("x", "X"):
                continue
            if "→ Hafta" in body or "-> Hafta" in body:
                continue
            if not title:
                continue

            sub = current_subgroup if indent_spaces >= 2 else ""

            matched_cat = None
            candidates = ([current_group] if current_group else []) + list(tags)
            for cand_name in candidates:
                nt = _norm_topic(cand_name)
                if nt and nt in cat_by_norm:
                    matched_cat = cat_by_norm[nt]
                    break

            tasks.append(
                {
                    "key": f"w:{line_no}",
                    "line": line_no,
                    "title": title,
                    "group": current_group,
                    "subgroup": sub,
                    "depth": depth,
                    "startsSubgroup": False,
                    "waiting": marker in ("w", "W"),
                    "inProgress": marker == "/",
                    "categoryId": matched_cat["id"] if matched_cat else 0,
                    "categoryName": matched_cat["name"] if matched_cat else "",
                    "categoryColor": matched_cat["color"] if matched_cat else "",
                }
            )
            continue

        bm = _BULLET_RE.match(line)
        if bm:
            indent_spaces = len(bm.group(1).replace("\t", "    "))
            if indent_spaces < 2:
                clean_b, _ = _clean_task_title(bm.group(2))
                current_subgroup = clean_b
        elif not line.strip():
            current_subgroup = ""

    fallback_group = tr_en(lang, "Diğer", "Other")
    groups_map: dict[str, dict[str, Any]] = {}
    groups_order: list[str] = []
    last_sub_by_group: dict[str, str] = {}
    for t in tasks:
        gname = t["group"] or fallback_group
        if gname not in groups_map:
            matched_cat = cat_by_norm.get(_norm_topic(gname))
            groups_map[gname] = {
                "name": gname,
                "categoryId": matched_cat["id"] if matched_cat else (t["categoryId"] or 0),
                "categoryColor": matched_cat["color"] if matched_cat else (t["categoryColor"] or ""),
                "categoryEmoji": matched_cat["emoji"] if matched_cat else "",
                "categoryIcon": matched_cat["icon"] if matched_cat else "",
                "categoryIconColor": matched_cat["iconColor"] if matched_cat else "",
                "tasks": [],
            }
            groups_order.append(gname)
            last_sub_by_group[gname] = ""
        sub_val = t["subgroup"] or ""
        if sub_val and sub_val != last_sub_by_group[gname]:
            t["startsSubgroup"] = True
        last_sub_by_group[gname] = sub_val
        groups_map[gname]["tasks"].append(t)

    return {
        "enabled": enabled,
        "templateSet": True,
        "resolvedPath": str(resolved),
        "fileName": resolved.stem,
        "rawFileName": resolved.name,
        "exists": True,
        "openCount": len(tasks),
        "tasks": tasks,
        "groups": [groups_map[g] for g in groups_order],
    }


# ---------------------------------------------------------------------------
# Todoist Unified API v1 Integration (Optional, Offline-First, 2-Way Close)
# ---------------------------------------------------------------------------

TODOIST_CACHE_TTL_SEC = 90.0
TODOIST_PROJECTS_TTL_SEC = 600.0


def todoist_api_base() -> str:
    override = os.environ.get("HOURA_TODOIST_API_BASE", "").strip()
    return (override or "https://api.todoist.com/api/v1").rstrip("/")


def todoist_token_path() -> Path:
    override = os.environ.get("HOURA_TODOIST_TOKEN_FILE", "").strip()
    if override:
        return Path(override).expanduser()
    return state_dir() / "todoist_token"


def todoist_links_path() -> Path:
    return state_dir() / "todoist_links.json"


def todoist_cache_path() -> Path:
    return cache_dir() / "todoist_cache.json"


def load_todoist_token() -> str:
    p = todoist_token_path()
    if not p.is_file():
        return ""
    try:
        return p.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def save_todoist_token_file(token: str) -> None:
    val = (token or "").strip()
    p = todoist_token_path()
    if not val:
        p.unlink(missing_ok=True)
        return
    _write_private_file(p, val + "\n")


def load_todoist_link_meta() -> dict[str, dict[str, Any]]:
    p = todoist_links_path()
    if not p.is_file():
        return {}
    try:
        raw = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {}
    if not isinstance(raw, dict):
        return {}
    cutoff = time.time() - 45 * 86400
    out: dict[str, dict[str, Any]] = {}
    for k, v in raw.items():
        if isinstance(v, dict):
            tid = str(v.get("id") or "").strip()
            ts = float(v.get("ts") or 0)
            if tid and (ts <= 0 or ts >= cutoff):
                out[str(k)] = {"id": tid, "done": bool(v.get("done", False)), "ts": ts}
        elif isinstance(v, str) and v.strip():
            out[str(k)] = {"id": v.strip(), "done": False, "ts": 0.0}
    return out


def load_todoist_links() -> dict[str, str]:
    return {k: v["id"] for k, v in load_todoist_link_meta().items()}


def set_todoist_link(local_todo_id: int, todoist_id: str, done: bool | None = None) -> None:
    td_id = str(todoist_id or "").strip()
    if not td_id or local_todo_id <= 0:
        return
    p = todoist_links_path()
    raw: dict[str, Any] = {}
    if p.is_file():
        try:
            loaded = json.loads(p.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                raw = loaded
        except Exception:
            raw = {}
    cutoff = time.time() - 45 * 86400
    cleaned: dict[str, Any] = {}
    for k, v in raw.items():
        if isinstance(v, dict):
            if float(v.get("ts") or 0) >= cutoff and str(v.get("id") or "").strip():
                cleaned[str(k)] = {
                    "id": str(v.get("id")).strip(),
                    "done": bool(v.get("done", False)),
                    "ts": float(v.get("ts") or time.time()),
                }
        elif isinstance(v, str) and v.strip():
            cleaned[str(k)] = {"id": v.strip(), "done": False, "ts": time.time()}
    prev_done = bool(cleaned.get(str(local_todo_id), {}).get("done", False))
    final_done = prev_done if done is None else bool(done)
    cleaned[str(local_todo_id)] = {"id": td_id, "done": final_done, "ts": time.time()}
    _write_private_file(p, json.dumps(cleaned, ensure_ascii=False))


def set_todoist_done_by_remote_id(todoist_id: str, done: bool) -> list[int]:
    td_id = str(todoist_id or "").strip()
    if not td_id:
        return []
    p = todoist_links_path()
    if not p.is_file():
        return []
    try:
        raw = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return []
    if not isinstance(raw, dict):
        return []
    matched_local_ids: list[int] = []
    changed = False
    for k, v in list(raw.items()):
        entry_id = ""
        if isinstance(v, dict):
            entry_id = str(v.get("id") or "").strip()
        elif isinstance(v, str):
            entry_id = v.strip()
        if entry_id == td_id:
            raw[str(k)] = {"id": td_id, "done": bool(done), "ts": time.time()}
            changed = True
            try:
                matched_local_ids.append(int(k))
            except ValueError:
                pass
    if changed:
        _write_private_file(p, json.dumps(raw, ensure_ascii=False))
    return matched_local_ids


VALID_SCOPES = ("day", "week", "month", "range", "inbox")
VALID_RECURRENCES = ("", "daily", "weekday", "weekly", "monthly")

_MONTHS_SHORT_TR = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]
_MONTHS_SHORT_EN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
_MONTHS_FULL_TR = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
_MONTHS_FULL_EN = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
_WEEKDAYS_EN = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def _safe_parse_day(raw: Any) -> dt.date | None:
    s = str(raw or "").strip()
    if len(s) >= 10:
        s = s[:10]
    if not s:
        return None
    try:
        return dt.date.fromisoformat(s)
    except ValueError:
        return None


def _clamp_priority(raw: Any) -> int:
    try:
        v = int(raw)
    except (TypeError, ValueError):
        return 1
    return max(1, min(4, v))


def _normalize_due_time(raw: Any) -> str:
    s = str(raw or "").strip()
    if not s:
        return ""
    m = re.match(r"^([01]?\d|2[0-3]):([0-5]\d)$", s)
    if not m:
        return ""
    return f"{int(m.group(1)):02d}:{int(m.group(2)):02d}"


def _normalize_recurrence(raw: Any) -> str:
    s = str(raw or "").strip().lower()
    return s if s in VALID_RECURRENCES else ""


def _extract_task_shorthands(raw_title: str) -> tuple[str, int | None, str]:
    text = (raw_title or "").strip()
    if not text:
        return "", None, ""

    extracted_prio: int | None = None
    extracted_time = ""

    def _prio_repl(m: re.Match[str]) -> str:
        nonlocal extracted_prio
        p_num = int(m.group(1) or m.group(2))
        # Todoist convention: p1 -> 4 (highest), p2 -> 3, p3 -> 2, p4 -> 1
        extracted_prio = 5 - p_num
        return " "

    cleaned = re.sub(r"(?i)(?:^|\s)(?:p([1-4])|!!([1-4]))(?=\s|$)", _prio_repl, text)

    def _at_time_repl(m: re.Match[str]) -> str:
        nonlocal extracted_time
        extracted_time = f"{int(m.group(1)):02d}:{int(m.group(2)):02d}"
        return " "

    cleaned = re.sub(r"(?:^|\s)@([01]?\d|2[0-3]):([0-5]\d)(?=\s|$)", _at_time_repl, cleaned)
    if not extracted_time:
        m_tail = re.search(r"\s+([01]\d|2[0-3]):([0-5]\d)\s*$", cleaned)
        if m_tail:
            extracted_time = f"{int(m_tail.group(1)):02d}:{int(m_tail.group(2)):02d}"
            cleaned = cleaned[: m_tail.start()]

    cleaned = re.sub(r"\s{2,}", " ", cleaned).strip()
    return (cleaned or text), extracted_prio, extracted_time


def _normalize_schedule(
    scope_raw: Any,
    day_raw: Any,
    end_day_raw: Any = "",
    due_time_raw: Any = "",
    recurrence_raw: Any = "",
    ref_date: dt.date | None = None,
) -> tuple[str, str, str, str, str]:
    ref = ref_date or dt.date.today()
    scope = str(scope_raw or "day").strip().lower()
    if scope not in VALID_SCOPES:
        scope = "day"
    due_time = _normalize_due_time(due_time_raw)
    recurrence = _normalize_recurrence(recurrence_raw)

    if scope == "inbox":
        base_d = _safe_parse_day(day_raw) or ref
        return "inbox", base_d.isoformat(), "", "", ""

    if scope == "week":
        d = _safe_parse_day(day_raw) or ref
        mon = d - dt.timedelta(days=d.isoweekday() - 1)
        sun = mon + dt.timedelta(days=6)
        return "week", mon.isoformat(), sun.isoformat(), due_time, recurrence

    if scope == "month":
        d = _safe_parse_day(day_raw) or ref
        first = dt.date(d.year, d.month, 1)
        last = dt.date(d.year, d.month, calendar.monthrange(d.year, d.month)[1])
        return "month", first.isoformat(), last.isoformat(), due_time, recurrence

    if scope == "range":
        d1 = _safe_parse_day(day_raw) or ref
        d2 = _safe_parse_day(end_day_raw) or d1
        if d2 < d1:
            d1, d2 = d2, d1
        if d1 == d2:
            return "day", d1.isoformat(), "", due_time, recurrence
        return "range", d1.isoformat(), d2.isoformat(), due_time, recurrence

    d = _safe_parse_day(day_raw) or ref
    return "day", d.isoformat(), "", due_time, recurrence


def _advance_recurring_schedule(
    scope: str,
    day_iso: str,
    end_day_iso: str,
    recurrence: str,
    ref_date: dt.date | None = None,
) -> tuple[str, str, str]:
    ref = ref_date or dt.date.today()
    rec = _normalize_recurrence(recurrence)
    d_start = _safe_parse_day(day_iso) or ref
    d_end = _safe_parse_day(end_day_iso) or d_start
    span_days = max(0, (d_end - d_start).days)

    if scope == "week":
        cur_mon = ref - dt.timedelta(days=ref.isoweekday() - 1)
        base_mon = max(d_start, cur_mon)
        if rec == "monthly":
            ny = base_mon.year + (1 if base_mon.month == 12 else 0)
            nm = 1 if base_mon.month == 12 else (base_mon.month + 1)
            cand = dt.date(ny, nm, min(base_mon.day, calendar.monthrange(ny, nm)[1]))
            n_mon = cand - dt.timedelta(days=cand.isoweekday() - 1)
        else:
            n_mon = base_mon + dt.timedelta(days=7)
        return "week", n_mon.isoformat(), (n_mon + dt.timedelta(days=6)).isoformat()

    if scope == "month":
        cur_first = dt.date(ref.year, ref.month, 1)
        base_m = max(dt.date(d_start.year, d_start.month, 1), cur_first)
        ny = base_m.year + (1 if base_m.month == 12 else 0)
        nm = 1 if base_m.month == 12 else (base_m.month + 1)
        first = dt.date(ny, nm, 1)
        last = dt.date(ny, nm, calendar.monthrange(ny, nm)[1])
        return "month", first.isoformat(), last.isoformat()

    base = max(d_start, ref)
    if rec == "daily":
        next_d = base + dt.timedelta(days=1)
    elif rec == "weekday":
        next_d = base + dt.timedelta(days=1)
        while next_d.isoweekday() > 5:
            next_d += dt.timedelta(days=1)
    elif rec == "weekly":
        next_d = base + dt.timedelta(days=7)
    elif rec == "monthly":
        ny = base.year + (1 if base.month == 12 else 0)
        nm = 1 if base.month == 12 else (base.month + 1)
        target_dom = min(d_start.day, calendar.monthrange(ny, nm)[1])
        next_d = dt.date(ny, nm, target_dom)
    else:
        next_d = base + dt.timedelta(days=1)

    if scope == "range" and span_days > 0:
        return "range", next_d.isoformat(), (next_d + dt.timedelta(days=span_days)).isoformat()
    return "day", next_d.isoformat(), ""


def _fmt_short_day(d: dt.date, lang: str, ref_year: int) -> str:
    if lang == "tr":
        base = f"{d.day} {_MONTHS_SHORT_TR[d.month - 1]}"
    else:
        base = f"{_MONTHS_SHORT_EN[d.month - 1]} {d.day}"
    return f"{base} {d.year}" if d.year != ref_year else base


def _format_recurrence_label(recurrence: str, lang: str) -> str:
    rec = _normalize_recurrence(recurrence)
    if rec == "daily":
        return tr_en(lang, "Her gün", "Daily")
    if rec == "weekday":
        return tr_en(lang, "Hafta içi", "Weekdays")
    if rec == "weekly":
        return tr_en(lang, "Haftalık", "Weekly")
    if rec == "monthly":
        return tr_en(lang, "Aylık", "Monthly")
    return ""


def _format_todo_due_label(
    scope: str,
    day_iso: str,
    end_day_iso: str,
    lang: str,
    ref_date: dt.date,
) -> str:
    if scope == "inbox":
        return ""
    d_start = _safe_parse_day(day_iso)
    if d_start is None:
        return ""
    d_end = _safe_parse_day(end_day_iso) or d_start
    cur_week_mon = ref_date - dt.timedelta(days=ref_date.isoweekday() - 1)
    next_week_mon = cur_week_mon + dt.timedelta(days=7)

    if scope == "day":
        if d_start == ref_date:
            return tr_en(lang, "Bugün", "Today")
        if d_start == ref_date + dt.timedelta(days=1):
            return tr_en(lang, "Yarın", "Tomorrow")
        if d_start == ref_date - dt.timedelta(days=1):
            return tr_en(lang, "Dün", "Yesterday")
        return _fmt_short_day(d_start, lang, ref_date.year)

    if scope == "week":
        w_mon = d_start - dt.timedelta(days=d_start.isoweekday() - 1)
        w_sun = w_mon + dt.timedelta(days=6)
        if w_mon == cur_week_mon:
            return tr_en(lang, "Bu hafta", "This week")
        if w_mon == next_week_mon:
            return tr_en(lang, "Gelecek hafta", "Next week")
        iso_w = w_mon.isocalendar()[1]
        rng = f"{_fmt_short_day(w_mon, lang, ref_date.year)}–{_fmt_short_day(w_sun, lang, ref_date.year)}"
        return tr_en(lang, f"H{iso_w} · {rng}", f"W{iso_w} · {rng}")

    if scope == "month":
        if d_start.year == ref_date.year and d_start.month == ref_date.month:
            return tr_en(lang, "Bu ay", "This month")
        m_name = (_MONTHS_FULL_TR if lang == "tr" else _MONTHS_FULL_EN)[d_start.month - 1]
        return f"{m_name} {d_start.year}" if d_start.year != ref_date.year else m_name

    # scope == "range"
    if d_start == d_end:
        return _fmt_short_day(d_start, lang, ref_date.year)
    return f"{_fmt_short_day(d_start, lang, ref_date.year)} – {_fmt_short_day(d_end, lang, ref_date.year)}"


def _serialize_todo_row(
    r: sqlite3.Row,
    link_meta: dict[str, dict[str, Any]],
    open_td_ids: set[str] | None = None,
    sid_override: int | None = None,
    cat_map: dict[int, dict[str, Any]] | None = None,
    lang: str = "en",
    ref_date: dt.date | None = None,
    now_hm: str = "",
) -> dict[str, Any]:
    keys = set(r.keys())
    tid_int = int(r["id"])
    meta = link_meta.get(str(tid_int), {})
    td_id = str(meta.get("id") or "")
    td_done = bool(meta.get("done", False))
    if td_id and open_td_ids is not None and td_id in open_td_ids:
        td_done = False
    sid_val = (
        int(sid_override)
        if sid_override is not None
        else (int(r["session_id"]) if ("session_id" in keys and r["session_id"] is not None) else 0)
    )
    today_d = ref_date or dt.date.today()
    today_iso = today_d.isoformat()
    cur_hm = now_hm or dt.datetime.now().strftime("%H:%M")

    raw_day = str(r["day"] or "") if "day" in keys else ""
    raw_scope = str(r["scope"] or "day") if "scope" in keys else "day"
    if raw_scope not in VALID_SCOPES:
        raw_scope = "day"
    raw_end_day = str(r["end_day"] or "") if "end_day" in keys else ""
    due_time = _normalize_due_time(r["due_time"]) if "due_time" in keys else ""
    recurrence = _normalize_recurrence(r["recurrence"]) if "recurrence" in keys else ""
    priority = _clamp_priority(r["priority"]) if "priority" in keys else 1
    cat_id = int(r["category_id"] or 0) if "category_id" in keys else 0
    pos_val = int(r["position"] or 0) if "position" in keys else 0
    st_val = int(r["state"])

    eff_end = ""
    if raw_scope == "day":
        eff_end = raw_day
    elif raw_scope in ("week", "month", "range"):
        eff_end = raw_end_day or raw_day

    is_open = st_val != 2
    is_past_due = bool(is_open and raw_scope != "inbox" and eff_end and eff_end < today_iso)
    is_time_overdue = bool(
        is_open and raw_scope == "day" and raw_day == today_iso and due_time and due_time < cur_hm
    )
    is_overdue = is_past_due or is_time_overdue

    cat_obj = (cat_map or {}).get(cat_id) if cat_id > 0 else None
    due_label = _format_todo_due_label(raw_scope, raw_day, raw_end_day, lang, today_d)
    rec_label = _format_recurrence_label(recurrence, lang)

    return {
        "id": tid_int,
        "day": raw_day,
        "endDay": raw_end_day,
        "scope": raw_scope,
        "priority": priority,
        "dueTime": due_time,
        "recurrence": recurrence,
        "recurrenceLabel": rec_label,
        "dueLabel": due_label,
        "isPastDue": is_past_due,
        "isOverdue": is_overdue,
        "categoryId": cat_obj["id"] if cat_obj else 0,
        "categoryName": cat_obj["name"] if cat_obj else "",
        "categoryColor": cat_obj["color"] if cat_obj else "",
        "title": r["title"],
        "detail": r["detail"] or "",
        "state": st_val,
        "sessionId": sid_val,
        "position": pos_val,
        "todoistId": td_id,
        "todoistDone": td_done,
    }


def _load_cat_lookup(conn: sqlite3.Connection) -> dict[int, dict[str, Any]]:
    rows = conn.execute("SELECT id, name, color FROM categories").fetchall()
    return {int(r["id"]): {"id": int(r["id"]), "name": r["name"], "color": r["color"]} for r in rows}


def _fetch_session_todos(
    conn: sqlite3.Connection,
    session_id: int,
    link_meta: dict[str, dict[str, Any]],
    lang: str = "en",
    cat_map: dict[int, dict[str, Any]] | None = None,
    open_td_ids: set[str] | None = None,
    ref_date: dt.date | None = None,
    now_hm: str = "",
) -> list[dict[str, Any]]:
    if session_id <= 0:
        return []
    cmap = cat_map if cat_map is not None else _load_cat_lookup(conn)
    rows = conn.execute(
        "SELECT * FROM todos WHERE session_id = ? ORDER BY position, id",
        (session_id,),
    ).fetchall()
    return [
        _serialize_todo_row(
            r,
            link_meta,
            open_td_ids=open_td_ids,
            sid_override=session_id,
            cat_map=cmap,
            lang=lang,
            ref_date=ref_date,
            now_hm=now_hm,
        )
        for r in rows
    ]


def remove_todoist_link(local_todo_id: int) -> None:
    p = todoist_links_path()
    if not p.is_file():
        return
    try:
        raw = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return
    if isinstance(raw, dict) and str(local_todo_id) in raw:
        raw.pop(str(local_todo_id), None)
        _write_private_file(p, json.dumps(raw, ensure_ascii=False))


def remove_todoist_links_by_remote_id(todoist_id: str) -> None:
    td_id = str(todoist_id or "").strip()
    if not td_id:
        return
    p = todoist_links_path()
    if not p.is_file():
        return
    try:
        raw = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return
    if not isinstance(raw, dict):
        return
    to_del = []
    for k, v in raw.items():
        eid = str(v.get("id") or "").strip() if isinstance(v, dict) else (v.strip() if isinstance(v, str) else "")
        if eid == td_id:
            to_del.append(k)
    if to_del:
        for k in to_del:
            raw.pop(k, None)
        _write_private_file(p, json.dumps(raw, ensure_ascii=False))


def _load_todoist_cache() -> dict[str, Any]:
    p = todoist_cache_path()
    if not p.is_file():
        return {}
    try:
        raw = json.loads(p.read_text(encoding="utf-8"))
        return raw if isinstance(raw, dict) else {}
    except Exception:
        return {}


def _save_todoist_cache(cache_obj: dict[str, Any]) -> None:
    try:
        _write_private_file(todoist_cache_path(), json.dumps(cache_obj, ensure_ascii=False))
    except Exception:
        pass


def _todoist_http(
    method: str,
    rel_path: str,
    token: str,
    payload: dict[str, Any] | None = None,
    timeout: float = 6.0,
) -> tuple[int, Any, str]:
    base = todoist_api_base()
    url = base + (rel_path if rel_path.startswith("/") else ("/" + rel_path))
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "User-Agent": "Houra-Omarchy/1.0",
    }
    data_bytes = None
    if payload is not None:
        data_bytes = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=data_bytes, headers=headers, method=method)
    ctx = ssl.create_default_context() if url.startswith("https://") else None
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            status = int(getattr(resp, "status", 200))
            body = resp.read().decode("utf-8", errors="replace").strip()
            if not body:
                return status, None, ""
            try:
                return status, json.loads(body), ""
            except Exception:
                return status, None, ""
    except urllib.error.HTTPError as exc:
        return int(exc.code), None, f"HTTP {exc.code}"
    except Exception as exc:
        return 0, None, str(exc)


def _todoist_friendly_error(status: int, raw_err: str, lang: str, context: str = "filter") -> str:
    if status in (401, 403):
        return tr_en(
            lang,
            "Todoist API anahtarı reddedildi — Ayarlar'dan kontrol et.",
            "Todoist rejected the API token — check it in Settings.",
        )
    if status == 400:
        if context == "write":
            return tr_en(
                lang,
                "Todoist görev verisini kabul etmedi — tarih veya alanları kontrol et.",
                "Todoist rejected the task payload — check date or fields.",
            )
        return tr_en(
            lang,
            "Todoist filtre sorgusu geçersiz — filtreyi kontrol et.",
            "Invalid Todoist filter query — check your filter in Settings.",
        )
    if status == 404:
        return tr_en(lang, "Todoist görevi bulunamadı.", "Todoist task was not found.")
    if status >= 500:
        return tr_en(lang, "Todoist servisi şu an yanıt vermiyor.", "Todoist service is temporarily unavailable.")
    return tr_en(lang, "Todoist sunucusuna ulaşılamadı.", "Couldn't reach Todoist — check your connection.")


def _todoist_paginated_get(rel_path: str, token: str, lang: str) -> tuple[list[dict[str, Any]], str]:
    items: list[dict[str, Any]] = []
    cursor = ""
    for _ in range(3):
        sep = "&" if "?" in rel_path else "?"
        page_path = f"{rel_path}{sep}limit=200" + (f"&cursor={urllib.parse.quote(cursor)}" if cursor else "")
        status, parsed, err = _todoist_http("GET", page_path, token)
        if status < 200 or status >= 300:
            return [], _todoist_friendly_error(status, err, lang)
        if isinstance(parsed, list):
            items.extend(x for x in parsed if isinstance(x, dict))
            break
        if isinstance(parsed, dict):
            batch = parsed.get("results")
            if isinstance(batch, list):
                items.extend(x for x in batch if isinstance(x, dict))
            next_c = str(parsed.get("next_cursor") or "").strip()
            if not next_c:
                break
            cursor = next_c
        else:
            break
    return items, ""


def _build_todoist_due_fields(
    scope_raw: Any,
    day_raw: Any,
    end_day_raw: Any = "",
    due_time_raw: Any = "",
    recurrence_raw: Any = "",
    ref_date: dt.date | None = None,
    is_update: bool = False,
) -> dict[str, Any]:
    """
    Build Free-plan-safe Todoist Unified API v1 due fields.
    NEVER sends Pro-only `deadline_date` or `duration`, which trigger HTTP 400 on Free accounts.
    """
    ref = ref_date or dt.date.today()
    scope, norm_day, norm_end, norm_time, norm_rec = _normalize_schedule(
        scope_raw, day_raw, end_day_raw, due_time_raw, recurrence_raw, ref_date=ref
    )
    if scope == "inbox":
        return {"due_string": "no date", "due_lang": "en"} if is_update else {}

    target_iso = norm_end if (scope in ("week", "month", "range") and norm_end) else norm_day
    target_d = _safe_parse_day(target_iso) or ref

    if norm_rec:
        if norm_rec == "daily":
            phrase = "every day"
        elif norm_rec == "weekday":
            phrase = "every weekday"
        elif norm_rec == "weekly":
            phrase = f"every {_WEEKDAYS_EN[target_d.weekday()]}"
        else:
            phrase = "every month"
        if norm_time:
            phrase = f"{phrase} at {norm_time}"
        return {"due_string": phrase, "due_lang": "en"}

    if norm_time:
        hh, mm = (int(x) for x in norm_time.split(":"))
        local_dt = dt.datetime(target_d.year, target_d.month, target_d.day, hh, mm, 0).astimezone()
        utc_iso = local_dt.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        return {"due_datetime": utc_iso}

    return {"due_date": target_d.isoformat()}


def _resolve_todoist_project_id(
    explicit_project_id: str,
    category_id: int,
    conn: sqlite3.Connection,
) -> str:
    pid = (explicit_project_id or "").strip()
    if pid:
        return pid
    if category_id <= 0:
        return ""
    crow = conn.execute("SELECT name FROM categories WHERE id = ?", (category_id,)).fetchone()
    if crow is None:
        return ""
    target_norm = _norm_topic(crow["name"])
    if not target_norm:
        return ""
    cache = _load_todoist_cache()
    projs = cache.get("projects")
    if isinstance(projs, dict):
        for k, v in projs.items():
            if _norm_topic(str(v)) == target_norm:
                return str(k)
    return ""


def _parse_todoist_due_datetime(due_obj: dict[str, Any]) -> tuple[str, str]:
    raw_dt = str(due_obj.get("datetime") or due_obj.get("date") or "").strip()
    if not raw_dt:
        return "", ""
    day_part = raw_dt[:10] if len(raw_dt) >= 10 else raw_dt
    if "T" not in raw_dt:
        return day_part, ""
    try:
        iso_norm = raw_dt.replace("Z", "+00:00")
        parsed_dt = dt.datetime.fromisoformat(iso_norm)
        if parsed_dt.tzinfo is not None:
            local_dt = parsed_dt.astimezone()
            return local_dt.strftime("%Y-%m-%d"), local_dt.strftime("%H:%M")
        return parsed_dt.strftime("%Y-%m-%d"), parsed_dt.strftime("%H:%M")
    except ValueError:
        hm = raw_dt[11:16] if len(raw_dt) >= 16 else ""
        return day_part, _normalize_due_time(hm)


def sync_todoist_task_completion(
    todoist_id: str,
    completed: bool,
    settings: dict[str, Any],
    lang: str,
) -> tuple[bool, str]:
    if not todoist_id:
        return False, ""
    if not settings.get("todoistOn"):
        return False, tr_en(
            lang,
            "Todoist senkronu kapalı — Ayarlar'dan etkinleştir.",
            "Todoist sync is off — enable it in Settings.",
        )
    token = load_todoist_token()
    if not token:
        return False, tr_en(
            lang,
            "Todoist API anahtarı bulunamadı — Ayarlar'dan bağla.",
            "No Todoist API token configured — connect in Settings.",
        )
    action = "close" if completed else "reopen"
    encoded_id = urllib.parse.quote(str(todoist_id), safe="")
    status, _, raw_err = _todoist_http("POST", f"/tasks/{encoded_id}/{action}", token, timeout=5.0)
    if 200 <= status < 300:
        cache = _load_todoist_cache()
        if completed:
            raw_tasks = cache.get("rawTasks")
            if isinstance(raw_tasks, list):
                cache["rawTasks"] = [t for t in raw_tasks if str(t.get("id", "")) != str(todoist_id)]
                _save_todoist_cache(cache)
        else:
            cache["syncedAt"] = 0.0
            _save_todoist_cache(cache)
        return True, ""
    return False, _todoist_friendly_error(status, raw_err, lang, context="write")


def _fetch_todoist_account_label(token: str) -> str:
    if not token:
        return ""
    status, parsed, _ = _todoist_http("GET", "/user", token, timeout=4.0)
    if 200 <= status < 300 and isinstance(parsed, dict):
        name = str(parsed.get("full_name") or "").strip()
        email = str(parsed.get("email") or "").strip()
        if name and email:
            return f"{name} · {email}"
        return email or name
    return ""


def load_todoist_tasks(
    settings: dict[str, Any],
    categories: list[dict[str, Any]],
    ref_date: dt.date | None = None,
    lang: str = "en",
    force_sync: bool = False,
) -> dict[str, Any]:
    enabled = bool(settings.get("todoistOn"))
    filt = str(settings.get("todoistFilter") or "today | overdue").strip() or "today | overdue"
    token = load_todoist_token()
    has_token = bool(token)
    cache = _load_todoist_cache() if has_token else {}
    account_label = str(cache.get("account") or "").strip() if has_token else ""

    if not enabled or not has_token:
        return {
            "enabled": enabled,
            "hasToken": has_token,
            "account": account_label,
            "filter": filt,
            "syncedAt": 0.0,
            "error": "",
            "openCount": 0,
            "projects": [],
            "tasks": [],
            "groups": [],
        }

    now_ts = time.time()
    cached_filter = str(cache.get("filter") or "")
    synced_at = float(cache.get("syncedAt") or 0.0)
    projects_at = float(cache.get("projectsAt") or 0.0)
    projects_by_id: dict[str, str] = (
        {str(k): str(v) for k, v in cache.get("projects", {}).items()}
        if isinstance(cache.get("projects"), dict)
        else {}
    )
    raw_tasks: list[dict[str, Any]] = (
        [x for x in cache.get("rawTasks", []) if isinstance(x, dict)]
        if isinstance(cache.get("rawTasks"), list)
        else []
    )
    err_msg = str(cache.get("error") or "")

    need_sync = force_sync or (cached_filter != filt) or (now_ts - synced_at >= TODOIST_CACHE_TTL_SEC)
    if need_sync:
        need_projects = (
            (not projects_by_id)
            or (now_ts - projects_at >= TODOIST_PROJECTS_TTL_SEC)
            or (force_sync and (now_ts - projects_at >= 5.0))
        )
        if need_projects:
            proj_items, _ = _todoist_paginated_get("/projects", token, lang)
            if proj_items:
                projects_by_id = {
                    str(p.get("id")): str(p.get("name") or "").strip()
                    for p in proj_items
                    if p.get("id") is not None and str(p.get("name") or "").strip()
                }
                projects_at = now_ts
            fetched_acc = _fetch_todoist_account_label(token)
            if fetched_acc:
                account_label = fetched_acc

        if filt.lower() == "all":
            ep = "/tasks"
        else:
            ep = f"/tasks/filter?query={urllib.parse.quote(filt)}&lang=en"
        fetched_tasks, fetch_err = _todoist_paginated_get(ep, token, lang)
        if fetch_err:
            err_msg = fetch_err
            if cached_filter != filt:
                raw_tasks = []
        else:
            raw_tasks = [t for t in fetched_tasks if not t.get("checked") and not t.get("is_completed")]
            synced_at = now_ts
            err_msg = ""

        _save_todoist_cache(
            {
                "syncedAt": synced_at,
                "filter": filt,
                "projects": projects_by_id,
                "projectsAt": projects_at,
                "account": account_label,
                "rawTasks": raw_tasks,
                "error": err_msg,
            }
        )

    projects_list = [
        {"id": pid, "name": pname}
        for pid, pname in sorted(
            projects_by_id.items(),
            key=lambda kv: (0 if kv[1].lower() in ("inbox", "gelen kutusu") else 1, kv[1].lower(), kv[0]),
        )
    ]

    today_iso = (ref_date or dt.date.today()).isoformat()
    now_hm = dt.datetime.now().strftime("%H:%M")
    cat_by_norm: dict[str, dict[str, Any]] = {}
    for c in categories:
        n = _norm_topic(c["name"])
        if n and n not in cat_by_norm:
            cat_by_norm[n] = c

    def _due_prefix(task_obj: dict[str, Any]) -> str:
        due = task_obj.get("due")
        if isinstance(due, dict):
            day_p, _ = _parse_todoist_due_datetime(due)
            return day_p
        return ""

    def _sort_key(task_obj: dict[str, Any]) -> tuple[int, str, int, str, str]:
        due = task_obj.get("due") if isinstance(task_obj.get("due"), dict) else {}
        dp, tm = _parse_todoist_due_datetime(due) if due else ("", "")
        prio = int(task_obj.get("priority") or 1)
        content = str(task_obj.get("content") or "")
        return (1 if not dp else 0, dp or "9999-99-99", -prio, tm or "99:99", content.lower())

    sorted_raw = sorted(raw_tasks, key=_sort_key)
    fallback_group = "Inbox"
    tasks_out: list[dict[str, Any]] = []
    groups_map: dict[str, dict[str, Any]] = {}
    groups_order: list[str] = []

    for item in sorted_raw:
        tid = str(item.get("id") or "").strip()
        raw_content = str(item.get("content") or "").strip()
        if not tid or not raw_content:
            continue
        clean_title, inline_tags = _clean_task_title(raw_content)
        title = clean_title or raw_content
        desc = str(item.get("description") or "").strip()
        proj_id = str(item.get("project_id") or "")
        proj_name = projects_by_id.get(proj_id, "") or fallback_group
        labels = [str(lb) for lb in (item.get("labels") or []) if str(lb).strip()]
        due = item.get("due") if isinstance(item.get("due"), dict) else {}
        due_date_prefix, due_time_hm = _parse_todoist_due_datetime(due) if due else ("", "")
        is_recurring = bool(due.get("is_recurring")) if due else False
        due_label = str(due.get("string") or due_date_prefix or "").strip()
        if due_time_hm and due_time_hm not in due_label:
            due_label = f"{due_label} {due_time_hm}".strip()
        is_overdue = bool(
            (due_date_prefix and due_date_prefix < today_iso)
            or (due_date_prefix == today_iso and due_time_hm and due_time_hm < now_hm)
        )
        prio = _clamp_priority(item.get("priority") or 1)  # Todoist API: 4=P1, 3=P2, 2=P3, 1=P4

        matched_cat = None
        for cand in [proj_name] + labels + inline_tags:
            nt = _norm_topic(cand)
            if nt and nt in cat_by_norm:
                matched_cat = cat_by_norm[nt]
                break

        detail_parts = []
        if proj_name:
            detail_parts.append(f"#{proj_name}")
        if due_label:
            detail_parts.append(due_label)
        for lb in labels[:2]:
            detail_parts.append(f"@{lb}")

        td_entry = {
            "id": tid,
            "key": f"td:{tid}",
            "title": title,
            "description": desc,
            "detail": " · ".join(detail_parts),
            "dueDate": due_date_prefix,
            "dueTime": due_time_hm,
            "isRecurring": is_recurring,
            "dueLabel": due_label,
            "isOverdue": is_overdue,
            "priority": prio,
            "projectId": proj_id,
            "projectName": proj_name,
            "labels": labels,
            "categoryId": matched_cat["id"] if matched_cat else 0,
            "categoryName": matched_cat["name"] if matched_cat else "",
            "categoryColor": matched_cat["color"] if matched_cat else "",
        }
        tasks_out.append(td_entry)

        if proj_name not in groups_map:
            proj_cat = cat_by_norm.get(_norm_topic(proj_name))
            groups_map[proj_name] = {
                "name": proj_name,
                "categoryId": proj_cat["id"] if proj_cat else (td_entry["categoryId"] or 0),
                "categoryColor": proj_cat["color"] if proj_cat else (td_entry["categoryColor"] or ""),
                "categoryEmoji": proj_cat["emoji"] if proj_cat else "",
                "categoryIcon": proj_cat["icon"] if proj_cat else "",
                "categoryIconColor": proj_cat["iconColor"] if proj_cat else "",
                "tasks": [],
            }
            groups_order.append(proj_name)
        groups_map[proj_name]["tasks"].append(td_entry)

    return {
        "enabled": enabled,
        "hasToken": has_token,
        "account": account_label,
        "filter": filt,
        "syncedAt": synced_at,
        "error": err_msg,
        "openCount": len(tasks_out),
        "projects": projects_list,
        "tasks": tasks_out,
        "groups": [groups_map[g] for g in groups_order],
    }


# ---------------------------------------------------------------------------
# Date & Statistics Helpers
# ---------------------------------------------------------------------------

def parse_day(day_str: str) -> dt.date:
    return dt.date.fromisoformat(day_str)


def day_bounds_epoch(d: dt.date) -> tuple[float, float]:
    start_dt = dt.datetime(d.year, d.month, d.day, 0, 0, 0).astimezone()
    next_d = d + dt.timedelta(days=1)
    end_dt = dt.datetime(next_d.year, next_d.month, next_d.day, 0, 0, 0).astimezone()
    return start_dt.timestamp(), end_dt.timestamp()


def epoch_to_local_day(ts: float) -> str:
    return dt.datetime.fromtimestamp(ts).strftime("%Y-%m-%d")


def _distribute_session_hours(start_ts: float, focus_sec: int, hourly: list[float]) -> None:
    if focus_sec <= 0:
        return
    eff_end = start_ts + focus_sec
    cur = start_ts
    while cur < eff_end:
        ldt = dt.datetime.fromtimestamp(cur)
        next_hour = (ldt.replace(minute=0, second=0, microsecond=0) + dt.timedelta(hours=1)).timestamp()
        seg_end = min(eff_end, next_hour)
        if seg_end <= cur:
            seg_end = eff_end
        hourly[ldt.hour] += (seg_end - cur) / 60.0
        cur = seg_end


def build_snapshot(conn: sqlite3.Connection, params: dict[str, Any]) -> dict[str, Any]:
    settings = load_settings()
    lang = resolve_lang(str(settings.get("language", "system")))
    td_link_meta = load_todoist_link_meta()
    active_sid = params.get("activeSessionId")
    resumed_session: dict[str, Any] | None = None

    if not active_sid and params.get("resumeIfLive"):
        cand = conn.execute(
            "SELECT id, category_id, goal, work_min, rest_min, start, focus_sec, note "
            "FROM sessions WHERE end IS NULL ORDER BY id DESC LIMIT 1"
        ).fetchone()
        if cand is not None:
            now_ts = time.time()
            c_start = float(cand["start"])
            c_wmin = int(cand["work_min"])
            c_fsec = int(cand["focus_sec"])
            elapsed = max(0, int(now_ts - c_start))
            still_live = (
                (c_wmin > 0 and 0 <= (now_ts - c_start) < c_wmin * 60)
                or (c_wmin == 0 and 0 <= (now_ts - (c_start + c_fsec)) < 180)
            )
            if still_live:
                active_sid = int(cand["id"])
                s_todos = _fetch_session_todos(conn, active_sid, td_link_meta, lang=lang)
                resumed_session = {
                    "id": active_sid,
                    "categoryId": int(cand["category_id"]),
                    "goal": cand["goal"] or "",
                    "workMin": c_wmin,
                    "restMin": int(cand["rest_min"]),
                    "start": c_start,
                    "elapsedSec": elapsed if c_wmin > 0 else max(c_fsec, elapsed),
                    "note": cand["note"] or "",
                    "todos": s_todos,
                }

    close_abandoned(conn, active_session_id=int(active_sid) if active_sid else None)

    today_date = dt.date.today()
    today_key = today_date.isoformat()

    # Categories + lifetime aggregates
    cat_stats_rows = conn.execute(
        """
        SELECT category_id,
               COUNT(*) AS cnt,
               IFNULL(SUM(focus_sec), 0) AS sec
        FROM sessions
        WHERE end IS NOT NULL
        GROUP BY category_id
        """
    ).fetchall()
    cat_agg = {int(r["category_id"]): (int(r["cnt"]), int(r["sec"])) for r in cat_stats_rows}

    cat_rows = conn.execute(
        "SELECT id, name, color, emoji, icon, position, icon_color FROM categories ORDER BY position, id"
    ).fetchall()
    categories: list[dict[str, Any]] = []
    cat_map: dict[int, dict[str, Any]] = {}
    for r in cat_rows:
        cid = int(r["id"])
        scnt, ssec = cat_agg.get(cid, (0, 0))
        cdict = {
            "id": cid,
            "name": r["name"],
            "color": r["color"],
            "emoji": r["emoji"] or "",
            "icon": r["icon"] or "",
            "iconColor": r["icon_color"] or "",
            "position": int(r["position"]),
            "sessionCount": scnt,
            "totalMinutes": int(ssec // 60),
        }
        categories.append(cdict)
        cat_map[cid] = cdict

    deleted_cat = {
        "id": 0,
        "name": tr_en(lang, "Silinmiş", "Deleted"),
        "color": "#6e6e77",
        "emoji": "",
        "icon": "",
        "iconColor": "",
        "position": 999999,
    }

    def cat_for(cid: int) -> dict[str, Any]:
        return cat_map.get(cid, deleted_cat)

    # Weekly Markdown tasks & optional Todoist tasks
    weekly = load_weekly_tasks(settings, categories, ref_date=today_date, lang=lang)
    todoist = load_todoist_tasks(
        settings,
        categories,
        ref_date=today_date,
        lang=lang,
        force_sync=bool(params.get("forceTodoistSync")),
    )
    open_td_ids = {str(t.get("id") or "") for t in (todoist.get("tasks") or []) if t.get("id")}
    reopened_remote_ids = {
        str(meta.get("id") or "")
        for meta in td_link_meta.values()
        if meta.get("done") and str(meta.get("id") or "") in open_td_ids
    }
    for r_td_id in reopened_remote_ids:
        set_todoist_done_by_remote_id(r_td_id, False)
    if reopened_remote_ids:
        for meta in td_link_meta.values():
            if str(meta.get("id") or "") in reopened_remote_ids:
                meta["done"] = False
    if resumed_session is not None:
        for rt in resumed_session["todos"]:
            if rt.get("todoistId") and rt["todoistId"] in open_td_ids:
                rt["todoistDone"] = False

    # Today's sessions & todos
    t_start, t_end = day_bounds_epoch(today_date)
    today_sessions_rows = conn.execute(
        """
        SELECT id, category_id, goal, work_min, rest_min, start, end, focus_sec, note, emergency
        FROM sessions
        WHERE start >= ? AND start < ?
        ORDER BY start
        """,
        (t_start, t_end),
    ).fetchall()

    now_hm = dt.datetime.now().strftime("%H:%M")
    cur_week_mon = today_date - dt.timedelta(days=today_date.isoweekday() - 1)
    cur_week_sun = cur_week_mon + dt.timedelta(days=6)
    cur_week_mon_iso = cur_week_mon.isoformat()
    cur_week_sun_iso = cur_week_sun.isoformat()
    cur_month_first = dt.date(today_date.year, today_date.month, 1)
    cur_month_last = dt.date(
        today_date.year,
        today_date.month,
        calendar.monthrange(today_date.year, today_date.month)[1],
    )
    cur_month_first_iso = cur_month_first.isoformat()
    cur_month_last_iso = cur_month_last.isoformat()
    min_horizon_iso = min(cur_week_mon_iso, cur_month_first_iso)

    horizon_rows = conn.execute(
        "SELECT * FROM todos WHERE state != 2 OR day >= ? OR end_day >= ? ORDER BY position, id",
        (min_horizon_iso, min_horizon_iso),
    ).fetchall()
    all_horizon_todos = [
        _serialize_todo_row(
            r,
            td_link_meta,
            open_td_ids=open_td_ids,
            cat_map=cat_map,
            lang=lang,
            ref_date=today_date,
            now_hm=now_hm,
        )
        for r in horizon_rows
    ]

    today_todos = sorted(
        [
            t
            for t in all_horizon_todos
            if (t["scope"] == "day" and t["day"] == today_key)
            or (t["scope"] == "range" and t["day"] <= today_key <= (t["endDay"] or t["day"]))
            or t["isPastDue"]
        ],
        key=lambda t: (
            0 if t["isPastDue"] else 1,
            -t["priority"],
            0 if t["dueTime"] else 1,
            t["dueTime"],
            t["position"],
            t["id"],
        ),
    )

    week_todos = sorted(
        [
            t
            for t in all_horizon_todos
            if (t["scope"] == "week" and ((t["endDay"] or t["day"]) >= cur_week_mon_iso or t["state"] != 2))
            or (
                t["scope"] == "range"
                and t["day"] <= cur_week_sun_iso
                and (t["endDay"] or t["day"]) >= cur_week_mon_iso
            )
            or (
                t["scope"] == "day"
                and cur_week_mon_iso <= t["day"] <= cur_week_sun_iso
                and (t["day"] >= today_key or t["state"] != 2)
            )
        ],
        key=lambda t: (
            0 if t["scope"] == "week" else 1,
            t["day"],
            -t["priority"],
            0 if t["dueTime"] else 1,
            t["dueTime"],
            t["position"],
            t["id"],
        ),
    )

    month_todos = sorted(
        [
            t
            for t in all_horizon_todos
            if (t["scope"] == "month" and ((t["endDay"] or t["day"]) >= cur_month_first_iso or t["state"] != 2))
            or (
                t["scope"] in ("week", "range")
                and t["day"] <= cur_month_last_iso
                and (t["endDay"] or t["day"]) >= cur_month_first_iso
                and (t["state"] != 2 or (t["endDay"] or t["day"]) >= today_key)
            )
        ],
        key=lambda t: (
            0 if t["scope"] == "month" else 1,
            t["day"],
            -t["priority"],
            t["position"],
            t["id"],
        ),
    )

    upcoming_todos = sorted(
        [
            t
            for t in all_horizon_todos
            if t["scope"] != "inbox"
            and (
                t["day"] > today_key
                or (t["scope"] in ("week", "month", "range") and (t["endDay"] or t["day"]) >= today_key)
            )
        ],
        key=lambda t: (
            t["day"],
            t["endDay"] or t["day"],
            -t["priority"],
            0 if t["dueTime"] else 1,
            t["dueTime"],
            t["position"],
            t["id"],
        ),
    )

    inbox_todos = sorted(
        [t for t in all_horizon_todos if t["scope"] == "inbox"],
        key=lambda t: (-t["priority"], t["position"], t["id"]),
    )

    today_ids_set = {t["id"] for t in today_todos}
    open_planned = sorted(
        [
            t
            for t in all_horizon_todos
            if t["state"] != 2 and t["sessionId"] == 0 and t["id"] not in today_ids_set
        ],
        key=lambda t: (
            0 if t["scope"] == "week" else (1 if t["scope"] == "month" else (2 if t["scope"] in ("day", "range") else 3)),
            -t["priority"],
            t["day"],
            t["position"],
            t["id"],
        ),
    )

    horizons_obj = {
        "today": today_todos,
        "week": week_todos,
        "month": month_todos,
        "upcoming": upcoming_todos,
        "inbox": inbox_todos,
        "openPlanned": open_planned,
        "counts": {
            "today": sum(1 for t in today_todos if t["state"] != 2),
            "week": sum(1 for t in week_todos if t["state"] != 2),
            "month": sum(1 for t in month_todos if t["state"] != 2),
            "upcoming": sum(1 for t in upcoming_todos if t["state"] != 2),
            "inbox": sum(1 for t in inbox_todos if t["state"] != 2),
            "overdue": sum(1 for t in today_todos if t["isOverdue"] and t["state"] != 2),
        },
    }

    unattached_todos = [t for t in today_todos if t["sessionId"] == 0 and t["state"] != 2]
    done_todos_cnt = sum(1 for t in today_todos if t["state"] == 2)

    today_focus_mins = 0
    today_focus_sec = 0
    today_completed_cnt = 0
    today_50_cnt = 0
    today_breaks_cnt = 0
    today_break_mins = 0
    today_emergency_cnt = 0
    today_timeline: list[dict[str, Any]] = []

    for r in today_sessions_rows:
        is_done = r["end"] is not None
        fsec = int(r["focus_sec"])
        wmin_row = int(r["work_min"])
        rmin_row = int(r["rest_min"])
        c = cat_for(int(r["category_id"]))
        if is_done:
            today_focus_sec += fsec
            today_focus_mins += fsec // 60
            today_completed_cnt += 1
            if wmin_row == 50:
                today_50_cnt += 1
            if int(r["emergency"]) != 0:
                today_emergency_cnt += 1
            else:
                today_break_mins += max(0, rmin_row)
                if rmin_row > 0:
                    today_breaks_cnt += 1
        start_dt = dt.datetime.fromtimestamp(float(r["start"]))
        end_ts = float(r["end"]) if r["end"] is not None else (float(r["start"]) + max(60, fsec))
        end_dt = dt.datetime.fromtimestamp(end_ts)
        today_timeline.append(
            {
                "id": int(r["id"]),
                "categoryId": int(r["category_id"]),
                "categoryName": c["name"],
                "color": c["color"],
                "emoji": c["emoji"],
                "icon": c["icon"],
                "iconColor": c["iconColor"],
                "goal": r["goal"] or c["name"],
                "workMin": wmin_row,
                "restMin": rmin_row,
                "rhythmLabel": _rhythm_label(wmin_row, rmin_row, lang),
                "start": float(r["start"]),
                "end": float(r["end"]) if r["end"] is not None else 0.0,
                "startHourFrac": start_dt.hour + start_dt.minute / 60.0 + start_dt.second / 3600.0,
                "endHourFrac": min(24.0, max(start_dt.hour + start_dt.minute / 60.0 + 0.08, end_dt.hour + end_dt.minute / 60.0 + end_dt.second / 3600.0)),
                "focusSec": fsec,
                "focusMinutes": fsec // 60,
                "emergency": int(r["emergency"]) != 0,
                "completed": is_done,
            }
        )

    # Recent unique repeat candidates (last 30 days, up to 5)
    recent_cutoff = time.time() - 30 * 86400
    recent_rows = conn.execute(
        """
        SELECT category_id, goal, work_min, rest_min
        FROM sessions
        WHERE start >= ? AND end IS NOT NULL
        ORDER BY start DESC
        """,
        (recent_cutoff,),
    ).fetchall()
    seen_repeats: set[tuple[int, str, int, int]] = set()
    recent_repeats: list[dict[str, Any]] = []
    for r in recent_rows:
        cid = int(r["category_id"])
        if cid not in cat_map:
            continue
        c = cat_map[cid]
        goal = (r["goal"] or "").strip() or c["name"]
        wmin = int(r["work_min"])
        rmin = int(r["rest_min"])
        key = (cid, goal.lower(), wmin, rmin)
        if key in seen_repeats:
            continue
        seen_repeats.add(key)
        recent_repeats.append(
            {
                "categoryId": cid,
                "categoryName": c["name"],
                "color": c["color"],
                "emoji": c["emoji"],
                "icon": c["icon"],
                "iconColor": c["iconColor"],
                "goal": goal,
                "workMin": wmin,
                "restMin": rmin,
                "rhythmLabel": _rhythm_label(wmin, rmin, lang),
            }
        )
        if len(recent_repeats) >= 5:
            break

    # Statistics date range (defaults to current ISO week Monday..Sunday)
    iso_wd = today_date.isocalendar()[2]
    default_start = today_date - dt.timedelta(days=iso_wd - 1)
    default_end = default_start + dt.timedelta(days=6)

    try:
        range_start = parse_day(str(params["rangeStart"])) if params.get("rangeStart") else default_start
    except Exception:
        range_start = default_start
    try:
        range_end = parse_day(str(params["rangeEnd"])) if params.get("rangeEnd") else default_end
    except Exception:
        range_end = default_end
    if range_end < range_start:
        range_start, range_end = range_end, range_start
    if (range_end - range_start).days > 3660:
        range_start = range_end - dt.timedelta(days=3660)

    filter_topic = int(params.get("statsTopicId") or 0)

    stats = _compute_stats(conn, range_start, range_end, filter_topic, categories, cat_for, lang)

    # Sessions history (filtered by withNotes / topicId / day, last 90 days by default)
    hist_notes_only = bool(params.get("historyNotesOnly"))
    hist_topic_id = int(params.get("historyTopicId") or 0)
    hist_day = str(params.get("historyDay") or "").strip()

    where_clauses = ["end IS NOT NULL"]
    q_args: list[Any] = []
    if hist_notes_only:
        where_clauses.append("TRIM(note) != ''")
    if hist_topic_id > 0:
        where_clauses.append("category_id = ?")
        q_args.append(hist_topic_id)
    if hist_day:
        try:
            hd = parse_day(hist_day)
            hs, he = day_bounds_epoch(hd)
            where_clauses.append("start >= ? AND start < ?")
            q_args.extend([hs, he])
        except Exception:
            pass
    else:
        where_clauses.append("start >= ?")
        q_args.append(time.time() - 90 * 86400)

    hist_sql = (
        "SELECT id, category_id, goal, work_min, rest_min, start, end, focus_sec, note, emergency "
        f"FROM sessions WHERE {' AND '.join(where_clauses)} ORDER BY start DESC LIMIT 1000"
    )
    hist_rows = conn.execute(hist_sql, q_args).fetchall()
    sids = [int(r["id"]) for r in hist_rows]
    todos_by_session: dict[int, list[dict[str, Any]]] = {}
    if sids:
        placeholders = ",".join("?" for _ in sids)
        st_rows = conn.execute(
            f"SELECT * FROM todos WHERE session_id IN ({placeholders}) ORDER BY position, id",
            sids,
        ).fetchall()
        for tr in st_rows:
            sid = int(tr["session_id"])
            todos_by_session.setdefault(sid, []).append(
                _serialize_todo_row(
                    tr,
                    td_link_meta,
                    open_td_ids=open_td_ids,
                    sid_override=sid,
                    cat_map=cat_map,
                    lang=lang,
                    ref_date=today_date,
                    now_hm=now_hm,
                )
            )

    hist_days_map: dict[str, dict[str, Any]] = {}
    hist_days_order: list[str] = []
    for r in hist_rows:
        dkey = epoch_to_local_day(float(r["start"]))
        if dkey not in hist_days_map:
            hist_days_map[dkey] = {"day": dkey, "totalMinutes": 0, "sessions": []}
            hist_days_order.append(dkey)
        fmin = int(r["focus_sec"]) // 60
        wmin_row = int(r["work_min"])
        rmin_row = int(r["rest_min"])
        c = cat_for(int(r["category_id"]))
        sid = int(r["id"])
        st_list = todos_by_session.get(sid, [])
        st_done = sum(1 for t in st_list if int(t["state"]) == 2)
        hist_days_map[dkey]["totalMinutes"] += fmin
        hist_days_map[dkey]["sessions"].append(
            {
                "id": sid,
                "categoryId": int(r["category_id"]),
                "categoryName": c["name"],
                "color": c["color"],
                "emoji": c["emoji"],
                "icon": c["icon"],
                "iconColor": c["iconColor"],
                "goal": r["goal"] or c["name"],
                "workMin": wmin_row,
                "restMin": rmin_row,
                "rhythmLabel": _rhythm_label(wmin_row, rmin_row, lang),
                "start": float(r["start"]),
                "end": float(r["end"]),
                "focusSec": int(r["focus_sec"]),
                "focusMinutes": fmin,
                "note": r["note"] or "",
                "emergency": int(r["emergency"]) != 0,
                "todos": st_list,
                "todosDone": st_done,
                "todosTotal": len(st_list),
            }
        )

    chime_file = ensure_chime()

    return {
        "ok": True,
        "resumedSession": resumed_session,
        "settings": settings,
        "resolvedLang": lang,
        "dbPath": str(db_path()),
        "chimePath": str(chime_file),
        "categories": categories,
        "today": {
            "day": today_key,
            "focusSec": today_focus_sec,
            "focusMinutes": today_focus_mins,
            "sessionsCount": today_completed_cnt,
            "pomodoro50Count": today_50_cnt,
            "breaksCount": today_breaks_cnt,
            "breakMinutes": today_break_mins,
            "emergencyCount": today_emergency_cnt,
            "todos": today_todos,
            "horizons": horizons_obj,
            "unattachedTodos": unattached_todos,
            "doneTodos": done_todos_cnt,
            "totalTodos": len(today_todos),
            "timeline": today_timeline,
            "recentRepeats": recent_repeats,
        },
        "weekly": weekly,
        "todoist": todoist,
        "stats": stats,
        "history": [hist_days_map[d] for d in hist_days_order],
    }


def _compute_stats(
    conn: sqlite3.Connection,
    range_start: dt.date,
    range_end: dt.date,
    filter_topic: int,
    categories: list[dict[str, Any]],
    cat_for: Any,
    lang: str,
) -> dict[str, Any]:
    span_days = (range_end - range_start).days + 1
    rs_epoch, _ = day_bounds_epoch(range_start)
    _, re_epoch = day_bounds_epoch(range_end)

    prev_end = range_start - dt.timedelta(days=1)
    prev_start = prev_end - dt.timedelta(days=span_days - 1)
    ps_epoch, _ = day_bounds_epoch(prev_start)
    _, pe_epoch = day_bounds_epoch(prev_end)

    all_rows = conn.execute(
        """
        SELECT id, category_id, goal, work_min, rest_min, start, end, focus_sec, note, emergency
        FROM sessions
        WHERE end IS NOT NULL AND start >= ? AND start < ?
        ORDER BY start
        """,
        (rs_epoch, re_epoch),
    ).fetchall()

    rows = [r for r in all_rows if int(r["category_id"]) == filter_topic] if filter_topic > 0 else list(all_rows)

    topic_clause = " AND category_id = ?" if filter_topic > 0 else ""
    prev_args: list[Any] = [ps_epoch, pe_epoch] + ([filter_topic] if filter_topic > 0 else [])
    prev_rows = conn.execute(
        f"SELECT focus_sec FROM sessions WHERE end IS NOT NULL AND start >= ? AND start < ?{topic_clause}",
        prev_args,
    ).fetchall()
    prev_minutes = sum(int(r["focus_sec"]) // 60 for r in prev_rows)

    # Fetch todos attached to all sessions in range
    all_sids = [int(r["id"]) for r in all_rows]
    todos_by_sid: dict[int, list[int]] = {}
    if all_sids:
        for chunk_start in range(0, len(all_sids), 500):
            chunk = all_sids[chunk_start:chunk_start + 500]
            ph = ",".join("?" for _ in chunk)
            for tr in conn.execute(f"SELECT session_id, state FROM todos WHERE session_id IN ({ph})", chunk).fetchall():
                todos_by_sid.setdefault(int(tr["session_id"]), []).append(int(tr["state"]))

    tasks_total = 0
    tasks_done = 0
    for r in rows:
        states = todos_by_sid.get(int(r["id"]), [])
        tasks_total += len(states)
        tasks_done += sum(1 for st in states if st == 2)
    tasks_pct = int(round((tasks_done * 100.0) / tasks_total)) if tasks_total > 0 else 0

    days_list: list[dict[str, Any]] = []
    days_index: dict[str, dict[str, Any]] = {}
    for offset in range(span_days):
        d = range_start + dt.timedelta(days=offset)
        dkey = d.isoformat()
        d_obj = {
            "day": dkey,
            "dayNum": d.day,
            "month": d.month,
            "weekday": d.isoweekday(),  # 1=Mon .. 7=Sun
            "totalMinutes": 0,
            "allTotalMinutes": 0,
            "_catMins": {},
            "_allCatMins": {},
            "byCategory": [],
            "allByCategory": [],
            "sessions": [],
            "allSessions": [],
        }
        days_list.append(d_obj)
        days_index[dkey] = d_obj

    all_cat_totals_mins: dict[int, int] = {}
    all_total_mins = 0

    for r in all_rows:
        fsec = int(r["focus_sec"])
        fmin = fsec // 60
        cid = int(r["category_id"])
        wmin_row = int(r["work_min"])
        rmin_row = int(r["rest_min"])
        all_total_mins += fmin
        all_cat_totals_mins[cid] = all_cat_totals_mins.get(cid, 0) + fmin

        start_ts = float(r["start"])
        end_ts = float(r["end"])
        dkey = epoch_to_local_day(start_ts)
        d_obj = days_index.get(dkey)
        if d_obj is not None:
            d_obj["allTotalMinutes"] += fmin
            d_obj["_allCatMins"][cid] = d_obj["_allCatMins"].get(cid, 0) + fmin
            c = cat_for(cid)
            sdt = dt.datetime.fromtimestamp(start_ts)
            sh = sdt.hour + sdt.minute / 60.0 + sdt.second / 3600.0
            dur_h = fsec / 3600.0
            eh = min(24.0, sh + max(0.08, dur_h))
            sid = int(r["id"])
            st_states = todos_by_sid.get(sid, [])
            sess_entry = {
                "id": sid,
                "categoryId": cid,
                "categoryName": c["name"],
                "color": c["color"],
                "emoji": c["emoji"],
                "icon": c["icon"],
                "iconColor": c["iconColor"],
                "goal": r["goal"] or c["name"],
                "workMin": wmin_row,
                "restMin": rmin_row,
                "rhythmLabel": _rhythm_label(wmin_row, rmin_row, lang),
                "start": start_ts,
                "end": end_ts,
                "startHourFrac": sh,
                "endHourFrac": eh,
                "durationHours": dur_h,
                "focusMinutes": fmin,
                "note": r["note"] or "",
                "emergency": int(r["emergency"]) != 0,
                "todosDone": sum(1 for st in st_states if st == 2),
                "todosTotal": len(st_states),
            }
            d_obj["allSessions"].append(sess_entry)
            if filter_topic <= 0 or cid == filter_topic:
                d_obj["totalMinutes"] += fmin
                d_obj["_catMins"][cid] = d_obj["_catMins"].get(cid, 0) + fmin
                d_obj["sessions"].append(sess_entry)

    total_minutes = 0
    hourly_mins = [0.0] * 24
    for r in rows:
        fsec = int(r["focus_sec"])
        total_minutes += fsec // 60
        _distribute_session_hours(float(r["start"]), fsec, hourly_mins)

    best_day_key = ""
    best_day_mins = 0
    active_days = 0
    max_day_mins = 0

    def _build_by_cat(cat_mins_map: dict[int, int]) -> list[dict[str, Any]]:
        out = []
        for cid, cmins in sorted(cat_mins_map.items(), key=lambda kv: (int(cat_for(kv[0]).get("position", 999999)), kv[0])):
            if cmins <= 0:
                continue
            c = cat_for(cid)
            out.append(
                {
                    "categoryId": cid,
                    "categoryName": c["name"],
                    "color": c["color"],
                    "minutes": cmins,
                }
            )
        return out

    for d_obj in days_list:
        mins = d_obj["totalMinutes"]
        if mins > 0:
            active_days += 1
        if mins > max_day_mins:
            max_day_mins = mins
        if mins > best_day_mins:
            best_day_mins = mins
            best_day_key = d_obj["day"]
        d_obj["byCategory"] = _build_by_cat(d_obj["_catMins"])
        d_obj["allByCategory"] = _build_by_cat(d_obj["_allCatMins"])
        del d_obj["_catMins"]
        del d_obj["_allCatMins"]

    if prev_minutes > 0:
        delta_pct: int | None = int(round(((total_minutes - prev_minutes) * 100.0) / prev_minutes))
    else:
        delta_pct = None

    today_iso = dt.date.today()
    elapsed_days = min(span_days, max(1, (min(range_end, today_iso) - range_start).days + 1)) if range_start <= today_iso else span_days
    daily_avg = int(round(total_minutes / max(1, elapsed_days)))

    # Unfiltered category breakdown across ALL categories (matching Stats.swift:211-241)
    cat_ids_seen = {int(c["id"]) for c in categories}
    breakdown_cids = [int(c["id"]) for c in categories]
    for cid in all_cat_totals_mins:
        if cid not in cat_ids_seen and all_cat_totals_mins[cid] > 0:
            breakdown_cids.append(cid)

    max_cat_mins = max([all_cat_totals_mins.get(cid, 0) for cid in breakdown_cids], default=0)
    cat_breakdown = []
    for cid in sorted(breakdown_cids, key=lambda k: (-all_cat_totals_mins.get(k, 0), int(cat_for(k).get("position", 999999)), k)):
        c = cat_for(cid)
        cmins = all_cat_totals_mins.get(cid, 0)
        pct = int(round((cmins * 100.0) / all_total_mins)) if all_total_mins > 0 else 0
        bar_ratio = (cmins / max_cat_mins) if max_cat_mins > 0 else 0.0
        cat_breakdown.append(
            {
                "categoryId": cid,
                "name": c["name"],
                "color": c["color"],
                "emoji": c["emoji"],
                "icon": c["icon"],
                "iconColor": c["iconColor"],
                "minutes": cmins,
                "pct": pct,
                "barRatio": round(bar_ratio, 4),
            }
        )

    hourly_int = [int(round(x)) for x in hourly_mins]
    peak_hour = -1
    peak_mins = 0
    for h, hm in enumerate(hourly_int):
        if hm > peak_mins:
            peak_mins = hm
            peak_hour = h

    return {
        "rangeStart": range_start.isoformat(),
        "rangeEnd": range_end.isoformat(),
        "spanDays": span_days,
        "filterTopicId": filter_topic,
        "totalMinutes": total_minutes,
        "allTotalMinutes": all_total_mins,
        "prevMinutes": prev_minutes,
        "deltaPct": delta_pct,
        "dailyAvgMinutes": daily_avg,
        "activeDays": active_days,
        "sessionsCount": len(rows),
        "tasksDone": tasks_done,
        "tasksTotal": tasks_total,
        "tasksPct": tasks_pct,
        "bestDay": best_day_key,
        "bestDayMinutes": best_day_mins,
        "maxDayMinutes": max_day_mins,
        "maxCategoryMinutes": max_cat_mins,
        "days": days_list,
        "categoryBreakdown": cat_breakdown,
        "hourly": hourly_int,
        "peakHour": peak_hour,
        "peakHourMinutes": peak_mins,
    }


# ---------------------------------------------------------------------------
# Mutations & Commands
# ---------------------------------------------------------------------------

def handle_command(cmd: str, payload: dict[str, Any]) -> dict[str, Any]:
    settings = load_settings()
    lang = resolve_lang(str(settings.get("language", "system")))

    if cmd == "ensure-chime":
        return {"ok": True, "chimePath": str(ensure_chime())}

    if cmd == "save-settings":
        patch = payload.get("settings") if isinstance(payload.get("settings"), dict) else payload
        save_settings(patch)
        with open_db(lang) as conn:
            return build_snapshot(conn, payload)

    if cmd == "save-todoist-token":
        tok = str(payload.get("token") or "").strip()
        clean_payload = {k: v for k, v in payload.items() if k != "token"}
        if not tok:
            with open_db(lang) as conn:
                return build_snapshot(conn, clean_payload)
        proj_items, verify_err = _todoist_paginated_get("/projects", tok, lang)
        if verify_err:
            with open_db(lang) as conn:
                snap = build_snapshot(conn, clean_payload)
                if isinstance(snap.get("todoist"), dict):
                    snap["todoist"]["error"] = verify_err
                snap["todoistSynced"] = False
                return snap
        acc_label = _fetch_todoist_account_label(tok)
        save_todoist_token_file(tok)
        todoist_cache_path().unlink(missing_ok=True)
        now_ts = time.time()
        _save_todoist_cache(
            {
                "syncedAt": 0.0,
                "filter": "",
                "projects": {
                    str(p.get("id")): str(p.get("name") or "").strip()
                    for p in proj_items
                    if p.get("id") is not None and str(p.get("name") or "").strip()
                },
                "projectsAt": now_ts,
                "account": acc_label,
                "rawTasks": [],
                "error": "",
            }
        )
        save_settings({"todoistOn": True})
        with open_db(lang) as conn:
            snap = build_snapshot(conn, {**clean_payload, "forceTodoistSync": True})
            snap["todoistSynced"] = True
            return snap

    if cmd == "clear-todoist-token":
        save_todoist_token_file("")
        todoist_cache_path().unlink(missing_ok=True)
        save_settings({"todoistOn": False})
        with open_db(lang) as conn:
            return build_snapshot(conn, payload)

    if cmd == "sync-todoist":
        patch_td: dict[str, Any] = {}
        if "todoistFilter" in payload:
            patch_td["todoistFilter"] = str(payload.get("todoistFilter") or "today | overdue").strip() or "today | overdue"
        if "todoistOn" in payload:
            patch_td["todoistOn"] = bool(payload["todoistOn"])
        if patch_td:
            save_settings(patch_td)
        with open_db(lang) as conn:
            snap = build_snapshot(conn, {**payload, "forceTodoistSync": True})
            snap["todoistSynced"] = True
            return snap

    with open_db(lang) as conn:
        if cmd == "snapshot":
            return build_snapshot(conn, payload)

        if cmd == "start-session":
            cid = int(payload["categoryId"])
            cat_row = conn.execute("SELECT name FROM categories WHERE id = ?", (cid,)).fetchone()
            cat_name = (cat_row["name"] if cat_row is not None else tr_en(lang, "Genel", "General")).strip()
            goal = str(payload.get("goal") or "").strip() or cat_name
            work_min = max(0, int(payload.get("workMin", 50)))
            rest_min = max(1, int(payload.get("restMin", 10 if work_min != 25 else 5)))
            start_ts = float(payload.get("start") or time.time())
            day_key = str(payload.get("day") or epoch_to_local_day(start_ts))

            # Cleanly close any previously running session before inserting the new one
            close_prev_id = int(payload.get("closeSessionId") or 0)
            close_prev_sec = payload.get("closeFocusSec")
            open_rows = conn.execute(
                "SELECT id, start, work_min, focus_sec FROM sessions WHERE end IS NULL"
            ).fetchall()
            for orow in open_rows:
                oid = int(orow["id"])
                if close_prev_id == oid and close_prev_sec is not None:
                    actual_sec = max(0, int(close_prev_sec))
                else:
                    ow = int(orow["work_min"])
                    raw_el = max(0, int(start_ts - float(orow["start"])))
                    actual_sec = min(raw_el, ow * 60) if ow > 0 else max(int(orow["focus_sec"]), raw_el)
                conn.execute(
                    "UPDATE sessions SET end = ?, focus_sec = ? WHERE id = ?",
                    (start_ts, actual_sec, oid),
                )

            cur = conn.execute(
                "INSERT INTO sessions (category_id, goal, work_min, rest_min, start) VALUES (?, ?, ?, ?, ?)",
                (cid, goal, work_min, rest_min, start_ts),
            )
            sid = int(cur.lastrowid)

            attached_ids: list[int] = []
            for raw_tid in payload.get("todoIds") or []:
                tid = int(raw_tid)
                conn.execute("UPDATE todos SET session_id = ? WHERE id = ?", (sid, tid))
                attached_ids.append(tid)

            existing_td_map: dict[str, int] = {}
            cur_links = load_todoist_links()
            for r_ex in conn.execute(
                "SELECT id FROM todos WHERE session_id IS NULL AND state != 2 ORDER BY position, id"
            ).fetchall():
                ex_id = int(r_ex["id"])
                ex_td = cur_links.get(str(ex_id), "")
                if ex_td and ex_td not in existing_td_map:
                    existing_td_map[ex_td] = ex_id

            td_synced_on_start = False
            for extra in payload.get("extraTasks") or []:
                raw_title = str(extra.get("title") or "").strip()
                if not raw_title:
                    continue
                clean_title, sh_prio, sh_time = _extract_task_shorthands(raw_title)
                detail = str(extra.get("detail") or "").strip()
                td_id = str(extra.get("todoistId") or "").strip()
                reuse_id = existing_td_map.get(td_id, 0) if td_id else 0
                if reuse_id > 0 and reuse_id not in attached_ids:
                    conn.execute("UPDATE todos SET session_id = ? WHERE id = ?", (sid, reuse_id))
                    attached_ids.append(reuse_id)
                    continue

                ex_prio = (
                    _clamp_priority(extra["priority"])
                    if extra.get("priority") is not None
                    else (sh_prio if sh_prio is not None else 1)
                )
                ex_time = extra.get("dueTime") if extra.get("dueTime") else sh_time
                ex_scope, ex_day, ex_end, norm_ex_time, norm_ex_rec = _normalize_schedule(
                    extra.get("scope", "day"),
                    extra.get("day", day_key),
                    extra.get("endDay", ""),
                    ex_time,
                    extra.get("recurrence", ""),
                )
                ex_cat = max(0, int(extra.get("categoryId") or 0))

                if not td_id and extra.get("createOnTodoist") and settings.get("todoistOn"):
                    td_tok = load_todoist_token()
                    if td_tok:
                        td_body: dict[str, Any] = {"content": clean_title, "priority": ex_prio}
                        if detail:
                            td_body["description"] = detail
                        resolved_pid = _resolve_todoist_project_id(
                            str(extra.get("projectId") or ""), ex_cat or cid, conn
                        )
                        if resolved_pid:
                            td_body["project_id"] = resolved_pid
                        td_body.update(
                            _build_todoist_due_fields(
                                ex_scope, ex_day, ex_end, norm_ex_time, norm_ex_rec, is_update=False
                            )
                        )
                        st_code, created_obj, _ = _todoist_http("POST", "/tasks", td_tok, payload=td_body)
                        if 200 <= st_code < 300 and isinstance(created_obj, dict) and created_obj.get("id"):
                            td_id = str(created_obj["id"]).strip()
                            td_synced_on_start = True

                tcur = conn.execute(
                    """
                    INSERT INTO todos (day, title, detail, state, session_id, position, priority, scope, end_day, due_time, recurrence, category_id)
                    VALUES (?, ?, ?, 0, ?, (SELECT IFNULL(MAX(position), 0) + 1 FROM todos WHERE day = ?), ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        ex_day,
                        clean_title,
                        detail,
                        sid,
                        ex_day,
                        ex_prio,
                        ex_scope,
                        ex_end,
                        norm_ex_time,
                        norm_ex_rec,
                        ex_cat,
                    ),
                )
                new_tid = int(tcur.lastrowid)
                attached_ids.append(new_tid)
                if td_id:
                    set_todoist_link(new_tid, td_id)

            for idx, tid in enumerate(attached_ids):
                st = 1 if idx == 0 else 0
                conn.execute("UPDATE todos SET state = ? WHERE id = ?", (st, tid))

            conn.commit()
            if td_synced_on_start:
                c_obj = _load_todoist_cache()
                c_obj["syncedAt"] = 0.0
                _save_todoist_cache(c_obj)
            settings_patch: dict[str, Any] = {"lastTopic": cid, "rhythmWork": work_min}
            r_mode = str(payload.get("rhythmMode") or "").strip()
            if r_mode in ("25", "50", "custom", "free"):
                settings_patch["rhythmMode"] = r_mode
            if payload.get("customWork") is not None:
                settings_patch["customWork"] = max(1, min(240, int(payload["customWork"])))
            if payload.get("customRest") is not None:
                settings_patch["customRest"] = max(1, min(90, int(payload["customRest"])))
            save_settings(settings_patch)

            td_meta_now = load_todoist_link_meta()
            s_todos = _fetch_session_todos(conn, sid, td_meta_now, lang=lang)
            snap = build_snapshot(
                conn,
                {"activeSessionId": sid, **payload, **({"forceTodoistSync": True} if td_synced_on_start else {})},
            )
            snap["startedSession"] = {
                "id": sid,
                "categoryId": cid,
                "goal": goal,
                "workMin": work_min,
                "restMin": rest_min,
                "start": start_ts,
                "note": "",
                "todos": s_todos,
            }
            return snap

        if cmd == "checkpoint-session":
            sid = int(payload["sessionId"])
            fsec = max(0, int(payload.get("focusSec", 0)))
            conn.execute("UPDATE sessions SET focus_sec = ? WHERE id = ?", (fsec, sid))
            conn.commit()
            return {"ok": True, "sessionId": sid, "focusSec": fsec}

        if cmd == "finish-session":
            sid = int(payload["sessionId"])
            fsec = max(0, int(payload.get("focusSec", 0)))
            end_ts = float(payload.get("end") or time.time())
            skip_break = bool(payload.get("skipBreak"))
            if skip_break:
                conn.execute(
                    "UPDATE sessions SET end = ?, focus_sec = ?, rest_min = 0 WHERE id = ?",
                    (end_ts, fsec, sid),
                )
            else:
                conn.execute("UPDATE sessions SET end = ?, focus_sec = ? WHERE id = ?", (end_ts, fsec, sid))
            conn.commit()
            clean_payload = dict(payload)
            if skip_break and int(clean_payload.get("activeSessionId") or 0) == sid:
                clean_payload.pop("activeSessionId", None)
            return build_snapshot(conn, clean_payload)

        if cmd == "cancel-session":
            sid = int(payload.get("sessionId") or 0)
            if sid > 0:
                conn.execute(
                    "UPDATE todos SET session_id = NULL, state = CASE WHEN state = 1 THEN 0 ELSE state END WHERE session_id = ?",
                    (sid,),
                )
                conn.execute("DELETE FROM sessions WHERE id = ?", (sid,))
                conn.commit()
            clean_payload = {k: v for k, v in payload.items() if k != "activeSessionId"}
            return build_snapshot(conn, clean_payload)

        if cmd == "delete-session":
            sid = int(payload["sessionId"])
            conn.execute(
                "UPDATE todos SET session_id = NULL, state = CASE WHEN state = 1 THEN 0 ELSE state END WHERE session_id = ?",
                (sid,),
            )
            conn.execute("DELETE FROM sessions WHERE id = ?", (sid,))
            conn.commit()
            clean_payload = dict(payload)
            if int(clean_payload.get("activeSessionId") or 0) == sid:
                clean_payload.pop("activeSessionId", None)
            return build_snapshot(conn, clean_payload)

        if cmd == "mark-emergency":
            sid = int(payload["sessionId"])
            conn.execute("UPDATE sessions SET emergency = 1 WHERE id = ?", (sid,))
            conn.commit()
            return build_snapshot(conn, payload)

        if cmd == "set-session-note":
            sid = int(payload["sessionId"])
            note = str(payload.get("note") or "")
            conn.execute("UPDATE sessions SET note = ? WHERE id = ?", (note, sid))
            conn.commit()
            return {"ok": True, "sessionId": sid}

        if cmd == "add-todo":
            raw_title = str(payload.get("title") or "").strip()
            clean_title, sh_prio, sh_time = _extract_task_shorthands(raw_title)
            detail = str(payload.get("detail") or "").strip()
            td_id = str(payload.get("todoistId") or "").strip()
            prio = (
                _clamp_priority(payload["priority"])
                if payload.get("priority") is not None
                else (sh_prio if sh_prio is not None else 1)
            )
            due_time_in = payload.get("dueTime") if payload.get("dueTime") else sh_time
            scope, norm_day, norm_end, norm_time, norm_rec = _normalize_schedule(
                payload.get("scope", "day"),
                payload.get("day"),
                payload.get("endDay", ""),
                due_time_in,
                payload.get("recurrence", ""),
            )
            cat_id = max(0, int(payload.get("categoryId") or 0))
            already_linked = False
            if td_id:
                cur_links = load_todoist_links()
                for r_open in conn.execute(
                    "SELECT id FROM todos WHERE state != 2 OR day = ?", (norm_day,)
                ).fetchall():
                    if cur_links.get(str(r_open["id"]), "") == td_id:
                        already_linked = True
                        break
            if clean_title and not already_linked:
                tcur = conn.execute(
                    """
                    INSERT INTO todos (day, title, detail, state, position, priority, scope, end_day, due_time, recurrence, category_id)
                    VALUES (?, ?, ?, 0, (SELECT IFNULL(MAX(position), 0) + 1 FROM todos WHERE day = ?), ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        norm_day,
                        clean_title,
                        detail,
                        norm_day,
                        prio,
                        scope,
                        norm_end,
                        norm_time,
                        norm_rec,
                        cat_id,
                    ),
                )
                conn.commit()
                if td_id:
                    set_todoist_link(int(tcur.lastrowid), td_id)
            return build_snapshot(conn, payload)

        if cmd == "update-todo":
            tid = int(payload["todoId"])
            existing = conn.execute("SELECT * FROM todos WHERE id = ?", (tid,)).fetchone()
            if existing is not None:
                sh_prio = None
                sh_time = ""
                if "title" in payload:
                    cand_title, sh_prio, sh_time = _extract_task_shorthands(str(payload.get("title") or ""))
                    new_title = cand_title or existing["title"]
                else:
                    new_title = existing["title"]
                new_detail = str(payload["detail"]).strip() if "detail" in payload else (existing["detail"] or "")
                new_prio = (
                    _clamp_priority(payload["priority"])
                    if "priority" in payload and payload["priority"] is not None
                    else (sh_prio if sh_prio is not None else _clamp_priority(existing["priority"]))
                )
                raw_scope = payload.get("scope", existing["scope"] or "day")
                raw_day = payload.get("day", existing["day"])
                raw_end = payload.get("endDay", existing["end_day"] or "")
                raw_time = payload["dueTime"] if "dueTime" in payload else (sh_time or existing["due_time"] or "")
                raw_rec = payload["recurrence"] if "recurrence" in payload else (existing["recurrence"] or "")
                norm_scope, norm_day, norm_end, norm_time, norm_rec = _normalize_schedule(
                    raw_scope, raw_day, raw_end, raw_time, raw_rec
                )
                new_cat = (
                    max(0, int(payload.get("categoryId") or 0))
                    if "categoryId" in payload
                    else int(existing["category_id"] or 0)
                )
                conn.execute(
                    """
                    UPDATE todos
                    SET title = ?, detail = ?, priority = ?, scope = ?, day = ?, end_day = ?, due_time = ?, recurrence = ?, category_id = ?
                    WHERE id = ?
                    """,
                    (
                        new_title,
                        new_detail,
                        new_prio,
                        norm_scope,
                        norm_day,
                        norm_end,
                        norm_time,
                        norm_rec,
                        new_cat,
                        tid,
                    ),
                )
                conn.commit()
            td_meta_now = load_todoist_link_meta()
            active_sid_q = int(payload.get("activeSessionId") or 0)
            active_session_todos = (
                _fetch_session_todos(conn, active_sid_q, td_meta_now, lang=lang) if active_sid_q > 0 else None
            )
            snap = build_snapshot(conn, payload)
            snap["activeSessionTodos"] = active_session_todos
            return snap

        if cmd == "set-todo-state":
            tid = int(payload["todoId"])
            row = conn.execute("SELECT * FROM todos WHERE id = ?", (tid,)).fetchone()
            todo_sid = int(row["session_id"]) if (row is not None and row["session_id"] is not None) else 0
            if row is not None:
                prev_state = int(row["state"])
                if "state" in payload and payload["state"] is not None:
                    next_state = int(payload["state"]) % 3
                else:
                    next_state = (prev_state + 1) % 3
                if next_state == 1 and todo_sid > 0:
                    conn.execute(
                        "UPDATE todos SET state = 0 WHERE session_id = ? AND state = 1 AND id != ?",
                        (todo_sid, tid),
                    )
                conn.execute("UPDATE todos SET state = ? WHERE id = ?", (next_state, tid))

                rec_val = _normalize_recurrence(row["recurrence"])
                spawned_id = int(row["spawned_next_id"] or 0)
                row_scope = str(row["scope"] or "day")
                if prev_state != 2 and next_state == 2 and rec_val and row_scope != "inbox" and spawned_id == 0:
                    n_scope, n_day, n_end = _advance_recurring_schedule(
                        row_scope,
                        str(row["day"] or ""),
                        str(row["end_day"] or ""),
                        rec_val,
                    )
                    ncur = conn.execute(
                        """
                        INSERT INTO todos (day, title, detail, state, session_id, position, priority, scope, end_day, due_time, recurrence, category_id, spawned_next_id)
                        VALUES (?, ?, ?, 0, NULL, (SELECT IFNULL(MAX(position), 0) + 1 FROM todos WHERE day = ?), ?, ?, ?, ?, ?, ?, 0)
                        """,
                        (
                            n_day,
                            row["title"],
                            row["detail"] or "",
                            n_day,
                            _clamp_priority(row["priority"]),
                            n_scope,
                            n_end,
                            _normalize_due_time(row["due_time"]),
                            rec_val,
                            int(row["category_id"] or 0),
                        ),
                    )
                    conn.execute(
                        "UPDATE todos SET spawned_next_id = ? WHERE id = ?",
                        (int(ncur.lastrowid), tid),
                    )
                elif prev_state == 2 and next_state != 2 and spawned_id > 0:
                    sp_row = conn.execute(
                        "SELECT id, state, session_id FROM todos WHERE id = ?",
                        (spawned_id,),
                    ).fetchone()
                    if sp_row is not None and int(sp_row["state"]) == 0 and sp_row["session_id"] is None:
                        conn.execute("DELETE FROM todos WHERE id = ?", (spawned_id,))
                        conn.execute("UPDATE todos SET spawned_next_id = 0 WHERE id = ?", (tid,))

                conn.commit()

            td_meta_now = load_todoist_link_meta()
            session_todos = _fetch_session_todos(conn, todo_sid, td_meta_now, lang=lang) if todo_sid > 0 else []
            active_sid_q = int(payload.get("activeSessionId") or 0)
            active_session_todos = (
                _fetch_session_todos(conn, active_sid_q, td_meta_now, lang=lang) if active_sid_q > 0 else None
            )
            snap = build_snapshot(conn, payload)
            snap["todoSessionId"] = todo_sid
            snap["sessionTodos"] = session_todos
            snap["activeSessionTodos"] = active_session_todos
            snap["todoistSynced"] = False
            return snap

        if cmd == "set-todoist-completed":
            todo_id_opt = int(payload.get("todoId") or 0)
            td_id = str(payload.get("todoistId") or "").strip()
            if not td_id and todo_id_opt > 0:
                td_id = load_todoist_links().get(str(todo_id_opt), "")
            completed = bool(payload.get("completed", True))
            ok_sync, sync_err = sync_todoist_task_completion(td_id, completed, load_settings(), lang)
            if ok_sync:
                if todo_id_opt > 0 and td_id:
                    set_todoist_link(todo_id_opt, td_id, done=completed)
                linked_local_ids = set_todoist_done_by_remote_id(td_id, completed)
                target_ids = set(linked_local_ids) | ({todo_id_opt} if todo_id_opt > 0 else set())
                for ltid in target_ids:
                    if completed:
                        conn.execute("UPDATE todos SET state = 2 WHERE id = ?", (ltid,))
                    else:
                        lrow = conn.execute("SELECT session_id FROM todos WHERE id = ?", (ltid,)).fetchone()
                        if lrow is not None:
                            lsid = int(lrow["session_id"]) if lrow["session_id"] is not None else 0
                            if lsid > 0:
                                has_active = (
                                    conn.execute(
                                        "SELECT 1 FROM todos WHERE session_id = ? AND state = 1 AND id != ? LIMIT 1",
                                        (lsid, ltid),
                                    ).fetchone()
                                    is not None
                                )
                                conn.execute("UPDATE todos SET state = ? WHERE id = ?", (0 if has_active else 1, ltid))
                            else:
                                conn.execute("UPDATE todos SET state = 0 WHERE id = ?", (ltid,))
                if target_ids:
                    conn.commit()

            td_meta_now = load_todoist_link_meta()
            active_sid_q = int(payload.get("activeSessionId") or 0)
            active_session_todos = (
                _fetch_session_todos(conn, active_sid_q, td_meta_now, lang=lang) if active_sid_q > 0 else None
            )
            snap = build_snapshot(conn, payload)
            snap["activeSessionTodos"] = active_session_todos
            snap["todoistSynced"] = ok_sync
            if not ok_sync and sync_err and isinstance(snap.get("todoist"), dict):
                snap["todoist"]["error"] = sync_err
            return snap

        if cmd == "create-todoist-task":
            cur_cfg = load_settings()
            tok = load_todoist_token()
            if not cur_cfg.get("todoistOn") or not tok:
                snap = build_snapshot(conn, payload)
                if isinstance(snap.get("todoist"), dict):
                    snap["todoist"]["error"] = tr_en(
                        lang,
                        "Todoist bağlı değil — önce Ayarlar'dan API anahtarını bağla.",
                        "Todoist is not connected — connect your API token in Settings first.",
                    )
                snap["todoistCreated"] = None
                snap["todoistSynced"] = False
                return snap

            raw_title = str(payload.get("title") or "").strip()
            clean_title, sh_prio, sh_time = _extract_task_shorthands(raw_title)
            if not clean_title:
                snap = build_snapshot(conn, payload)
                snap["todoistCreated"] = None
                snap["todoistSynced"] = False
                return snap

            detail = str(payload.get("detail") or payload.get("description") or "").strip()
            prio = (
                _clamp_priority(payload["priority"])
                if payload.get("priority") is not None
                else (sh_prio if sh_prio is not None else 1)
            )
            due_time_in = payload.get("dueTime") if payload.get("dueTime") else sh_time
            cat_id = max(0, int(payload.get("categoryId") or 0))
            proj_id = _resolve_todoist_project_id(str(payload.get("projectId") or ""), cat_id, conn)

            req_body: dict[str, Any] = {
                "content": clean_title,
                "priority": prio,
            }
            if detail:
                req_body["description"] = detail
            if proj_id:
                req_body["project_id"] = proj_id
            if isinstance(payload.get("labels"), list):
                clean_labels = [str(lb).strip() for lb in payload["labels"] if str(lb).strip()]
                if clean_labels:
                    req_body["labels"] = clean_labels
            req_body.update(
                _build_todoist_due_fields(
                    payload.get("scope", "day"),
                    payload.get("day"),
                    payload.get("endDay", ""),
                    due_time_in,
                    payload.get("recurrence", ""),
                    is_update=False,
                )
            )

            st_code, created_obj, raw_err = _todoist_http("POST", "/tasks", tok, payload=req_body, timeout=6.0)
            if 200 <= st_code < 300 and isinstance(created_obj, dict):
                created_id = str(created_obj.get("id") or "").strip()
                c_obj = _load_todoist_cache()
                c_obj["syncedAt"] = 0.0
                _save_todoist_cache(c_obj)
                snap = build_snapshot(conn, {**payload, "forceTodoistSync": True})
                vis_ids = {str(t.get("id") or "") for t in (snap.get("todoist", {}).get("tasks") or [])}
                snap["todoistCreated"] = {
                    "id": created_id,
                    "title": clean_title,
                    "visibleInFilter": bool(created_id in vis_ids),
                }
                snap["todoistSynced"] = True
                return snap

            err_msg = _todoist_friendly_error(st_code, raw_err, lang, context="write")
            snap = build_snapshot(conn, payload)
            if isinstance(snap.get("todoist"), dict):
                snap["todoist"]["error"] = err_msg
            snap["todoistCreated"] = None
            snap["todoistSynced"] = False
            return snap

        if cmd == "update-todoist-task":
            td_id = str(payload.get("todoistId") or "").strip()
            cur_cfg = load_settings()
            tok = load_todoist_token()
            if not td_id or not cur_cfg.get("todoistOn") or not tok:
                snap = build_snapshot(conn, payload)
                if isinstance(snap.get("todoist"), dict) and (not cur_cfg.get("todoistOn") or not tok):
                    snap["todoist"]["error"] = tr_en(
                        lang,
                        "Todoist bağlı değil — Ayarlar'dan kontrol et.",
                        "Todoist is not connected — check Settings.",
                    )
                snap["todoistUpdated"] = False
                return snap

            req_body = {}
            sh_prio = None
            sh_time = ""
            clean_title = ""
            if "title" in payload:
                clean_title, sh_prio, sh_time = _extract_task_shorthands(str(payload.get("title") or ""))
                if clean_title:
                    req_body["content"] = clean_title
            if "detail" in payload or "description" in payload:
                req_body["description"] = str(payload.get("detail", payload.get("description", "")) or "").strip()
            if "priority" in payload and payload["priority"] is not None:
                req_body["priority"] = _clamp_priority(payload["priority"])
            elif sh_prio is not None:
                req_body["priority"] = sh_prio
            if "projectId" in payload and str(payload.get("projectId") or "").strip():
                req_body["project_id"] = str(payload["projectId"]).strip()

            has_due_patch = any(
                k in payload for k in ("scope", "day", "endDay", "dueTime", "recurrence", "clearDue")
            ) or bool(sh_time)
            if has_due_patch:
                if payload.get("clearDue"):
                    req_body.update({"due_string": "no date", "due_lang": "en"})
                else:
                    req_body.update(
                        _build_todoist_due_fields(
                            payload.get("scope", "day"),
                            payload.get("day"),
                            payload.get("endDay", ""),
                            payload.get("dueTime") if "dueTime" in payload else sh_time,
                            payload.get("recurrence", ""),
                            is_update=True,
                        )
                    )

            encoded_id = urllib.parse.quote(td_id, safe="")
            st_code, _, raw_err = _todoist_http("POST", f"/tasks/{encoded_id}", tok, payload=req_body, timeout=6.0)
            if 200 <= st_code < 300:
                links_map = load_todoist_links()
                linked_local_ids = [int(k) for k, v in links_map.items() if v == td_id and k.isdigit()]
                if linked_local_ids:
                    for ltid in linked_local_ids:
                        if "priority" in req_body:
                            conn.execute("UPDATE todos SET priority = ? WHERE id = ?", (req_body["priority"], ltid))
                        if clean_title:
                            conn.execute("UPDATE todos SET title = ? WHERE id = ?", (clean_title, ltid))
                        if has_due_patch and not payload.get("clearDue"):
                            n_sc, n_d, n_ed, n_tm, n_rc = _normalize_schedule(
                                payload.get("scope", "day"),
                                payload.get("day"),
                                payload.get("endDay", ""),
                                payload.get("dueTime") if "dueTime" in payload else sh_time,
                                payload.get("recurrence", ""),
                            )
                            conn.execute(
                                "UPDATE todos SET scope = ?, day = ?, end_day = ?, due_time = ?, recurrence = ? WHERE id = ?",
                                (n_sc, n_d, n_ed, n_tm, n_rc, ltid),
                            )
                        elif payload.get("clearDue"):
                            conn.execute(
                                "UPDATE todos SET scope = 'inbox', end_day = '', due_time = '', recurrence = '' WHERE id = ?",
                                (ltid,),
                            )
                    conn.commit()
                c_obj = _load_todoist_cache()
                c_obj["syncedAt"] = 0.0
                _save_todoist_cache(c_obj)
                td_meta_now = load_todoist_link_meta()
                active_sid_q = int(payload.get("activeSessionId") or 0)
                active_session_todos = (
                    _fetch_session_todos(conn, active_sid_q, td_meta_now, lang=lang) if active_sid_q > 0 else None
                )
                snap = build_snapshot(conn, {**payload, "forceTodoistSync": True})
                snap["activeSessionTodos"] = active_session_todos
                snap["todoistUpdated"] = True
                return snap

            err_msg = _todoist_friendly_error(st_code, raw_err, lang, context="write")
            snap = build_snapshot(conn, payload)
            if isinstance(snap.get("todoist"), dict):
                snap["todoist"]["error"] = err_msg
            snap["todoistUpdated"] = False
            return snap

        if cmd == "delete-todoist-task":
            td_id = str(payload.get("todoistId") or "").strip()
            cur_cfg = load_settings()
            tok = load_todoist_token()
            if not td_id or not cur_cfg.get("todoistOn") or not tok:
                snap = build_snapshot(conn, payload)
                snap["todoistDeleted"] = False
                return snap
            encoded_id = urllib.parse.quote(td_id, safe="")
            st_code, _, raw_err = _todoist_http("DELETE", f"/tasks/{encoded_id}", tok, timeout=5.0)
            if 200 <= st_code < 300:
                c_obj = _load_todoist_cache()
                if isinstance(c_obj.get("rawTasks"), list):
                    c_obj["rawTasks"] = [t for t in c_obj["rawTasks"] if str(t.get("id", "")) != td_id]
                    _save_todoist_cache(c_obj)
                remove_todoist_links_by_remote_id(td_id)
                snap = build_snapshot(conn, payload)
                snap["todoistDeleted"] = True
                return snap
            err_msg = _todoist_friendly_error(st_code, raw_err, lang, context="write")
            snap = build_snapshot(conn, payload)
            if isinstance(snap.get("todoist"), dict):
                snap["todoist"]["error"] = err_msg
            snap["todoistDeleted"] = False
            return snap

        if cmd == "delete-todo":
            tid = int(payload["todoId"])
            conn.execute("DELETE FROM todos WHERE id = ?", (tid,))
            conn.commit()
            remove_todoist_link(tid)
            td_meta_now = load_todoist_link_meta()
            active_sid_q = int(payload.get("activeSessionId") or 0)
            active_session_todos = (
                _fetch_session_todos(conn, active_sid_q, td_meta_now, lang=lang) if active_sid_q > 0 else None
            )
            snap = build_snapshot(conn, payload)
            snap["activeSessionTodos"] = active_session_todos
            return snap

        if cmd == "add-category":
            name = str(payload.get("name") or tr_en(lang, "Yeni Kategori", "New Category")).strip()
            if not name:
                name = tr_en(lang, "Yeni Kategori", "New Category")
            color = str(payload.get("color") or PALETTE[0]).strip()
            emoji = str(payload.get("emoji") or "").strip() or None
            icon = str(payload.get("icon") or "").strip() or None
            icon_color = str(payload.get("iconColor") or "").strip() or None
            cur = conn.execute(
                """
                INSERT INTO categories (name, color, emoji, icon, position, icon_color)
                VALUES (?, ?, ?, ?, (SELECT IFNULL(MAX(position), 0) + 1 FROM categories), ?)
                """,
                (name, color, emoji, icon, icon_color),
            )
            conn.commit()
            snap = build_snapshot(conn, payload)
            snap["createdCategoryId"] = int(cur.lastrowid)
            return snap

        if cmd == "update-category":
            cid = int(payload["id"])
            existing = conn.execute("SELECT * FROM categories WHERE id = ?", (cid,)).fetchone()
            if existing is not None:
                name = str(payload.get("name", existing["name"])).strip() or existing["name"]
                color = str(payload.get("color", existing["color"])).strip() or existing["color"]
                emoji_raw = payload.get("emoji", existing["emoji"])
                icon_raw = payload.get("icon", existing["icon"])
                ic_raw = payload.get("iconColor", existing["icon_color"])
                emoji = (str(emoji_raw).strip() or None) if emoji_raw is not None else None
                icon = (str(icon_raw).strip() or None) if icon_raw is not None else None
                icon_color = (str(ic_raw).strip() or None) if ic_raw is not None else None
                conn.execute(
                    "UPDATE categories SET name = ?, color = ?, emoji = ?, icon = ?, icon_color = ? WHERE id = ?",
                    (name, color, emoji, icon, icon_color, cid),
                )
                conn.commit()
            return build_snapshot(conn, payload)

        if cmd == "delete-category":
            cid = int(payload["id"])
            cnt = conn.execute("SELECT COUNT(*) AS c FROM categories").fetchone()["c"]
            if cnt > 1:
                conn.execute("DELETE FROM categories WHERE id = ?", (cid,))
                conn.commit()
            return build_snapshot(conn, payload)

        if cmd == "export-csv":
            out_raw = str(payload.get("path") or "").strip()
            if out_raw:
                out_path = Path(out_raw).expanduser()
            else:
                dl = Path.home() / "Downloads"
                if not dl.is_dir():
                    dl = Path.home()
                out_path = dl / f"houra-sessions-{dt.date.today().isoformat()}.csv"
            out_path.parent.mkdir(parents=True, exist_ok=True)

            cats = {int(r["id"]): r["name"] for r in conn.execute("SELECT id, name FROM categories").fetchall()}
            rows = conn.execute(
                """
                SELECT category_id, goal, work_min, rest_min, start, end, focus_sec, emergency, note
                FROM sessions
                ORDER BY start ASC
                """
            ).fetchall()

            with out_path.open("w", encoding="utf-8", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(["start", "end", "category", "goal", "work_min", "rest_min", "focus_min", "emergency", "note"])
                for r in rows:
                    s_iso = dt.datetime.fromtimestamp(float(r["start"])).astimezone().isoformat(timespec="seconds")
                    e_iso = (
                        dt.datetime.fromtimestamp(float(r["end"])).astimezone().isoformat(timespec="seconds")
                        if r["end"] is not None
                        else ""
                    )
                    cname = cats.get(int(r["category_id"]), "")
                    fmin = int(r["focus_sec"]) // 60
                    writer.writerow([
                        s_iso,
                        e_iso,
                        cname,
                        r["goal"],
                        int(r["work_min"]),
                        int(r["rest_min"]),
                        fmin,
                        1 if int(r["emergency"]) else 0,
                        r["note"] or "",
                    ])
            return {"ok": True, "csvPath": str(out_path), "count": len(rows)}

    return {"ok": False, "error": f"Unknown command: {cmd}"}


# ---------------------------------------------------------------------------
# Demo Seeder & Self-Test
# ---------------------------------------------------------------------------

def seed_demo() -> dict[str, Any]:
    lang = resolve_lang(load_settings().get("language", "system"))
    with open_db(lang) as conn:
        conn.executescript("DELETE FROM todos; DELETE FROM sessions; DELETE FROM categories;")
        demo_cats = [
            ("Product", "#4c8df0", None, "rocket-launch", None),
            ("Systems", "#4fc08d", None, "terminal-window", None),
            ("Writing", "#e88b48", None, "note-pencil", None),
            ("Reading", "#a874e8", None, "book-open", None),
        ]
        cat_ids: list[int] = []
        for idx, (name, col, em, ic, ic_col) in enumerate(demo_cats, start=1):
            cur = conn.execute(
                "INSERT INTO categories (name, color, emoji, icon, position, icon_color) VALUES (?, ?, ?, ?, ?, ?)",
                (name, col, em, ic, idx, ic_col),
            )
            cat_ids.append(int(cur.lastrowid))

        goals = {
            cat_ids[0]: ["Release checklist review", "Onboarding flow polish", "Design token cleanup"],
            cat_ids[1]: ["Wayland layer-shell integration", "SQLite query profiling", "Keyboard navigation pass"],
            cat_ids[2]: ["Weekly architecture notes", "Plugin documentation draft"],
            cat_ids[3]: ["Distributed systems chapter", "Paper review notes"],
        }
        rng = random.Random(42)
        today = dt.date.today()
        for days_ago in range(60, -1, -1):
            d = today - dt.timedelta(days=days_ago)
            if days_ago > 0 and rng.random() < 0.22:
                continue
            count = 3 if days_ago == 0 else rng.randint(1, 4)
            hour_cursor = 9.0 + rng.uniform(0, 1.2)
            for s_idx in range(count):
                cid = cat_ids[(days_ago + s_idx) % len(cat_ids)]
                wmin = 50 if rng.random() < 0.68 else 25
                rmin = 10 if wmin == 50 else 5
                fsec = wmin * 60
                start_dt = dt.datetime(d.year, d.month, d.day, 0, 0, 0).astimezone() + dt.timedelta(hours=hour_cursor)
                start_ts = start_dt.timestamp()
                if start_ts + fsec > time.time() and days_ago == 0:
                    start_ts = time.time() - (count - s_idx) * 3900
                end_ts = start_ts + fsec
                goal = rng.choice(goals[cid])
                note = "Clean steady block; zero context switches." if (days_ago % 5 == 0 and s_idx == 0) else ""
                scur = conn.execute(
                    """
                    INSERT INTO sessions (category_id, goal, work_min, rest_min, start, end, focus_sec, note, emergency)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
                    """,
                    (cid, goal, wmin, rmin, start_ts, end_ts, fsec, note),
                )
                sid = int(scur.lastrowid)
                conn.execute(
                    "INSERT INTO todos (day, title, detail, state, session_id, position) VALUES (?, ?, '', 2, ?, ?)",
                    (d.isoformat(), goal, sid, s_idx + 1),
                )
                hour_cursor += (wmin + rmin + rng.randint(10, 35)) / 60.0

        today_extra = [
            ("Finalize Wayland break overlay", "All monitors + hold-to-exit", 2),
            ("Validate manifest schema", "omarchy plugin validate", 1),
            ("Export weekly focus review", "", 0),
        ]
        for idx, (title, detail, st) in enumerate(today_extra, start=10):
            conn.execute(
                "INSERT INTO todos (day, title, detail, state, session_id, position) VALUES (?, ?, ?, ?, NULL, ?)",
                (today.isoformat(), title, detail, st, idx),
            )
        conn.commit()
        return build_snapshot(conn, {})


def run_selftest() -> int:
    with tempfile.TemporaryDirectory() as td:
        os.environ["HOURA_DB"] = os.path.join(td, "test.sqlite")
        os.environ["HOURA_CONFIG"] = os.path.join(td, "settings.json")
        os.environ["HOURA_CACHE_DIR"] = os.path.join(td, "cache")
        os.environ["HOURA_STATE_DIR"] = os.path.join(td, "state")

        snap = handle_command("snapshot", {})
        assert snap["ok"] and len(snap["categories"]) == 1

        cat_res = handle_command(
            "add-category",
            {"name": "Code", "color": "#4fc08d", "icon": "code", "iconColor": "#000000"},
        )
        cid = cat_res["createdCategoryId"]
        assert any(c["id"] == cid and c["icon"] == "code" for c in cat_res["categories"])

        # Weekly markdown test (emoji heading, parent checkbox subgroup, arrow strip)
        md_file = Path(td) / "weekly.md"
        md_file.write_text(
            "# 💻 Code\n"
            "- [ ] Ship Omarchy plugin #code\n"
            "- [w] Waiting on review → [[Reviewer]]\n"
            "- [x] Completed parent task\n"
            "  - [ ] Subtask under checkbox parent ✅ 2026-10-29\n"
            "- [ ] Moved task → Hafta 45\n"
            "- Parent bucket\n"
            "  - [ ] Nested [[Houra|Houra Port]] subtask ✅ 2026-10-29\n",
            encoding="utf-8",
        )
        handle_command("save-settings", {"weeklyOn": True, "weeklyTemplate": str(md_file)})
        snap2 = handle_command("snapshot", {})
        wtasks = snap2["weekly"]["tasks"]
        assert len(wtasks) == 4, f"Expected 4 open weekly tasks, got {wtasks}"
        assert wtasks[0]["categoryId"] == cid
        assert wtasks[1]["waiting"] is True and wtasks[1]["title"] == "Waiting on review"
        assert wtasks[2]["subgroup"] == "Completed parent task" and wtasks[2]["startsSubgroup"] is True
        assert wtasks[3]["subgroup"] == "Parent bucket"
        assert wtasks[3]["title"] == "Nested Houra Port subtask"

        # Session lifecycle + empty goal fallback + custom rhythm
        todo_snap = handle_command("add-todo", {"title": "First task", "detail": "Details"})
        tid = todo_snap["today"]["todos"][0]["id"]
        started = handle_command(
            "start-session",
            {
                "categoryId": cid,
                "goal": "",
                "workMin": 40,
                "restMin": 8,
                "rhythmMode": "custom",
                "customWork": 40,
                "customRest": 8,
                "todoIds": [tid],
                "extraTasks": [{"title": "Second task", "detail": ""}],
            },
        )
        sid = started["startedSession"]["id"]
        assert started["startedSession"]["goal"] == "Code"
        assert started["settings"]["customWork"] == 40 and started["settings"]["customRest"] == 8
        stodos = started["startedSession"]["todos"]
        assert len(stodos) == 2 and stodos[0]["state"] == 1 and stodos[1]["state"] == 0

        # Toggle second task to doing -> first task resets to waiting
        toggled = handle_command("set-todo-state", {"todoId": stodos[1]["id"], "state": 1, "activeSessionId": sid})
        by_id = {t["id"]: t["state"] for t in toggled["activeSessionTodos"]}
        assert by_id[stodos[0]["id"]] == 0 and by_id[stodos[1]["id"]] == 1

        handle_command("set-session-note", {"sessionId": sid, "note": "Great flow"})
        finished = handle_command("finish-session", {"sessionId": sid, "focusSec": 2400})
        assert finished["today"]["focusMinutes"] == 40
        assert finished["today"]["breakMinutes"] == 8

        csv_out = handle_command("export-csv", {"path": os.path.join(td, "out.csv")})
        assert csv_out["ok"] and csv_out["count"] == 1 and Path(csv_out["csvPath"]).is_file()
        assert Path(snap2["chimePath"]).is_file()

        # Multi-horizon + priority + recurrence selftest
        hz_snap = handle_command("add-todo", {"title": "Weekly milestone p1", "scope": "week"})
        assert any(t["title"] == "Weekly milestone" and t["priority"] == 4 for t in hz_snap["today"]["horizons"]["week"])
        ib_snap = handle_command("add-todo", {"title": "Someday idea !!2", "scope": "inbox"})
        assert any(t["title"] == "Someday idea" and t["priority"] == 3 for t in ib_snap["today"]["horizons"]["inbox"])
        rec_snap = handle_command("add-todo", {"title": "Standup @09:30", "recurrence": "daily"})
        rec_todo = next(t for t in rec_snap["today"]["todos"] if t["title"] == "Standup")
        assert rec_todo["dueTime"] == "09:30" and rec_todo["recurrence"] == "daily"
        done_rec = handle_command("set-todo-state", {"todoId": rec_todo["id"], "state": 2})
        assert any(t["title"] == "Standup" and t["day"] > done_rec["today"]["day"] for t in done_rec["today"]["horizons"]["upcoming"])

    print("SELFTEST_OK")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) >= 2 and argv[1] == "--selftest":
        return run_selftest()
    if len(argv) >= 2 and argv[1] == "--demo":
        res = seed_demo()
        sys.stdout.write(json.dumps({"ok": True, "categories": len(res["categories"])}) + "\n")
        return 0

    cmd = argv[1] if len(argv) >= 2 else "snapshot"
    raw_payload = argv[2] if len(argv) >= 3 else "{}"
    if raw_payload == "-":
        raw_payload = sys.stdin.read()
    try:
        payload = json.loads(raw_payload) if raw_payload else {}
        if not isinstance(payload, dict):
            payload = {}
    except Exception:
        payload = {}

    try:
        result = handle_command(cmd, payload)
    except Exception as exc:
        result = {"ok": False, "error": str(exc)}

    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
    sys.stdout.flush()
    return 0 if result.get("ok", False) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
