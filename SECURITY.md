# Security Policy

## Scope & Privacy Model

Houra is offline-first by default and makes **zero network requests** unless you explicitly enable the optional **Todoist** integration in `Settings → Todoist`.

- **Local focus data:** Focus sessions, categories, notes, and daily to-dos are stored locally in `~/.local/share/houra/houra.sqlite`, with non-secret UI preferences in `~/.config/houra/settings.json`.
- **Weekly Markdown notes:** When enabled, your weekly Markdown files are opened strictly **read-only**; Houra never modifies your vault or Markdown files.
- **Todoist API token (optional):**
  - Stored exclusively in `~/.local/state/houra/todoist_token` inside a `0700` state directory, written atomically with `0600` (`rw-------`) file permissions.
  - Never written to `settings.json`, SQLite, logs, or UI snapshot JSON, and passed from QML to the local Python helper via `stdin` rather than command-line arguments (`/proc/<pid>/cmdline`).
  - Sent only to `https://api.todoist.com/api/v1/` over TLS (`Authorization: Bearer`) to read projects/tasks and, when you explicitly mark a task completed or reopened in Houra, close or reopen that task.
  - Clicking **Disconnect** in `Settings → Todoist` deletes `~/.local/state/houra/todoist_token` and clears the local Todoist cache (`~/.cache/houra/todoist_cache.json`).
- **Privilege boundary:** Nothing runs with elevated privileges, and Houra modifies no system files outside its own XDG data, config, state, and cache directories.

## Reporting a Vulnerability

If you discover a security issue (such as a token leak, path traversal, or unintended file write), please report it privately via GitHub Security Advisories on [`fatihaydost/omarchy-houra`](https://github.com/fatihaydost/omarchy-houra/security/advisories/new) or by contacting **fatihaydostt@gmail.com** rather than opening a public issue.

Include the plugin version from `manifest.json` and steps to reproduce.
