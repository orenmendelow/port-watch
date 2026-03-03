import Foundation
import Combine

final class PortScanner: ObservableObject {
    @Published var ports: [PortInfo] = []

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
            DispatchQueue.main.async {
                self?.ports = results
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
            let label = resolveServerLabel(pid: pid, fallback: processName)
            let project = resolveProjectName(pid: pid)
            let stats = getProcessStats(pid: pid)

            results.append(PortInfo(
                port: port,
                process: processName,
                pid: pid,
                address: address,
                serverLabel: label,
                projectName: project,
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
    private static func resolveProjectName(pid: Int) -> String {
        let cwd = getProcessCwd(pid: pid)
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
