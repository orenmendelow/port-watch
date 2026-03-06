# PortWatch

A macOS menu bar app that monitors active dev server ports and terminal sessions.

![PortWatch](screenshot.png)

## Features

- **Menu bar icon** -- antenna icon, changes appearance when dev ports are active
- **Project name detection** -- reads `package.json` or `pyproject.toml` name field, falls back to directory name
- **Live CPU/MEM stats** -- per-process and per-terminal-session, updated every 3 seconds
- **Process control** -- hover any port row to reveal: open in browser, pause/resume (SIGSTOP/SIGCONT), kill (SIGTERM). All buttons have hover states.
- **Kill all** -- inline confirmation prompt in the footer
- **Terminal sessions** -- CPU/MEM breakdown per Terminal.app window, labeled by main process and project (e.g. "claude · shipyard"). Hover to focus the window.
- **Smart filtering** -- whitelists known dev processes, excludes app-embedded runtimes (Autodesk Fusion's node, Figma agent, etc.) by checking process working directory
- **JSON sidecar** -- writes `~/.port-watch/ports.json` every scan cycle for CLI tools to consume
- **CLI companion** -- `port-watch` command reads the JSON sidecar or falls back to direct `lsof`
- **Auto-start on login** -- LaunchAgent included

## Requirements

- macOS 13+ (tested on macOS 26 Tahoe)
- Swift 5.9+

## Install

```sh
git clone https://github.com/orenmendelow/port-watch.git
cd port-watch
./install.sh
```

This will:

1. Build the Swift package in release mode
2. Create `PortWatch.app` in `/Applications` with generated app icon
3. Install a LaunchAgent for auto-start on login
4. Symlink the `port-watch` CLI to `/usr/local/bin`
5. Create `~/.port-watch/` data directory

Start the app:

```sh
open /Applications/PortWatch.app
```

## Uninstall

```sh
./uninstall.sh
```

Removes the app bundle, LaunchAgent, CLI symlink, and `~/.port-watch/` directory.

## CLI Usage

When the menu bar app is running, the CLI reads its JSON sidecar for instant results:

```sh
port-watch
```

```
PROCESS            PORT  PID
───────            ────  ───
node               3000  12345
Python             8000  12346
```

If the app is not running (or the JSON is stale), the CLI falls back to scanning via `lsof` directly.

## How It Works

### Architecture

Uses `NSStatusBar` + `NSPopover` (AppKit) for the menu bar item, with SwiftUI views inside the popover. This approach is compatible across macOS 13 through macOS 26.

### Port scanning

Polls `lsof -iTCP -sTCP:LISTEN -nP` every 3 seconds on a background thread. Filters against a whitelist of dev process names (node, python, ruby, go, deno, bun, vite, uvicorn, etc.) and discards any process whose working directory is `/` (catches app-embedded runtimes).

For each listening port:

1. **Resolves the project name** -- gets the process working directory via `lsof -a -p <pid> -d cwd -Fn`, then reads `package.json` or `pyproject.toml`. Falls back to the directory name.
2. **Resolves the server label** -- inspects the full command line via `ps` and matches against known frameworks (next, vite, django, flask, expo, etc.)
3. **Reads CPU/MEM stats** -- via `ps -p <pid> -o %cpu=,rss=,state=`
4. **Detects suspended state** -- from the process state flag (`T`)

### Terminal sessions

Queries Terminal.app via AppleScript for each window/tab's TTY, aggregates CPU/MEM for all processes on that TTY. Sessions are labeled by the most CPU-intensive non-shell process, with project context from the working directory (e.g. "claude · shipyard").

### JSON sidecar

Results are written atomically to `~/.port-watch/ports.json` on every scan cycle.

```json
{
  "timestamp": "2026-03-06T12:00:00Z",
  "ports": [
    {
      "port": 3000,
      "process": "node",
      "pid": 12345,
      "address": "*",
      "serverLabel": "next",
      "projectName": "my-app",
      "projectPath": "/Users/you/projects/my-app",
      "cpuPercent": 2.3,
      "memMB": 148.5,
      "isSuspended": false
    }
  ]
}
```

The CLI considers the JSON stale after 10 seconds and falls back to direct `lsof`.

## License

MIT
