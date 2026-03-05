import Foundation
import Combine

final class PortScanner: ObservableObject {
    @Published var ports: [PortInfo] = []
    @Published var sessions: [TerminalSession] = []

    private var timer: Timer?

    private static let jsonDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".port-watch")
    private static let jsonPath = jsonDirectory.appendingPathComponent("ports.json")

    private static let devProcesses: Set<String> = [
        "node", "python", "python3", "ruby", "java", "go", "deno", "bun",
        "cargo", "php", "uvicorn", "gunicorn", "next", "vite", "webpack",
        "esbuild", "turbopack", "flask", "django", "rails", "beam.smp",
        "mix", "elixir", "swift", "dotnet", "nginx", "httpd", "caddy",
        "hugo", "gatsby", "nuxt", "remix", "astro", "ng", "parcel",
        "rollup", "tsx", "ts-node", "npx", "yarn", "pnpm",
        "postgres", "mysqld", "mongod", "redis-ser",
    ]

    func start() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scan() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let results = Self.runLsof()
            let termSessions = Self.scanTerminalSessions()
            DispatchQueue.main.async {
                self?.ports = results
                self?.sessions = termSessions
                Self.writeJSON(results)
            }
        }
    }

    // MARK: - Process control

    func killProcess(pid: Int) {
        kill(Int32(pid), SIGTERM)
    }

    func killAll() {
        for port in ports {
            kill(Int32(port.pid), SIGTERM)
        }
    }

    func toggleSuspend(pid: Int) {
        let isSuspended = ports.first(where: { $0.pid == pid })?.isSuspended ?? false
        kill(Int32(pid), isSuspended ? SIGCONT : SIGSTOP)
        scan()
    }



    // MARK: - Terminal sessions

    /// Get the list of Terminal.app TTYs via AppleScript, then aggregate
    /// CPU/MEM for all processes on each TTY and label with the most
    /// meaningful process running in it.
    static func scanTerminalSessions() -> [TerminalSession] {
        // 1. Get TTYs from Terminal.app
        let ttys = getTerminalTTYs()
        guard !ttys.isEmpty else { return [] }

        // 2. Get all processes with tty, cpu, rss, comm in one ps call
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-e", "-o", "tty=,pcpu=,rss=,pid=,comm="]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        // Group processes by tty
        struct ProcEntry {
            let cpu: Double
            let rssKB: Double
            let pid: Int
            let comm: String
        }

        var byTTY: [String: [ProcEntry]] = [:]
        for line in output.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count >= 5 else { continue }
            let tty = String(parts[0])
            guard tty != "??" else { continue }
            let cpu = Double(parts[1]) ?? 0
            let rss = Double(parts[2]) ?? 0
            let pid = Int(parts[3]) ?? 0
            let comm = String(parts[4])
            let devTTY = "/dev/" + tty
            if ttys.keys.contains(devTTY) {
                byTTY[devTTY, default: []].append(ProcEntry(cpu: cpu, rssKB: rss, pid: pid, comm: comm))
            }
        }

        // 3. For each tty, aggregate stats and pick a label
        let shellNames: Set<String> = ["login", "-zsh", "zsh", "-bash", "bash", "-sh", "sh"]
        var results: [TerminalSession] = []

        for (tty, info) in ttys {
            let procs = byTTY[tty] ?? []
            let totalCPU = procs.reduce(0) { $0 + $1.cpu }
            let totalMem = procs.reduce(0) { $0 + $1.rssKB } / 1024.0

            // Find the most interesting process (highest CPU, excluding shells)
            let interesting = procs
                .filter { !shellNames.contains($0.comm) }
                .sorted { $0.cpu > $1.cpu }

            var label = "idle"
            if let top = interesting.first {
                // Check if it's claude — if so, find what project via cwd
                if top.comm == "claude" {
                    let cwd = getProcessCwd(pid: top.pid)
                    if !cwd.isEmpty, cwd != "/" {
                        let dirName = (cwd as NSString).lastPathComponent
                        let home = FileManager.default.homeDirectoryForCurrentUser.path
                        if cwd != home {
                            label = "claude · \(dirName)"
                        } else {
                            label = "claude"
                        }
                    } else {
                        label = "claude"
                    }
                } else if top.comm.hasPrefix("sourcekit") {
                    // sourcekit-lsp is noise, skip to next
                    let next = interesting.first { !$0.comm.hasPrefix("sourcekit") && $0.comm != "claude" }
                    label = next?.comm ?? (interesting.contains { $0.comm == "claude" } ? "claude" : "idle")
                } else {
                    label = top.comm
                }
            }

            results.append(TerminalSession(
                tty: tty,
                label: label,
                cpuPercent: totalCPU,
                memMB: totalMem,
                windowIndex: info.window,
                tabIndex: info.tab
            ))
        }

        return results.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    private static func getTerminalTTYs() -> [String: (window: Int, tab: Int)] {
        let script = """
        tell application "Terminal"
            set output to ""
            set winIdx to 0
            repeat with w in windows
                set winIdx to winIdx + 1
                set tabIdx to 0
                repeat with t in tabs of w
                    set tabIdx to tabIdx + 1
                    try
                        set output to output & (tty of t) & "," & winIdx & "," & tabIdx & linefeed
                    end try
                end repeat
            end repeat
            return output
        end tell
        """

        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var result: [String: (window: Int, tab: Int)] = [:]
        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: ",")
            guard parts.count >= 3,
                  let win = Int(parts[1]),
                  let tab = Int(parts[2]) else { continue }
            result[String(parts[0])] = (win, tab)
        }
        return result
    }

    func focusTerminalSession(_ session: TerminalSession) {
        let script = """
        tell application "Terminal"
            set index of window \(session.windowIndex) to 1
            set selected of tab \(session.tabIndex) of window 1 to true
            activate
        end tell
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }

    // MARK: - Scanning

    static func runLsof() -> [PortInfo] {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-iTCP", "-sTCP:LISTEN", "-nP"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return parseLsofOutput(output)
    }

    static func parseLsofOutput(_ output: String) -> [PortInfo] {
        var seen = Set<Int>()
        var results: [PortInfo] = []

        let lines = output.components(separatedBy: "\n")
        for line in lines.dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }

            let processName = String(parts[0])
            let pidStr = String(parts[1])
            let nameField = String(parts[8])

            guard let pid = Int(pidStr) else { continue }

            let lowerName = processName.lowercased()
            guard devProcesses.contains(lowerName) else { continue }

            guard let colonIdx = nameField.lastIndex(of: ":") else { continue }
            let portStr = String(nameField[nameField.index(after: colonIdx)...])
            guard let port = Int(portStr) else { continue }

            guard !seen.contains(port) else { continue }
            seen.insert(port)

            let address = String(nameField[nameField.startIndex..<colonIdx])
            let projectCwd = getProcessCwd(pid: pid)

            // Skip processes with no real project directory — these are app-embedded
            // runtimes (Autodesk Fusion's node, Figma's node, etc.), not dev servers.
            guard !projectCwd.isEmpty, projectCwd != "/" else { continue }

            let label = resolveServerLabel(pid: pid, fallback: processName)
            let project = resolveProjectName(cwd: projectCwd)
            let stats = getProcessStats(pid: pid)

            results.append(PortInfo(
                port: port,
                process: processName,
                pid: pid,
                address: address,
                serverLabel: label,
                projectName: project,
                projectPath: projectCwd,
                cpuPercent: stats.cpu,
                memMB: stats.mem,
                isSuspended: stats.suspended
            ))
        }

        return results.sorted { $0.port < $1.port }
    }

    // MARK: - Process info

    private static func getProcessStats(pid: Int) -> (cpu: Double, mem: Double, suspended: Bool) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "%cpu=,rss=,state="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return (0, 0, false)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !out.isEmpty else {
            return (0, 0, false)
        }

        let parts = out.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3 else { return (0, 0, false) }

        let cpu = Double(parts[0]) ?? 0
        let rssKB = Double(parts[1]) ?? 0
        let state = String(parts[2])
        let suspended = state.contains("T")

        return (cpu, rssKB / 1024.0, suspended)
    }

    /// Get the working directory of a process, then derive the project name
    /// from package.json "name" field, or fall back to the directory name.
    private static func resolveProjectName(cwd: String) -> String {
        guard !cwd.isEmpty, cwd != "/" else { return "" }

        // Try package.json in cwd
        let pkgPath = (cwd as NSString).appendingPathComponent("package.json")
        if let data = FileManager.default.contents(atPath: pkgPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = json["name"] as? String, !name.isEmpty {
            return name
        }

        // Try pyproject.toml name (basic parse)
        let pyprojectPath = (cwd as NSString).appendingPathComponent("pyproject.toml")
        if let contents = try? String(contentsOfFile: pyprojectPath, encoding: .utf8) {
            let lines = contents.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("name") && trimmed.contains("=") {
                    let value = trimmed.split(separator: "=", maxSplits: 1).last?
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) ?? ""
                    if !value.isEmpty { return value }
                }
            }
        }

        // Fall back to directory name
        return (cwd as NSString).lastPathComponent
    }

    private static func getProcessCwd(pid: Int) -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let out = String(data: data, encoding: .utf8) else { return "" }

        // Output has lines like "p1234", "fcwd", "n/path/to/dir"
        for line in out.components(separatedBy: "\n") {
            if line.hasPrefix("n/") {
                return String(line.dropFirst()) // drop the "n" prefix
            }
        }
        return ""
    }

    private static func resolveServerLabel(pid: Int, fallback: String) -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "args="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return fallback
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let fullCmd = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fullCmd.isEmpty else {
            return fallback
        }

        return extractLabel(from: fullCmd, fallback: fallback)
    }

    private static func extractLabel(from cmd: String, fallback: String) -> String {
        if cmd.hasPrefix("next-server") { return "next" }

        let knownTools = [
            "expo", "vite", "webpack", "next", "nuxt", "remix", "astro",
            "gatsby", "parcel", "rollup", "esbuild", "turbopack",
            "uvicorn", "gunicorn", "flask", "django", "rails",
            "hugo", "caddy", "nginx",
        ]
        let cmdLower = cmd.lowercased()
        for tool in knownTools {
            if cmdLower.contains("/\(tool)") || cmdLower.contains(" \(tool)") {
                return tool
            }
        }

        if let mRange = cmdLower.range(of: " -m ") {
            let afterM = cmd[mRange.upperBound...]
            let module = afterM.split(separator: " ").first.map(String.init) ?? fallback
            if module == "multiprocessing.spawn" { return fallback }
            return module
        }

        if cmdLower.contains("manage.py") && cmdLower.contains("runserver") {
            return "django"
        }

        return fallback
    }

    // MARK: - JSON

    private static func writeJSON(_ ports: [PortInfo]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: jsonDirectory, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        let snapshot = PortSnapshot(
            timestamp: formatter.string(from: Date()),
            ports: ports
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        let tempURL = jsonDirectory.appendingPathComponent("ports.json.tmp")
        try? data.write(to: tempURL, options: .atomic)
        try? fm.removeItem(at: jsonPath)
        try? fm.moveItem(at: tempURL, to: jsonPath)
    }
}
