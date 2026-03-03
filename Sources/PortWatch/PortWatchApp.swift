import SwiftUI

@main
struct PortWatchApp: App {
    @StateObject private var scanner: PortScanner

    init() {
        let s = PortScanner()
        s.start()
        _scanner = StateObject(wrappedValue: s)
    }

    var body: some Scene {
        MenuBarExtra {
            PortWatchPanel(scanner: scanner)
        } label: {
            Image(systemName: scanner.ports.isEmpty
                  ? "antenna.radiowaves.left.and.right"
                  : "antenna.radiowaves.left.and.right.circle.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}

struct PortWatchPanel: View {
    @ObservedObject var scanner: PortScanner
    @State private var hoveredPid: Int?
    @State private var confirmingKillAll = false

    private let headerFont = Font.system(size: 10, weight: .regular, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if scanner.ports.isEmpty {
                Text("no active ports")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(scanner.ports) { port in
                    PortRow(port: port, scanner: scanner, isHovered: hoveredPid == port.pid)
                        .onHover { hovering in
                            hoveredPid = hovering ? port.pid : nil
                        }
                }

                Divider()
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                HStack {
                    Spacer()
                    if confirmingKillAll {
                        HStack(spacing: 8) {
                            Text("kill all?")
                                .font(headerFont)
                                .foregroundStyle(.red.opacity(0.8))

                            HoverButton(label: "yes", color: .red.opacity(0.8), font: headerFont) {
                                scanner.killAll()
                                confirmingKillAll = false
                            }

                            HoverButton(label: "no", color: .secondary, font: headerFont) {
                                confirmingKillAll = false
                            }
                        }
                    } else {
                        HoverButton(label: "kill all", color: .red.opacity(0.8), font: headerFont) {
                            confirmingKillAll = true
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            Divider()
                .padding(.vertical, 6)

            HStack {
                Text("portwatch")
                    .font(headerFont)
                    .foregroundStyle(.tertiary)
                Spacer()
                HoverButton(label: "quit", color: .secondary, font: headerFont) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 280)
    }
}

struct HoverButton: View {
    let label: String
    let color: Color
    let font: Font
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .foregroundStyle(isHovered ? color.opacity(1) : color.opacity(0.7))
                .underline(isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct IconHoverButton: View {
    let systemName: String
    let size: CGFloat
    let color: Color
    let action: () -> Void
    var tooltip: String = ""

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: isHovered ? .bold : .regular))
                .foregroundStyle(isHovered ? color : color.opacity(0.6))
                .scaleEffect(isHovered ? 1.15 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip)
    }
}

struct PortRow: View {
    let port: PortInfo
    let scanner: PortScanner
    let isHovered: Bool

    private let monoSmall = Font.system(size: 10, weight: .regular, design: .monospaced)

    var body: some View {
        HStack(spacing: 0) {
            Text(port.portString)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 52, alignment: .leading)

            Text(port.projectName.isEmpty ? port.serverLabel : port.projectName)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            // Right side: action buttons on hover replace the stats columns
            if isHovered {
                HStack(spacing: 10) {
                    IconHoverButton(
                        systemName: "arrow.up.right.square",
                        size: 14,
                        color: .primary,
                        action: {
                            if let url = URL(string: "http://localhost:\(port.port)") {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        tooltip: "Open in browser"
                    )

                    IconHoverButton(
                        systemName: port.isSuspended ? "play.circle.fill" : "pause.circle.fill",
                        size: 14,
                        color: .primary,
                        action: { scanner.toggleSuspend(pid: port.pid) },
                        tooltip: port.isSuspended ? "Resume" : "Pause"
                    )

                    IconHoverButton(
                        systemName: "xmark.circle.fill",
                        size: 14,
                        color: .red,
                        action: { scanner.killProcess(pid: port.pid) },
                        tooltip: "Kill"
                    )
                }
                .frame(width: 78, alignment: .trailing)
            } else if port.isSuspended {
                Text("paused")
                    .font(monoSmall)
                    .foregroundStyle(.yellow.opacity(0.8))
                    .frame(width: 78, alignment: .trailing)
            } else {
                HStack(spacing: 4) {
                    Text(String(format: "%.0f%%", port.cpuPercent))
                        .font(monoSmall)
                        .foregroundStyle(port.cpuPercent > 50 ? .red : .secondary)
                        .frame(width: 32, alignment: .trailing)

                    Text(formatMem(port.memMB))
                        .font(monoSmall)
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
                .frame(width: 78, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered ? .white.opacity(0.05) : .clear)
        .contentShape(Rectangle())
    }

    private func formatMem(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1fG", mb / 1024)
        }
        return String(format: "%.0fM", mb)
    }
}
