"""Local stand-in for the Todoist API v1, only for recording README media with sample tasks.

Run: python3 -I mock_todoist.py [port]   then point Houra at it with
HOURA_TODOIST_API_BASE=http://127.0.0.1:<port>/api/v1 and the token "demo-token".
"""
from __future__ import annotations

import datetime as dt
import http.server
import json
import sys

TOKEN = "demo-token"
TODAY = dt.date.today()


def _due(days: int, time: str = "", every: str = "") -> dict:
    day = (TODAY + dt.timedelta(days=days)).isoformat()
    due = {"date": day, "is_recurring": bool(every), "string": every or day}
    if time:
        due["datetime"] = f"{day}T{time}:00"
        due["date"] = due["datetime"]
    return due


def _local_day(due: dict) -> str:
    # due_datetime arrives in UTC ("...Z"); compare against the local calendar day like Todoist does
    stamp = due.get("datetime") or due["date"]
    if stamp.endswith("Z"):
        return dt.datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone().date().isoformat()
    return stamp[:10]


PROJECTS = [
    {"id": "p_inbox", "name": "Inbox", "inbox_project": True},
    {"id": "p_product", "name": "Product"},
    {"id": "p_systems", "name": "Systems"},
    {"id": "p_writing", "name": "Writing"},
    {"id": "p_reading", "name": "Reading"},
]

TASKS = {
    t["id"]: t
    for t in [
        {"id": "t1", "content": "Review the onboarding copy", "description": "", "priority": 4,
         "project_id": "p_product", "due": _due(0, "10:30"), "labels": []},
        {"id": "t2", "content": "Fix flaky stats test", "description": "Only fails on Mondays", "priority": 3,
         "project_id": "p_systems", "due": _due(0, "14:00"), "labels": []},
        {"id": "t3", "content": "Outline the release post", "description": "", "priority": 2,
         "project_id": "p_writing", "due": _due(0), "labels": []},
        {"id": "t4", "content": "Inbox zero", "description": "", "priority": 1,
         "project_id": "p_inbox", "due": _due(0, "", "every weekday"), "labels": []},
        {"id": "t5", "content": "Read chapter 8", "description": "", "priority": 1,
         "project_id": "p_reading", "due": _due(2), "labels": []},
        {"id": "t6", "content": "Plan next sprint", "description": "", "priority": 3,
         "project_id": "p_product", "due": _due(4, "11:00"), "labels": []},
    ]
}
_next = [100]


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        return

    def _json(self, code: int, obj: dict | None = None) -> None:
        raw = json.dumps(obj).encode() if obj is not None else b""
        self.send_response(code)
        if obj is not None:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _authed(self) -> bool:
        if self.headers.get("Authorization") == f"Bearer {TOKEN}":
            return True
        self._json(401, {"error": "unauthorized"})
        return False

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length") or "0")
        return json.loads(self.rfile.read(n).decode() or "{}") if n else {}

    def do_GET(self) -> None:
        if not self._authed():
            return
        if self.path.startswith("/api/v1/user"):
            self._json(200, {"full_name": "Demo User", "email": "demo@example.com"})
        elif self.path.startswith("/api/v1/projects"):
            self._json(200, {"results": PROJECTS, "next_cursor": None})
        elif self.path.startswith("/api/v1/tasks"):
            open_tasks = [t for t in TASKS.values() if not t.get("checked")]
            if self.path.startswith("/api/v1/tasks/filter"):  # Houra's default filter: today | overdue
                open_tasks = [t for t in open_tasks if t.get("due") and _local_day(t["due"]) <= TODAY.isoformat()]
            self._json(200, {"results": open_tasks, "next_cursor": None})
        else:
            self._json(404, {})

    def do_POST(self) -> None:
        if not self._authed():
            return
        body = self._body()
        parts = self.path.rstrip("/").split("/")  # ['', 'api', 'v1', 'tasks', id?, action?]
        if self.path.rstrip("/") == "/api/v1/tasks":
            _next[0] += 1
            tid = f"t{_next[0]}"
            due = None
            if body.get("due_datetime"):
                due = {"date": body["due_datetime"], "datetime": body["due_datetime"], "is_recurring": False}
            elif body.get("due_date"):
                due = {"date": body["due_date"], "is_recurring": False}
            elif body.get("due_string") and body["due_string"] != "no date":
                due = {"date": TODAY.isoformat(), "string": body["due_string"], "is_recurring": "every" in body["due_string"]}
            TASKS[tid] = {"id": tid, "content": body.get("content", ""), "description": body.get("description", ""),
                          "priority": int(body.get("priority", 1)), "project_id": body.get("project_id", "p_inbox"),
                          "due": due, "labels": body.get("labels", [])}
            self._json(200, TASKS[tid])
        elif len(parts) >= 5 and parts[3] == "tasks" and parts[4] in TASKS:
            task = TASKS[parts[4]]
            if len(parts) == 6 and parts[5] in ("close", "reopen"):
                task["checked"] = parts[5] == "close"
                self._json(204)
                return
            for key in ("content", "description", "priority", "project_id"):
                if key in body:
                    task[key] = body[key]
            if body.get("due_string") == "no date":
                task["due"] = None
            elif body.get("due_datetime"):
                task["due"] = {"date": body["due_datetime"], "datetime": body["due_datetime"], "is_recurring": False}
            elif body.get("due_date"):
                task["due"] = {"date": body["due_date"], "is_recurring": False}
            self._json(200, task)
        else:
            self._json(404, {})

    def do_DELETE(self) -> None:
        if not self._authed():
            return
        parts = self.path.rstrip("/").split("/")
        if len(parts) == 5 and parts[3] == "tasks":
            TASKS.pop(parts[4], None)
            self._json(204)
        else:
            self._json(404, {})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
