# PortWatch

A macOS menu bar app that monitors active dev server ports and terminal sessions.

![PortWatch](screenshot.png)

## Features

- **Menu bar icon** -- changes appearance when ports are active
- **Project name detection** -- reads `package.json` name field, `pyproject.toml` name field, or falls back to directory name
- **Server label detection** -- identifies the framework/tool (next, vite, uvicorn, django, etc.) from the process command line
- **Live CPU/MEM stats** -- per-process and per-terminal-session, updated every 3 seconds
- **Process control** -- pause (SIGSTOP), resume (SIGCONT), or kill (SIGTERM) individual servers on hover
- **Open in browser** -- click to open `localhost:<port>`
- **Kill all** -- with inline confirmation prompt
- **Terminal sessions** -- shows CPU/MEM breakdown per Terminal.app window, labeled by main process and project (e.g. "claude · shipyard"). Hover to focus the window.
- **Smart filtering** -- excludes app-embedded runtimes (Autodesk Fusion's node, Figma agent, etc.) by checking process working directory
- **JSON sidecar** -- writes `~/.port-watch/ports.json` every scan cycle for CLI tools and scripts to consume
- **CLI companion** -- `port-watch` command reads the JSON sidecar or falls back to direct `lsof` scanning
- **Auto-start on login** -- installs a LaunchAgent

## Requirements

- macOS 13+
- Swift 5.9+

## Install

```sh
git clone https://github.com/orenmendelow/port-watch.git
cd port-watch
./install.sh
```

This will:

1. Build the Swift package in release mode
2. Create `PortWatch.app` in `/Applications` with app icon
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

PortWatch polls `lsof -iTCP -sTCP:LISTEN -nP` every 3 seconds on a background thread. It filters results against a known set of dev process names (node, python, ruby, go, deno, bun, vite, uvicorn, etc.) and discards system services and app-embedded runtimes (any process whose working directory is `/`).

For each listening port, it:

1. **Resolves the server label** -- inspects the full command line (`ps -p <pid> -o args=`) and matches against known frameworks (next, vite, django, flask, expo, etc.)
2. **Resolves the project name** -- gets the process working directory via `lsof -a -p <pid> -d cwd -Fn`, then reads `package.json` or `pyproject.toml` in that directory. Falls back to the directory name.
3. **Reads CPU/MEM stats** -- via `ps -p <pid> -o %cpu=,rss=,state=`
4. **Detects suspended state** -- from the process state flag (`T`)

For terminal sessions, it queries Terminal.app via AppleScript for each window/tab's TTY, then aggregates CPU/MEM for all processes on that TTY. Sessions are labeled by the most CPU-intensive non-shell process, with project context from the working directory.

Results are written atomically to `~/.port-watch/ports.json` on every scan cycle.

## JSON Format

`~/.port-watch/ports.json`:

```json
{
  "timestamp": "2026-03-03T12:00:00Z",
  "ports": [
    {
      "port": 3000,
      "process": "node",
      "pid": 12345,
      "address": "127.0.0.1",
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

The JSON file is only valid if it is less than 10 seconds old (the CLI enforces this).

## License

MIT
