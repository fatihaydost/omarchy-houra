<p align="center">
  <img src="assets/icon.png" width="150" alt="Houra icon">
</p>

<h1 align="center">Houra for Omarchy</h1>

<p align="center">
  <b>A calm focus timer for Omarchy.</b><br>
  Plan the session, keep the time in sight, and step away from the screen when the break comes.
</p>

<p align="center">
  <b>English</b> · <a href="README.tr.md">Türkçe</a>
</p>

<p align="center">
  <img src="assets/flow.gif" width="880" alt="Starting a session, checking off a task and reaching the full-screen break">
</p>

---

This is the Omarchy version of Houra, built for `omarchy-shell` and Hyprland. For the macOS version, see [**Houra**](https://github.com/serbestonline/Houra) by Emirhan (`@serbestonline`); both use the same SQLite data format.

Houra is a focus timer built around three ideas:

1. **Decide before you start.** Every session begins with a category, a goal and, if you want, a short to-do list picked from today's tasks, your weekly note or Todoist. Once the session runs, the list is locked: you finish what you planned instead of adding more.
2. **Keep time in sight without a window in the way.** A small tag, strip, capsule, card or ring sits on your screen. Click it and the full session opens beside it; move away and it closes again. Everywhere outside the widget stays click-through, so your tiled windows never lose the pointer.
3. **Really take the break.** When the time is up, a full-screen break covers every display. It only lets you back in early through a deliberate, press-and-hold *Emergency* button.

Everything stays on your machine in a local SQLite file. There is no account and no tracking; Todoist is optional and off by default.

The interface is available in English and Turkish, and follows your active Omarchy theme.

## Contents

- [Sessions](#sessions)
- [On-screen views](#on-screen-views)
- [Break screen](#break-screen)
- [Statistics](#statistics)
- [Today, sessions and categories](#today-sessions-and-categories)
- [Todoist](#todoist)
- [Installation](#installation)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Your data](#your-data)
- [Building and contributing](#building-and-contributing)

## Sessions

<img src="assets/new-session.png" width="380" align="right" alt="New session window">

Start a session from the bar menu, from the panel, or from anywhere with a keybinding (see [Keyboard shortcuts](#keyboard-shortcuts)).

- **Category:** each category has its own colour and, optionally, an emoji or one of 100 built-in icons.
- **Goal:** answer *What are you focusing on?* in a few words.
- **Tasks:** tick tasks from today's list, or write new ones with a title, optional details, a `P1–P4` priority and a time (`p1`, `@14:30` work inline). New tasks are added to today's list too.
- **This week's list:** if you plan your week in a Markdown file, for example a weekly note in Obsidian, Houra reads its open tasks and lets you pick them too. Set the path in *Settings › Weekly tasks*; it can contain the year, week and month (`{YYYY}`, `{WW}`, `{MM}`) and `*` for any folder, so it follows you into next week by itself. The file is only read, never written.
- **Rhythm:** **25 + 5**, **50 + 10**, a **custom** length (1–240 min focus, 1–90 min break), or **free**: the clock counts up, and every 50 minutes the screen pulses and the widget asks if you want a break. Saying no is fine.

During the session every task has three states, cycled with a click:

| | |
|---|---|
| 🤓 | to do |
| 🙂‍↔️ | doing right now (only one at a time) |
| 🥳 | done |

Each session also has a free-form **Notes** field. Notes and tasks are kept with the session and show up later in *Sessions*.

<br clear="right">

## On-screen views

<p align="center">
  <img src="assets/widgets.gif" width="728" alt="The five on-screen views and their detail panel">
</p>

While a session runs, Houra shows the remaining time and the task you are on in one of five views. Choose it in *Settings › Show on screen*, or from the bar menu:

| View | What it looks like |
|---|---|
| **Tag** | A label stuck to the screen edge: category, current task and time, with a thin progress line. |
| **Thin strip** | A thin line along the edge that fills from the bottom; the time rides on top of it. |
| **Capsule** | A floating pill with the task, the time and a pause button. |
| **Card** | A floating card with a large progress ring. |
| **Ring** | Just a small ring with the time inside. |

**Click** any view and the detail panel opens next to it: the big countdown, *Pause* and *Finish*, *Close & save* or *Cancel*, the task list, your notes and a timeline of today. Move the mouse away and it closes. While you are typing a note it stays open. With the thin strip, the panel slides out as a drawer along the edge.

**Press and drag** to move a view. The tag and the strip snap to the nearest edge, left or right. The capsule, card and ring stay exactly where you drop them. Drag across the edge you share with another monitor and the view moves to that display. Positions are remembered, and the view never jumps when you switch monitors or workspaces.

<p align="center">
  <img src="assets/snap.gif" width="640" alt="Dragging the tag to the other edge">
</p>

## Break screen

<p align="center">
  <img src="assets/rest.gif" width="720" alt="Full-screen break">
</p>

When the focus time ends, or when you press *Finish*, a slow black-and-white scene covers every screen with the break countdown. Keystrokes are swallowed on purpose.

If something really cannot wait, **press and hold *Emergency* for 1.5 seconds**. The break keeps running in the bar, the early exit is recorded, and you can go back to the break from the bar menu. When the break ends, Houra asks about your next session.

## Statistics

<p align="center">
  <img src="assets/stats.gif" width="1000" alt="Statistics page">
</p>

- **Periods:** week, month, year, or any range picked from the calendar. Step through periods with ‹ ›.
- **At a glance:** total focus with the change from the previous period, daily average, finished tasks, and your best day.
- **Three charts:**
  - **Calendar:** every day is a tile with a thin line showing the category mix. Long ranges turn into a year grid.
  - **Flow:** categories stacked as smooth layers over time.
  - **Time map:** one row per day, sessions placed at the real hours you worked them.
- **Categories:** hover a category to highlight it, click it to filter the whole page by it.
- **Most productive hours:** a 24-hour strip of when you actually focus.
- **Day details:** click any day for its category split, sessions, rhythms and tasks.

## Today, sessions and categories

<p align="center">
  <img src="assets/panel-today.png" width="49%" alt="Today page">
  <img src="assets/panel-sessions.png" width="49%" alt="Sessions page">
</p>

- **Today:** today's focus, breaks, tasks and emergency exits; a to-do planner with *Today*, *Week*, *Month*, *Upcoming* and *Inbox* tabs, priorities, times and repeating tasks (daily, weekdays, weekly, monthly); a vertical timeline of your sessions; and, if weekly tasks are on, a *This week* card with the open tasks of your weekly note. Click one to start a session with it.
- **Sessions:** your history grouped by day, filterable by category or *with notes*. Click a session to see its tasks and notes, or delete one you started by mistake.

<p align="center">
  <img src="assets/panel-categories.png" width="49%" alt="Categories">
  <img src="assets/panel-settings.png" width="49%" alt="Settings">
</p>

- **Categories:** rename a category in place. Click its square to pick a colour (or any custom colour), an emoji, or one of 100 [Phosphor](https://phosphoricons.com) icons, searchable in English and Turkish.
- **Settings:** appearance (your Omarchy theme or *Houra classic*), Do Not Disturb during focus, language, on-screen view, weekly tasks, Todoist, and your data.

### Bar widget

The bar icon is the Houra mark: rounded squares around a dot, like the app icon. During a session only the outer square stays, and it draws itself around as time passes, next to the remaining time. During a break it shows the break countdown. From its menu you can start a session, repeat a recent one, pause or finish, switch the on-screen view and open the panel.

## Todoist

<p align="center">
  <img src="assets/todoist.gif" width="880" alt="Picking Todoist tasks in a new session, adding one to Todoist and completing it">
</p>

Optional and off by default. Paste a personal API token from Todoist's website (*Settings › Integrations › Developer*) into *Settings › Todoist*. Houra then lists your Todoist tasks next to your own, lets you pick them in a new session, and can create or edit Todoist tasks with priority, due date, time and repeat. Finishing a session never closes a Todoist task by itself; you complete it explicitly when the task is done. The token is stored only in `~/.local/state/houra/todoist_token` with `0600` permissions. See [SECURITY.md](SECURITY.md).

## Installation

```bash
omarchy plugin add https://github.com/fatihaydost/omarchy-houra --enable
```

Remove it at any time:

```bash
omarchy plugin remove io.github.fatihaydost.houra
```

Requires **Omarchy 4.x**. It uses only what Omarchy already ships (`omarchy-shell` / Quickshell, the `python3` standard library, `pw-play`, `xdg-open`); there is no third-party dependency.

Optional: `zenity` (`pacman` package) enables the native folder/file pickers and the CSV save dialog. Without it, type the weekly path by hand; CSV export saves to `~/Downloads`.

## Keyboard shortcuts

Houra doesn't take any global keys by itself. Add the ones you want to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + N", "Houra new session", "omarchy-shell houra newSession")
o.bind("SUPER + ALT + H", "Houra panel", "omarchy-shell houra panel")
```

| Key | Action |
|---|---|
| `Tab` / `Shift + Tab` | Move between the sidebar and the page controls |
| `↑` `↓` `←` `→` | Move through lists, tabs, filters, rhythms and the icon grid |
| `Ctrl + Tab` | Next tab |
| `Enter` / `Space` | Select; `Enter` starts the session in the new session window |
| `Delete` | Delete the selected item |
| `Esc` | Leave a text field, close a drawer, then close the window |
| `SUPER + W`, `Ctrl + W`, `Ctrl + Q` | Close the Houra window |

Everything is also scriptable through `omarchy-shell houra <command>`:

| Command | Action |
|---|---|
| `newSession` | Open or close the new session window |
| `panel`, `stats`, `tab <name>` | Open the panel (on `today`, `stats`, `sessions`, `categories` or `settings`) |
| `close` | Close any open Houra window |
| `toggle` | Open the bar menu |
| `pause`, `finish` | Pause / resume, or finish and start the break |
| `closeSession`, `cancel` | Save without a break, or discard the session |
| `style <name>` | Switch view: `tag`, `strip`, `capsule`, `card`, `ring`, `none` |
| `syncTodoist`, `status` | Sync Todoist now, print the current state as JSON |

## Your data

All categories, tasks, sessions and notes are stored in a single SQLite file:

```
~/.local/share/houra/houra.sqlite
```

Preferences live in `~/.config/houra/settings.json`. Nothing leaves your machine unless you connect Todoist. From *Settings* you can open the data folder or export every session as CSV. If the shell restarts in the middle of a session, Houra picks it up where it left off.

## Building and contributing

The plugin is plain QML on top of `omarchy-shell`, with a small Python backend using only the standard library:

| Path | What it does |
|---|---|
| `Service.qml` | The session engine and `omarchy-shell houra` IPC |
| `BarWidget.qml`, `components/BarPopout.qml` | Bar icon and its menu |
| `windows/OnScreenWidgetWindow.qml`, `components/DetailCard.qml` | On-screen views and their detail panel |
| `windows/NewSessionWindow.qml`, `windows/RestOverlayWindow.qml` | New session window and the break screen |
| `windows/MainPanelWindow.qml`, `pages/` | The panel: Today, Statistics, Sessions, Categories, Settings |
| `backend/houra_cli.py` | SQLite storage, weekly Markdown, Todoist, CSV, chime |

For development, copy the folder into `~/.config/omarchy/plugins/io.github.fatihaydost.houra` and run `omarchy-restart-shell` after QML changes. Run the tests with `python3 -m unittest discover -s tests`.

The screenshots and GIFs in this README come from the plugin itself running on sample data: `zsh media/record/make_media.sh` records each scenario on an empty workspace without touching your own data, and [Remotion](https://www.remotion.dev) in `media/` frames the recordings and turns them into GIFs. The Todoist scenario talks to a local stand-in (`media/record/mock_todoist.py`), never to the real Todoist API.

## Credits

- macOS version, original concept and design: [**Houra**](https://github.com/serbestonline/Houra) by [Emirhan (`@serbestonline`)](https://github.com/serbestonline) (MIT).
- App icon: from the macOS version of [Houra](https://github.com/serbestonline/Houra) (MIT).
- Icons: [Phosphor Icons](https://phosphoricons.com) (MIT).
- Omarchy version by [Fatih Aydost (`@fatihaydost`)](https://github.com/fatihaydost).

## License

MIT
