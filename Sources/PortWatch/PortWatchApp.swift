import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var scanner: PortScanner!

    func applicationDidFinishLaunching(_ notification: Notification) {
        scanner = PortScanner()
        scanner.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "PortWatch")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PortWatchPanel(scanner: scanner))

        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let symbolName = self.scanner.ports.isEmpty
                ? "antenna.radiowaves.left.and.right"
                : "antenna.radiowaves.left.and.right.circle.fill"
            self.statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "PortWatch")
            self.popover.contentViewController = NSHostingController(rootView: PortWatchPanel(scanner: self.scanner))
        }
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Make sure the popover window is key so it renders at full opacity
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

@main
struct PortWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

struct PortWatchPanel: View {
    @ObservedObject var scanner: PortScanner
    @State private var hoveredPort: Int?
    @State private var hoveredSession: String?
    @State private var confirmingKillAll = false

    private let headerFont = Font.system(size: 10, weight: .regular, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Ports section
            Text("PORTS")
                .font(headerFont)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if scanner.ports.isEmpty {
                Text("no active ports")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(scanner.ports) { port in
                    PortRow(port: port, scanner: scanner, isHovered: hoveredPort == port.port)
                        .onHover { hovering in
                            hoveredPort = hovering ? port.port : nil
                        }
                }
            }

            // Terminal sessions section
            if !scanner.sessions.isEmpty {
                Divider()
                    .padding(.vertical, 6)

                Text("SESSIONS")
                    .font(headerFont)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                ForEach(scanner.sessions) { session in
                    SessionRow(session: session, scanner: scanner, isHovered: hoveredSession == session.tty)
                        .onHover { hovering in
                            hoveredSession = hovering ? session.tty : nil
                        }
                }
            }

            Divider()
                .padding(.vertical, 6)

            // Footer
            HStack(spacing: 0) {
                Text("portwatch")
                    .font(headerFont)
                    .foregroundStyle(.tertiary)

                Spacer()

                if !scanner.ports.isEmpty {
                    if confirmingKillAll {
                        HStack(spacing: 6) {
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

                    Text(" · ")
                        .font(headerFont)
                        .foregroundStyle(.tertiary)
                }

                HoverButton(label: "quit", color: .secondary, font: headerFont) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 340)
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

            if isHovered {
                HStack(spacing: 8) {
                    IconHoverButton(
                        systemName: "arrow.up.right.square",
                        size: 14,
                        color: .white,
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
                        color: .white,
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
                .frame(width: 90, alignment: .trailing)
            } else if port.isSuspended {
                Text("paused")
                    .font(monoSmall)
                    .foregroundStyle(.yellow.opacity(0.8))
                    .frame(width: 90, alignment: .trailing)
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
                .frame(width: 90, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered ? .white.opacity(0.1) : .clear)
        .contentShape(Rectangle())
    }

    private func formatMem(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1fG", mb / 1024)
        }
        return String(format: "%.0fM", mb)
    }
}

struct SessionRow: View {
    let session: TerminalSession
    let scanner: PortScanner
    let isHovered: Bool

    private let monoSmall = Font.system(size: 10, weight: .regular, design: .monospaced)

    var body: some View {
        HStack(spacing: 0) {
            Text(session.label)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if isHovered {
                IconHoverButton(
                    systemName: "macwindow",
                    size: 14,
                    color: .white,
                    action: { scanner.focusTerminalSession(session) },
                    tooltip: "Show window"
                )
                .frame(width: 90, alignment: .trailing)
            } else {
                HStack(spacing: 4) {
                    Text(String(format: "%.0f%%", session.cpuPercent))
                        .font(monoSmall)
                        .foregroundStyle(session.cpuPercent > 50 ? .red : .secondary)
                        .frame(width: 32, alignment: .trailing)

                    Text(formatMem(session.memMB))
                        .font(monoSmall)
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
                .frame(width: 90, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isHovered ? .white.opacity(0.1) : .clear)
        .contentShape(Rectangle())
    }

    private func formatMem(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1fG", mb / 1024)
        }
        return String(format: "%.0fM", mb)
    }
}
