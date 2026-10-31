import datetime as dt
import http.server
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import threading
import unittest
import wave

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "backend" / "houra_cli.py"


class HouraBackendAndMarketplaceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.env = os.environ.copy()
        self.env["HOURA_DB"] = os.path.join(self.tmp.name, "houra.sqlite")
        self.env["HOURA_CONFIG"] = os.path.join(self.tmp.name, "settings.json")
        self.env["HOURA_CACHE_DIR"] = os.path.join(self.tmp.name, "cache")
        self.env["HOURA_STATE_DIR"] = os.path.join(self.tmp.name, "state")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def rpc(self, cmd: str, payload: dict | None = None, via_stdin: bool = False) -> dict:
        args = ["python3", str(CLI), cmd, "-" if via_stdin else json.dumps(payload or {})]
        proc = subprocess.run(
            args,
            env=self.env,
            input=(json.dumps(payload or {}) + "\n") if via_stdin else None,
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads(proc.stdout.strip())

    def test_sqlite_schema_and_session_lifecycle(self) -> None:
        snap = self.rpc("snapshot")
        self.assertTrue(snap["ok"])
        self.assertEqual(len(snap["categories"]), 1)

        # Chime WAV validity (4.0s mono 44.1kHz 16-bit)
        chime = Path(snap["chimePath"])
        self.assertTrue(chime.is_file())
        with wave.open(str(chime), "rb") as wf:
            self.assertEqual(wf.getnchannels(), 1)
            self.assertEqual(wf.getsampwidth(), 2)
            self.assertEqual(wf.getframerate(), 44100)
            self.assertEqual(wf.getnframes(), 44100 * 4)

        # Category CRUD + custom icon color
        added = self.rpc(
            "add-category",
            {"name": "Systems", "color": "#4fc08d", "icon": "terminal-window", "iconColor": "#000000"},
        )
        cid = added["createdCategoryId"]
        self.assertEqual(len(added["categories"]), 2)

        # Add todos and start session (custom rhythm + monitor pinning without lastWidgetScreen)
        t1 = self.rpc("add-todo", {"title": "Build layer-shell widget", "detail": "Region mask"})["today"]["todos"][0]["id"]
        unattached = self.rpc("add-todo", {"title": "Independent Today task", "detail": ""})["today"]["todos"][-1]["id"]
        started = self.rpc(
            "start-session",
            {
                "categoryId": cid,
                "goal": "Omarchy integration",
                "workMin": 40,
                "restMin": 8,
                "rhythmMode": "custom",
                "customWork": 40,
                "customRest": 8,
                "todoIds": [t1],
                "extraTasks": [{"title": "Verify qmllint", "detail": ""}],
            },
        )
        self.assertNotIn("lastWidgetScreen", started["settings"])
        self.assertEqual(started["settings"]["rhythmMode"], "custom")
        self.assertEqual(started["settings"]["customWork"], 40)
        self.assertEqual(started["settings"]["customRest"], 8)
        pinned = self.rpc("save-settings", {"widgetScreen": "eDP-1"})
        self.assertEqual(pinned["settings"]["widgetScreen"], "eDP-1")
        sess = started["startedSession"]
        self.assertEqual(len(sess["todos"]), 2)
        self.assertEqual(sess["todos"][0]["state"], 1)  # first task auto-set to doing
        self.assertEqual(sess["todos"][1]["state"], 0)

        # Setting second task to doing resets first task to waiting
        toggled = self.rpc("set-todo-state", {"todoId": sess["todos"][1]["id"], "state": 1, "activeSessionId": sess["id"]})
        states = {t["id"]: t["state"] for t in toggled["activeSessionTodos"]}
        self.assertEqual(states[sess["todos"][0]["id"]], 0)
        self.assertEqual(states[sess["todos"][1]["id"]], 1)

        # Toggling an unattached Today todo must not wipe activeSessionTodos
        toggled_other = self.rpc("set-todo-state", {"todoId": unattached, "state": 2, "activeSessionId": sess["id"]})
        self.assertEqual(len(toggled_other["activeSessionTodos"]), 2)

        # Save note, finish session, verify breakMinutes, then mark emergency
        self.rpc("set-session-note", {"sessionId": sess["id"], "note": "Zero warnings"})
        fin = self.rpc("finish-session", {"sessionId": sess["id"], "focusSec": 2400})
        self.assertEqual(fin["today"]["focusMinutes"], 40)
        self.assertEqual(fin["today"]["breakMinutes"], 8)

        em = self.rpc("mark-emergency", {"sessionId": sess["id"]})
        self.assertEqual(em["today"]["emergencyCount"], 1)
        self.assertEqual(em["today"]["breakMinutes"], 0)

        # Starting a new session with empty goal falls back to category name, and starting a third auto-closes the second
        second = self.rpc("start-session", {"categoryId": cid, "goal": "", "workMin": 50, "restMin": 10})
        self.assertEqual(second["startedSession"]["goal"], "Systems")
        second_id = second["startedSession"]["id"]
        third = self.rpc("start-session", {"categoryId": snap["categories"][0]["id"], "goal": "Deep reading", "workMin": 25, "restMin": 5})
        third_id = third["startedSession"]["id"]
        self.rpc("finish-session", {"sessionId": third_id, "focusSec": 1500})

        # Unfiltered stats.categoryBreakdown + unfiltered DayDrawer data even when statsTopicId filter is set
        filtered_snap = self.rpc("snapshot", {"statsTopicId": cid})
        self.assertGreaterEqual(len(filtered_snap["stats"]["categoryBreakdown"]), 2)
        today_cell = next(d for d in filtered_snap["stats"]["days"] if d["day"] == filtered_snap["today"]["day"])
        self.assertGreater(today_cell["allTotalMinutes"], today_cell["totalMinutes"])

        csv_path = os.path.join(self.tmp.name, "export.csv")
        exp = self.rpc("export-csv", {"path": csv_path})
        self.assertEqual(exp["count"], 3)
        content = Path(csv_path).read_text(encoding="utf-8")
        self.assertIn("Omarchy integration", content)
        self.assertIn("Zero warnings", content)
        self.assertLess(content.index("Omarchy integration"), content.index("Deep reading"))

        # Cancel an active session without saving: detaches todos back to waiting & removes session
        reusable_todo = self.rpc("add-todo", {"title": "Keep me on cancel", "detail": ""})["today"]["todos"][-1]["id"]
        accidental = self.rpc(
            "start-session",
            {"categoryId": cid, "goal": "Accidental start", "workMin": 25, "restMin": 5, "todoIds": [reusable_todo]},
        )
        acc_id = accidental["startedSession"]["id"]
        self.assertEqual(accidental["startedSession"]["todos"][0]["state"], 1)
        cancelled = self.rpc("cancel-session", {"sessionId": acc_id})
        recovered = next(t for t in cancelled["today"]["todos"] if t["id"] == reusable_todo)
        self.assertEqual(recovered["sessionId"], 0)
        self.assertEqual(recovered["state"], 0)
        self.assertEqual(self.rpc("export-csv", {"path": csv_path})["count"], 3)

        # Delete a past recorded session: removes from history, stats, today, and CSV
        deleted = self.rpc("delete-session", {"sessionId": third_id})
        self.assertEqual(self.rpc("export-csv", {"path": csv_path})["count"], 2)
        all_hist_ids = [s["id"] for grp in deleted["history"] for s in grp["sessions"]]
        self.assertNotIn(third_id, all_hist_ids)

    def test_private_history_database_modes(self) -> None:
        # Session notes, goals and tasks must not be readable by other local accounts (umask 022 default)
        data_home = Path(self.tmp.name) / "xdg-data"
        env = dict(self.env)
        env.pop("HOURA_DB")
        env["XDG_DATA_HOME"] = str(data_home)
        folder = data_home / "houra"
        db = folder / "houra.sqlite"

        def mode(path: Path) -> int:
            return stat.S_IMODE(path.stat().st_mode)

        def run(cmd: str, payload: dict) -> None:
            subprocess.run(["python3", str(CLI), cmd, json.dumps(payload)], env=env, check=True,
                           capture_output=True, preexec_fn=lambda: os.umask(0o022))

        run("start-session", {"categoryId": 1, "goal": "private goal", "workMinutes": 25, "breakMinutes": 5})
        self.assertEqual(mode(folder), 0o700)
        self.assertEqual(mode(db), 0o600)
        for side in ("-wal", "-shm"):
            side_path = Path(str(db) + side)
            if side_path.exists():
                self.assertEqual(mode(side_path), 0o600, side)

        # An install created before this fix (0755 folder, 0644 files) is tightened on the next open
        os.chmod(folder, 0o755)
        os.chmod(db, 0o644)
        run("snapshot", {})
        self.assertEqual(mode(folder), 0o700)
        self.assertEqual(mode(db), 0o600)

    def test_text_items_never_render_rich_text(self) -> None:
        # Task titles and notes can come from Todoist or Markdown; AutoText would render HTML and fetch <img> URLs
        missing = []
        for path in sorted(ROOT.rglob("*.qml")):
            if "media" in path.parts or "node_modules" in path.parts:
                continue
            lines = path.read_text().split("\n")
            for i, line in enumerate(lines):
                if re.search(r"(^|[^A-Za-z.])(Text|TextEdit) \{", line):
                    window = line + "".join(lines[i + 1:i + 3])
                    if "PlainText" not in window:
                        missing.append(f"{path.relative_to(ROOT)}:{i + 1}")
        self.assertEqual(missing, [], "Text items without textFormat PlainText")

    def test_weekly_markdown_wildcard_and_obsidian_syntax(self) -> None:
        vault = Path(self.tmp.name) / "200-Weekly"
        vault.mkdir()
        cat_res = self.rpc("add-category", {"name": "Project", "color": "#e88b48"})
        cid = cat_res["createdCategoryId"]

        import datetime as dt
        today = dt.date.today()
        iso_y, iso_w, _ = today.isocalendar()
        month_str = f"{today.month:02d}"
        older = vault / f"{iso_y:04d}-{month_str}-W{iso_w:02d}-old.md"
        older.write_text("# Projects\n- [ ] Older file\n", encoding="utf-8")
        os.utime(older, (1700000000, 1700000000))

        md = vault / f"{iso_y:04d}-{month_str}-W{iso_w:02d}-latest.md"
        md.write_text(
            "# 🚀 Projects\n"
            "- [ ] Prepare [[Marketplace|Omarchy Marketplace]] release\n"
            "  - [ ] Verify automated security baseline\n"
            "- [w] Waiting on review\n"
            "- [x] Completed item\n"
            "- [ ] Deferred item → Hafta 49\n"
            "- UI Polish\n"
            "  - [/] Test multi-monitor DriftingLights ✅ 2026-10-29\n",
            encoding="utf-8",
        )
        tmpl = str(Path(self.tmp.name) / "*-Weekly" / "{YYYY}-{MM}-W{WW}-*.md")
        snap = self.rpc("save-settings", {"weeklyOn": True, "weeklyTemplate": tmpl})
        wk = snap["weekly"]
        self.assertTrue(wk["exists"])
        self.assertTrue(wk["resolvedPath"].endswith("-latest.md"))
        self.assertEqual(wk["openCount"], 4)
        self.assertEqual(wk["tasks"][0]["categoryId"], cid)
        self.assertEqual(wk["tasks"][0]["title"], "Prepare Omarchy Marketplace release")
        self.assertEqual(wk["tasks"][1]["subgroup"], "Prepare Omarchy Marketplace release")
        self.assertTrue(wk["tasks"][1]["startsSubgroup"])
        self.assertTrue(wk["tasks"][2]["waiting"])
        self.assertEqual(wk["tasks"][3]["subgroup"], "UI Polish")

    def test_todoist_two_way_sync_and_private_token_storage(self) -> None:
        events: dict[str, list[str]] = {"gets": [], "closed": [], "reopened": [], "auth": []}
        expected_token = "td_secret_mock_token_9911"
        second_token = "td_work_account_token_2200"

        class MockTodoistHandler(http.server.BaseHTTPRequestHandler):
            def log_message(self, fmt: str, *args: object) -> None:
                return

            def do_GET(self) -> None:
                events["gets"].append(self.path)
                auth_hdr = self.headers.get("Authorization", "")
                events["auth"].append(auth_hdr)
                if auth_hdr not in (f"Bearer {expected_token}", f"Bearer {second_token}"):
                    self.send_response(401)
                    self.end_headers()
                    return
                is_second = auth_hdr == f"Bearer {second_token}"
                if self.path == "/api/v1/user":
                    body = (
                        {"full_name": "Work Account", "email": "work@example.com"}
                        if is_second
                        else {"full_name": "Focus Dev", "email": "focus@example.com"}
                    )
                elif self.path.startswith("/api/v1/projects"):
                    body = {
                        "results": [
                            {"id": "proj_sys", "name": "Systems"},
                            {"id": "proj_inb", "name": "Inbox"},
                        ],
                        "next_cursor": None,
                    }
                elif self.path.startswith("/api/v1/tasks/filter") or self.path.startswith("/api/v1/tasks"):
                    body = (
                        {
                            "results": [
                                {
                                    "id": "t_200",
                                    "content": "Review work sprint",
                                    "project_id": "proj_sys",
                                    "priority": 3,
                                }
                            ],
                            "next_cursor": None,
                        }
                        if is_second
                        else {
                            "results": [
                                {
                                    "id": "t_100",
                                    "content": "Ship Todoist integration",
                                    "project_id": "proj_sys",
                                    "priority": 4,
                                    "labels": ["deep"],
                                    "due": {"date": "2020-01-01", "string": "Jan 1"},
                                },
                                {
                                    "id": "t_101",
                                    "content": "Triage weekly inbox",
                                    "project_id": "proj_inb",
                                    "priority": 1,
                                },
                            ],
                            "next_cursor": None,
                        }
                    )
                else:
                    self.send_response(404)
                    self.end_headers()
                    return
                raw = json.dumps(body).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_POST(self) -> None:
                events["auth"].append(self.headers.get("Authorization", ""))
                if self.path in ("/api/v1/tasks/t_100/close", "/api/v1/tasks/t_101/close"):
                    tid_closed = self.path.split("/")[4]
                    events["closed"].append(tid_closed)
                    self.send_response(204)
                    self.end_headers()
                    return
                if self.path in ("/api/v1/tasks/t_100/reopen", "/api/v1/tasks/t_101/reopen"):
                    tid_reopened = self.path.split("/")[4]
                    events["reopened"].append(tid_reopened)
                    self.send_response(204)
                    self.end_headers()
                    return
                self.send_response(404)
                self.end_headers()

        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), MockTodoistHandler)
        thread = threading.Thread(target=srv.serve_forever, daemon=True)
        thread.start()
        try:
            self.env["HOURA_TODOIST_API_BASE"] = f"http://127.0.0.1:{srv.server_port}/api/v1"

            # 1. Offline-first by default: zero HTTP requests when Todoist is disabled
            cid = self.rpc("add-category", {"name": "Systems", "color": "#4fc08d"}, via_stdin=True)["createdCategoryId"]
            initial = self.rpc("snapshot", via_stdin=True)
            self.assertFalse(initial["todoist"]["enabled"])
            self.assertFalse(initial["todoist"]["hasToken"])
            self.assertNotIn("omarchyTokenAvailable", initial["todoist"])
            self.assertEqual(len(events["gets"]), 0)

            # 2. Invalid Todoist website API key is rejected without writing token file
            token_file = Path(self.env["HOURA_STATE_DIR"]) / "todoist_token"
            rejected = self.rpc("save-todoist-token", {"token": "wrong_api_key"}, via_stdin=True)
            self.assertFalse(rejected["todoistSynced"])
            self.assertFalse(rejected["todoist"]["hasToken"])
            self.assertTrue(bool(rejected["todoist"]["error"]))
            self.assertFalse(token_file.exists())

            # 3. Direct connection with personal Todoist website API key + 0600 private storage + account label
            connected = self.rpc("save-todoist-token", {"token": expected_token}, via_stdin=True)
            self.assertTrue(connected["todoistSynced"])
            self.assertTrue(connected["todoist"]["enabled"])
            self.assertTrue(connected["todoist"]["hasToken"])
            self.assertEqual(connected["todoist"]["account"], "Focus Dev · focus@example.com")
            self.assertEqual(connected["todoist"]["openCount"], 2)

            self.assertTrue(token_file.is_file())
            self.assertEqual(stat.S_IMODE(token_file.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(Path(self.env["HOURA_STATE_DIR"]).stat().st_mode), 0o700)
            self.assertNotIn(expected_token, Path(self.env["HOURA_CONFIG"]).read_text(encoding="utf-8"))
            self.assertNotIn(expected_token, json.dumps(connected))

            # Category matching (#Systems -> Systems category) + overdue sorting
            t0 = connected["todoist"]["tasks"][0]
            self.assertEqual(t0["id"], "t_100")
            self.assertEqual(t0["categoryId"], cid)
            self.assertTrue(t0["isOverdue"])
            self.assertEqual(t0["priority"], 4)

            # 4. 90s cache prevents redundant network requests on normal snapshots
            gets_after_connect = len(events["gets"])
            cached_snap = self.rpc("snapshot", via_stdin=True)
            self.assertEqual(cached_snap["todoist"]["openCount"], 2)
            self.assertEqual(len(events["gets"]), gets_after_connect)

            # 4. Deduplicated pull into Today's to-do
            pulled1 = self.rpc("add-todo", {"title": "Triage weekly inbox", "detail": "#Inbox", "todoistId": "t_101"}, via_stdin=True)
            pulled2 = self.rpc("add-todo", {"title": "Triage weekly inbox", "detail": "#Inbox", "todoistId": "t_101"}, via_stdin=True)
            t101_rows = [t for t in pulled2["today"]["todos"] if t["todoistId"] == "t_101"]
            self.assertEqual(len(t101_rows), 1)
            self.assertEqual(len(pulled1["today"]["todos"]), len(pulled2["today"]["todos"]))

            # 5. Decoupled session lifecycle & explicit Todoist task completion:
            #    Local emoji state (🥳) and session finish/close NEVER auto-complete Todoist tasks.
            started = self.rpc(
                "start-session",
                {
                    "categoryId": cid,
                    "goal": "Todoist block",
                    "workMin": 25,
                    "restMin": 5,
                    "extraTasks": [{"title": "Ship Todoist integration", "detail": "#Systems · Jan 1", "todoistId": "t_100"}],
                },
                via_stdin=True,
            )
            sess_id = started["startedSession"]["id"]
            sess_todo = started["startedSession"]["todos"][0]
            self.assertEqual(sess_todo["todoistId"], "t_100")
            self.assertFalse(sess_todo["todoistDone"])
            self.assertEqual(sess_todo["state"], 1)

            local_done = self.rpc(
                "set-todo-state",
                {"todoId": sess_todo["id"], "state": 2, "activeSessionId": sess_id},
                via_stdin=True,
            )
            self.assertFalse(local_done["todoistSynced"])
            self.assertEqual(events["closed"], [])

            # Explicit Todoist completion while session is still running
            explicit_close = self.rpc(
                "set-todoist-completed",
                {"todoId": sess_todo["id"], "todoistId": "t_100", "completed": True, "activeSessionId": sess_id},
                via_stdin=True,
            )
            self.assertTrue(explicit_close["todoistSynced"])
            self.assertEqual(events["closed"], ["t_100"])
            self.assertEqual(explicit_close["todoist"]["openCount"], 1)
            self.assertTrue(explicit_close["activeSessionTodos"][0]["todoistDone"])
            self.assertEqual(explicit_close["activeSessionTodos"][0]["state"], 2)

            # Reopening explicitly restores Todoist open state and active session state
            explicit_reopen = self.rpc(
                "set-todoist-completed",
                {"todoId": sess_todo["id"], "todoistId": "t_100", "completed": False, "activeSessionId": sess_id},
                via_stdin=True,
            )
            self.assertTrue(explicit_reopen["todoistSynced"])
            self.assertEqual(events["reopened"], ["t_100"])
            self.assertFalse(explicit_reopen["activeSessionTodos"][0]["todoistDone"])
            self.assertEqual(explicit_reopen["activeSessionTodos"][0]["state"], 1)

            # Closing session early without break (`skipBreak: True`) saves focus time without break/emergency inflation or closing Todoist
            closed_no_break = self.rpc(
                "finish-session",
                {"sessionId": sess_id, "focusSec": 900, "skipBreak": True, "activeSessionId": sess_id},
                via_stdin=True,
            )
            self.assertEqual(closed_no_break["today"]["focusMinutes"], 15)
            self.assertEqual(closed_no_break["today"]["breakMinutes"], 0)
            self.assertEqual(closed_no_break["today"]["breaksCount"], 0)
            self.assertEqual(closed_no_break["today"]["emergencyCount"], 0)
            self.assertEqual(events["closed"], ["t_100"])

            # Direct completion from the Todoist card (`todoId: 0`) closes t_101 and updates linked Today row
            direct_card_close = self.rpc(
                "set-todoist-completed",
                {"todoId": 0, "todoistId": "t_101", "completed": True},
                via_stdin=True,
            )
            self.assertTrue(direct_card_close["todoistSynced"])
            self.assertEqual(events["closed"], ["t_100", "t_101"])
            t101_after = [t for t in direct_card_close["today"]["todos"] if t["todoistId"] == "t_101"][0]
            self.assertTrue(t101_after["todoistDone"])
            self.assertEqual(t101_after["state"], 2)

            # 6. Switching to another Todoist account's API key replaces account & clears old cache
            switched = self.rpc("save-todoist-token", {"token": second_token}, via_stdin=True)
            self.assertTrue(switched["todoistSynced"])
            self.assertEqual(switched["todoist"]["account"], "Work Account · work@example.com")
            self.assertEqual(switched["todoist"]["openCount"], 1)
            self.assertEqual(switched["todoist"]["tasks"][0]["id"], "t_200")
            self.assertNotIn(second_token, json.dumps(switched))

            # 7. Disconnect removes private token file and turns off sync
            cleared = self.rpc("clear-todoist-token", {}, via_stdin=True)
            self.assertFalse(cleared["todoist"]["hasToken"])
            self.assertFalse(cleared["todoist"]["enabled"])
            self.assertFalse(token_file.exists())
        finally:
            srv.shutdown()
            srv.server_close()

    def test_multi_horizon_planner_priorities_recurrence_and_todoist_crud(self) -> None:
        today = dt.date.today()
        today_iso = today.isoformat()
        yesterday_iso = (today - dt.timedelta(days=1)).isoformat()
        in_5_days_iso = (today + dt.timedelta(days=5)).isoformat()
        in_9_days_iso = (today + dt.timedelta(days=9)).isoformat()

        cid = self.rpc("add-category", {"name": "Research", "color": "#a78bfa"}, via_stdin=True)["createdCategoryId"]

        # 1. Shorthand extraction (`p1`, `@HH:MM`) + priority sorting + overdue rollover
        self.rpc("add-todo", {"title": "Normal task"}, via_stdin=True)
        self.rpc("add-todo", {"title": "Ship release p1 @14:30", "categoryId": cid}, via_stdin=True)
        self.rpc("add-todo", {"title": "Yesterday overdue", "day": yesterday_iso, "priority": 2}, via_stdin=True)

        # 2. Multi-horizon tasks: week, month, custom range, and undated inbox
        self.rpc("add-todo", {"title": "Weekly milestone", "scope": "week", "day": today_iso, "priority": 3}, via_stdin=True)
        self.rpc("add-todo", {"title": "Monthly paper draft", "scope": "month", "day": today_iso, "priority": 4}, via_stdin=True)
        self.rpc(
            "add-todo",
            {"title": "Sprint window", "scope": "range", "day": in_5_days_iso, "endDay": in_9_days_iso, "priority": 2},
            via_stdin=True,
        )
        snap = self.rpc(
            "add-todo",
            {"title": "Someday backlog idea", "scope": "inbox", "priority": 3, "categoryId": cid},
            via_stdin=True,
        )

        # Overdue rolls to top of Today, followed by P1 (`priority == 4`) before P4 (`priority == 1`)
        today_list = snap["today"]["todos"]
        self.assertEqual(today_list[0]["title"], "Yesterday overdue")
        self.assertTrue(today_list[0]["isPastDue"])
        self.assertEqual(today_list[1]["title"], "Ship release")
        self.assertEqual(today_list[1]["priority"], 4)
        self.assertEqual(today_list[1]["dueTime"], "14:30")
        self.assertEqual(today_list[1]["categoryId"], cid)
        self.assertEqual(today_list[2]["title"], "Normal task")

        horizons = snap["today"]["horizons"]
        self.assertTrue(any(t["title"] == "Weekly milestone" and t["scope"] == "week" for t in horizons["week"]))
        self.assertTrue(any(t["title"] == "Monthly paper draft" and t["scope"] == "month" for t in horizons["month"]))
        self.assertTrue(any(t["title"] == "Sprint window" and t["scope"] == "range" for t in horizons["upcoming"]))
        self.assertTrue(any(t["title"] == "Someday backlog idea" and t["scope"] == "inbox" for t in horizons["inbox"]))
        planned_titles = [t["title"] for t in horizons["openPlanned"]]
        for expected_planned in ("Weekly milestone", "Monthly paper draft", "Sprint window", "Someday backlog idea"):
            self.assertIn(expected_planned, planned_titles)

        # 3. Updating a local task's schedule/priority + recurring task advancement & undo cleanup
        rec_added = self.rpc(
            "add-todo",
            {"title": "Daily standup", "scope": "day", "day": today_iso, "dueTime": "09:15", "recurrence": "daily", "priority": 3},
            via_stdin=True,
        )
        rec_row = [t for t in rec_added["today"]["todos"] if t["title"] == "Daily standup"][0]
        updated = self.rpc(
            "update-todo",
            {"todoId": rec_row["id"], "priority": 4, "dueTime": "09:30"},
            via_stdin=True,
        )
        rec_row_upd = [t for t in updated["today"]["todos"] if t["id"] == rec_row["id"]][0]
        self.assertEqual(rec_row_upd["priority"], 4)
        self.assertEqual(rec_row_upd["dueTime"], "09:30")

        completed_rec = self.rpc("set-todo-state", {"todoId": rec_row["id"], "state": 2}, via_stdin=True)
        tomorrow_iso = (today + dt.timedelta(days=1)).isoformat()
        next_occurrences = [
            t for t in completed_rec["today"]["horizons"]["upcoming"]
            if t["title"] == "Daily standup" and t["day"] == tomorrow_iso and t["state"] == 0
        ]
        self.assertEqual(len(next_occurrences), 1)
        self.assertEqual(next_occurrences[0]["priority"], 4)
        self.assertEqual(next_occurrences[0]["dueTime"], "09:30")

        # Undoing completion removes the untouched spawned next occurrence instead of duplicating
        undone_rec = self.rpc("set-todo-state", {"todoId": rec_row["id"], "state": 0}, via_stdin=True)
        after_undo = [
            t for t in undone_rec["today"]["horizons"]["upcoming"]
            if t["title"] == "Daily standup" and t["day"] == tomorrow_iso
        ]
        self.assertEqual(len(after_undo), 0)

        # 4. 2-way Todoist task creation, editing, deletion, and New Session `+ Todoist` sync (Free-plan safe)
        td_token = "td_crud_token_789"
        remote_tasks: dict[str, dict] = {}
        captured_posts: list[tuple[str, dict]] = []
        deleted_ids: list[str] = []

        class MockTodoistCrudHandler(http.server.BaseHTTPRequestHandler):
            def log_message(self, fmt: str, *args) -> None:
                return

            def _send_json(self, code: int, obj: dict) -> None:
                raw = json.dumps(obj).encode("utf-8")
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_GET(self) -> None:
                if self.headers.get("Authorization") != f"Bearer {td_token}":
                    self.send_response(401)
                    self.end_headers()
                    return
                if self.path.startswith("/api/v1/user"):
                    self._send_json(200, {"full_name": "Planner User", "email": "plan@example.com"})
                elif self.path.startswith("/api/v1/projects"):
                    self._send_json(
                        200,
                        {
                            "results": [
                                {"id": "p_inb", "name": "Inbox", "inbox_project": True},
                                {"id": "p_res", "name": "Research"},
                            ],
                            "next_cursor": None,
                        },
                    )
                elif self.path.startswith("/api/v1/tasks"):
                    self._send_json(200, {"results": list(remote_tasks.values()), "next_cursor": None})
                else:
                    self.send_response(404)
                    self.end_headers()

            def do_POST(self) -> None:
                if self.headers.get("Authorization") != f"Bearer {td_token}":
                    self.send_response(401)
                    self.end_headers()
                    return
                clen = int(self.headers.get("Content-Length") or "0")
                payload = json.loads(self.rfile.read(clen).decode("utf-8")) if clen > 0 else {}
                captured_posts.append((self.path, payload))
                # Free-plan Todoist accounts reject Pro-only deadline_date and duration with HTTP 400
                if "deadline_date" in payload or "duration" in payload:
                    self._send_json(400, {"error": "Pro-only field rejected"})
                    return
                if self.path == "/api/v1/tasks":
                    new_id = f"td_new_{len(remote_tasks) + 1}"
                    due_obj = None
                    if payload.get("due_date"):
                        due_obj = {"date": payload["due_date"], "is_recurring": False}
                    elif payload.get("due_datetime"):
                        due_obj = {"date": payload["due_datetime"], "datetime": payload["due_datetime"], "is_recurring": False}
                    elif payload.get("due_string") and payload.get("due_string") != "no date":
                        due_obj = {"date": today_iso, "string": payload["due_string"], "is_recurring": "every" in payload["due_string"]}
                    created = {
                        "id": new_id,
                        "content": payload.get("content", ""),
                        "description": payload.get("description", ""),
                        "priority": int(payload.get("priority", 1)),
                        "project_id": payload.get("project_id", "p_inb"),
                        "due": due_obj,
                    }
                    remote_tasks[new_id] = created
                    self._send_json(200, created)
                    return
                if self.path.startswith("/api/v1/tasks/"):
                    tid_edit = self.path.split("/")[4]
                    item = remote_tasks.get(tid_edit)
                    if not item:
                        self.send_response(404)
                        self.end_headers()
                        return
                    if "priority" in payload:
                        item["priority"] = int(payload["priority"])
                    if "content" in payload:
                        item["content"] = payload["content"]
                    if payload.get("due_string") == "no date":
                        item["due"] = None
                    elif payload.get("due_date"):
                        item["due"] = {"date": payload["due_date"], "is_recurring": False}
                    elif payload.get("due_datetime"):
                        item["due"] = {"date": payload["due_datetime"], "datetime": payload["due_datetime"], "is_recurring": False}
                    elif payload.get("due_string"):
                        item["due"] = {"date": today_iso, "string": payload["due_string"], "is_recurring": "every" in payload["due_string"]}
                    self._send_json(200, item)
                    return
                self.send_response(404)
                self.end_headers()

            def do_DELETE(self) -> None:
                if self.headers.get("Authorization") != f"Bearer {td_token}":
                    self.send_response(401)
                    self.end_headers()
                    return
                if self.path.startswith("/api/v1/tasks/"):
                    tid_del = self.path.split("/")[4]
                    deleted_ids.append(tid_del)
                    remote_tasks.pop(tid_del, None)
                    self.send_response(204)
                    self.end_headers()
                    return
                self.send_response(404)
                self.end_headers()

        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), MockTodoistCrudHandler)
        thread = threading.Thread(target=srv.serve_forever, daemon=True)
        thread.start()
        try:
            self.env["HOURA_TODOIST_API_BASE"] = f"http://127.0.0.1:{srv.server_port}/api/v1"
            conn_snap = self.rpc("save-todoist-token", {"token": td_token}, via_stdin=True)
            self.assertTrue(conn_snap["todoistSynced"])
            proj_ids = {p["name"]: p["id"] for p in conn_snap["todoist"]["projects"]}
            self.assertEqual(proj_ids.get("Research"), "p_res")

            # Create Todoist task with P1 shorthand, @16:00 time, weekly recurrence, and category->project auto-match
            created_td = self.rpc(
                "create-todoist-task",
                {
                    "title": "Review benchmark table p1 @16:00",
                    "detail": "Check latency percentiles",
                    "scope": "week",
                    "day": today_iso,
                    "recurrence": "weekly",
                    "categoryId": cid,
                },
                via_stdin=True,
            )
            self.assertTrue(created_td["todoistSynced"])
            self.assertEqual(created_td["todoistCreated"]["id"], "td_new_1")
            self.assertTrue(created_td["todoistCreated"]["visibleInFilter"])
            self.assertEqual(created_td["todoist"]["openCount"], 1)
            td_task = created_td["todoist"]["tasks"][0]
            self.assertEqual(td_task["title"], "Review benchmark table")
            self.assertEqual(td_task["priority"], 4)
            self.assertEqual(td_task["projectId"], "p_res")
            self.assertTrue(td_task["isRecurring"])

            # Update Todoist task priority & clear due date ("inbox" -> due_string: "no date")
            edited_td = self.rpc(
                "update-todoist-task",
                {"todoistId": "td_new_1", "priority": 2, "scope": "inbox"},
                via_stdin=True,
            )
            self.assertTrue(edited_td["todoistUpdated"])
            self.assertEqual(edited_td["todoist"]["tasks"][0]["priority"], 2)
            self.assertEqual(edited_td["todoist"]["tasks"][0]["dueDate"], "")

            # Start session attaching a planned local task + creating a new task on Todoist at the same time
            inbox_local_id = [t["id"] for t in edited_td["today"]["horizons"]["inbox"] if t["title"] == "Someday backlog idea"][0]
            sess_started = self.rpc(
                "start-session",
                {
                    "categoryId": cid,
                    "goal": "Deep research",
                    "workMin": 25,
                    "restMin": 5,
                    "todoIds": [inbox_local_id],
                    "extraTasks": [{"title": "Draft conclusion", "priority": 3, "categoryId": cid, "createOnTodoist": True}],
                },
                via_stdin=True,
            )
            s_todos = sess_started["startedSession"]["todos"]
            self.assertEqual(len(s_todos), 2)
            self.assertEqual(s_todos[0]["id"], inbox_local_id)
            self.assertEqual(s_todos[1]["title"], "Draft conclusion")
            self.assertEqual(s_todos[1]["priority"], 3)
            self.assertEqual(s_todos[1]["todoistId"], "td_new_2")

            # Delete Todoist task
            after_del = self.rpc("delete-todoist-task", {"todoistId": "td_new_1"}, via_stdin=True)
            self.assertTrue(after_del["todoistDeleted"])
            self.assertEqual(deleted_ids, ["td_new_1"])

            for _, sent_payload in captured_posts:
                self.assertNotIn("deadline_date", sent_payload)
                self.assertNotIn("duration", sent_payload)
        finally:
            srv.shutdown()
            srv.server_close()

    def test_icon_library_has_all_100_phosphor_icons(self) -> None:
        icon_js = (ROOT / "IconData.js").read_text(encoding="utf-8")
        names = re.findall(r'"name":\s*"([^"]+)"', icon_js)
        self.assertEqual(len(names), 100)
        self.assertIn("rocket-launch", names)
        self.assertIn("mosque", names)
        self.assertIn("guitar", names)

    def test_windows_support_hyprland_window_close_and_close_shortcuts(self) -> None:
        expected_close_handlers = {
            "windows/MainPanelWindow.qml": "root.hideWindow()",
            "windows/NewSessionWindow.qml": "root.closeModal()",
        }
        for rel, close_call in expected_close_handlers.items():
            qml = (ROOT / rel).read_text(encoding="utf-8")
            self.assertIn("FloatingWindow {", qml, rel)
            self.assertNotIn("PanelWindow {", qml, rel)
            self.assertIn("minimumSize: Qt.size(root.targetWidth, root.targetHeight)", qml, rel)
            self.assertIn("maximumSize: Qt.size(root.targetWidth, root.targetHeight)", qml, rel)
            self.assertIn("onClosed:", qml, rel)
            self.assertIn(f"if (!root.closingFromHost) {close_call}", qml, rel)
            self.assertIn("Qt.Key_W", qml, rel)
            self.assertIn("Qt.Key_Q", qml, rel)
        popout_qml = (ROOT / "components/BarPopout.qml").read_text(encoding="utf-8")
        self.assertIn("Qt.Key_W", popout_qml)
        self.assertIn("Qt.Key_Q", popout_qml)

    def test_keyboard_navigation_contracts_and_qmllint(self) -> None:
        self.assertFalse((ROOT / "components/ShortcutsModal.qml").exists())

        main_qml = (ROOT / "windows/MainPanelWindow.qml").read_text(encoding="utf-8")
        self.assertIn("Keys.priority: Keys.BeforeItem", main_qml)
        self.assertNotIn("ShortcutsModal", main_qml)
        self.assertIn("if (root.activePageEditing) return", main_qml)
        self.assertIn("releaseTextFocus", main_qml)
        self.assertIn("enterFromTab", main_qml)
        self.assertIn("stepFocus", main_qml)

        new_sess_qml = (ROOT / "windows/NewSessionWindow.qml").read_text(encoding="utf-8")
        self.assertIn("Keys.priority: Keys.BeforeItem", new_sess_qml)
        self.assertIn("focusZoneStep", new_sess_qml)
        self.assertIn("togglePickerAtCursor", new_sess_qml)
        self.assertIn("stepRhythm", new_sess_qml)

        for page_rel in (
            "pages/TodayPage.qml",
            "pages/StatsPage.qml",
            "pages/SessionsPage.qml",
            "pages/CategoriesPage.qml",
            "pages/SettingsPage.qml",
        ):
            page_qml = (ROOT / page_rel).read_text(encoding="utf-8")
            self.assertIn("property bool kbPageActive:", page_qml, page_rel)
            self.assertIn("isEditingText", page_qml, page_rel)
            self.assertIn("function releaseTextFocus()", page_qml, page_rel)
            self.assertIn("function dismissOverlay()", page_qml, page_rel)
            self.assertIn("function enterFromTab(delta)", page_qml, page_rel)
            self.assertIn("function stepFocus(delta)", page_qml, page_rel)
            self.assertIn("function handleKey(event)", page_qml, page_rel)

        popout_qml = (ROOT / "components/BarPopout.qml").read_text(encoding="utf-8")
        self.assertIn("function triggerAction(", popout_qml)
        self.assertIn("stepWidgetStyle", popout_qml)

        qmllint = Path("/usr/lib/qt6/bin/qmllint")
        if qmllint.is_file():
            qml_targets = [
                "Service.qml",
                "windows/MainPanelWindow.qml",
                "windows/NewSessionWindow.qml",
                "pages/TodayPage.qml",
                "pages/StatsPage.qml",
                "pages/SessionsPage.qml",
                "pages/CategoriesPage.qml",
                "pages/SettingsPage.qml",
                "components/BarPopout.qml",
                "components/DetailCard.qml",
                "components/TaskSchedulePopover.qml",
                "components/TaskComposer.qml",
                "components/SymbolPicker.qml",
                "components/DayDrawer.qml",
                "components/RangePicker.qml",
            ]
            res = subprocess.run(
                [
                    str(qmllint),
                    "--bare",
                    "-I",
                    "/usr/lib/qt6/qml",
                    "-I",
                    "/usr/share/omarchy/shell",
                    "--unqualified",
                    "disable",
                    "--import",
                    "disable",
                    "--unresolved-type",
                    "disable",
                    "--uncreatable-type",
                    "disable",
                    *qml_targets,
                ],
                cwd=str(ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
            self.assertEqual(res.stdout.strip(), "", res.stdout)
            self.assertEqual(res.stderr.strip(), "", res.stderr)

    def test_marketplace_manifest_and_security_baseline(self) -> None:
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["schemaVersion"], 1)
        self.assertEqual(manifest["id"], "io.github.fatihaydost.houra")
        self.assertIn("service", manifest["kinds"])
        self.assertIn("bar-widget", manifest["kinds"])
        self.assertTrue((ROOT / manifest["entryPoints"]["service"]).is_file())
        self.assertTrue((ROOT / manifest["entryPoints"]["barWidget"]).is_file())

        # Ensure zero symlinks, zero setup/install filenames, and zero review-capability triggers
        forbidden_name_tokens = ("install", "installer", "setup", "uninstall")
        forbidden_text_patterns = (
            r"\bsudo\b",
            r"\bpkexec\b",
            r"\bsystemctl\b",
            r"\bsystemd-run\b",
            r"\bpacman\s+-S",
            r"\bapt-get\b",
            r"curl\s+[^|\n]*\|\s*(?:ba)?sh",
        )

        for path in ROOT.rglob("*"):
            if ".git" in path.parts or "__pycache__" in path.parts or "node_modules" in path.parts:
                continue
            self.assertFalse(path.is_symlink(), f"Symlink forbidden by omarchy-plugin-validate: {path}")
            if path.is_file():
                self.assertEqual(path.stat().st_mode & 0o111, 0, f"Executable bit triggers Marketplace installer capability: {path}")
            low_name = path.name.lower()
            for tok in forbidden_name_tokens:
                self.assertNotIn(tok, low_name, f"Setup-like filename triggers installer capability: {path}")
            if path.is_file() and path.suffix in {".qml", ".js", ".py", ".md", ".json", ".sh"}:
                self.assertLess(path.stat().st_size, 512 * 1024, f"File exceeds 512 KiB scan limit: {path}")
                if path.name == "test_houra.py":
                    continue
                txt = path.read_text(encoding="utf-8")
                if path.suffix == ".qml":
                    self.assertIsNone(re.search(r"pixelSize:\s*[0-9]+\.[0-9]+", txt), f"Fractional font.pixelSize in {path}")
                for pat in forbidden_text_patterns:
                    self.assertIsNone(re.search(pat, txt), f"Pattern {pat} matched in {path}")


if __name__ == "__main__":
    unittest.main()
