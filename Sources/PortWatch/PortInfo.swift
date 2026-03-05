import Foundation

struct PortInfo: Codable, Identifiable, Equatable {
    let port: Int
    let process: String
    let pid: Int
    let address: String
    let serverLabel: String   // framework/tool: "next", "expo", "uvicorn"
    let projectName: String   // from package.json or dir name: "shipyard", "wishlist-ios"
    let projectPath: String   // cwd of the process
    let cpuPercent: Double
    let memMB: Double
    let isSuspended: Bool

    var id: Int { port }

    var portString: String {
        "\(port)"
    }
}

struct TerminalSession: Identifiable, Equatable {
    let tty: String
    let label: String        // most meaningful process or project name
    let cpuPercent: Double
    let memMB: Double
    let windowIndex: Int
    let tabIndex: Int

    var id: String { tty }
}

struct PortSnapshot: Codable {
    let timestamp: String
    let ports: [PortInfo]
}
