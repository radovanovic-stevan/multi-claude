// ClaudeUsage — a small translucent desktop panel showing Claude subscription
// usage for each account. It shells out to `claude-usage --json` (which reads
// the OAuth tokens from the Keychain and queries the usage endpoint) and renders
// the result. No Dock icon; sits on the desktop; draggable; auto-refreshes.

import Cocoa
import SwiftUI
import Combine

// MARK: - Data model (matches `claude-usage --json`)

struct Report: Decodable {
    let generated_at: String
    let accounts: [Account]
}

struct Account: Decodable, Identifiable {
    let label: String
    let email: String
    let ok: Bool
    let error: String?
    let hint: String?
    let limits: [Limit]?
    let spend: Spend?
    var id: String { label }
}

struct Limit: Decodable, Identifiable {
    let label: String
    let percent: Double
    let severity: String
    let resets_at: String?
    var id: String { label }
}

struct Spend: Decodable {
    let percent: Double
    let severity: String
    let used: Double
    let limit: Double
    let currency: String
}

struct RunError: Error { let message: String }

// MARK: - Store (runs claude-usage, publishes the report)

final class UsageStore: ObservableObject {
    @Published var report: Report?
    @Published var statusError: String?     // failure to even run the script
    @Published var loading = false
    @Published var updatedAt: Date?

    private var timer: Timer?
    private let interval: TimeInterval = 300 // 5 min

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.runScript()
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                switch result {
                case .success(let report):
                    self.report = report
                    self.statusError = nil
                    self.updatedAt = Date()
                case .failure(let err):
                    self.statusError = err.message
                }
            }
        }
    }

    private static func runScript() -> Result<Report, RunError> {
        let home = NSHomeDirectory()
        // Login Items launch with a minimal PATH and a non-interactive shell, so
        // we can't rely on shell profiles. Build an explicit PATH (covers the
        // claude-usage symlink + the python3/security the script needs) and run
        // the script directly — no shell, no profile sourcing.
        var env = ProcessInfo.processInfo.environment
        let dirs = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
                    "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        env["PATH"] = (dirs + [env["PATH"] ?? ""]).joined(separator: ":")

        // Prefer the installed symlink; fall back to the repo copy beside the app.
        let fm = FileManager.default
        let candidates = ["\(home)/.local/bin/claude-usage",
                          Bundle.main.bundlePath + "/../claude-usage"]
        guard let script = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            return .failure(RunError(message: "claude-usage not found"))
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: script)
        p.arguments = ["--json"]
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
        } catch {
            return .failure(RunError(message: "can't launch claude-usage"))
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard !data.isEmpty else {
            let msg = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n").first.map(String.init)
            return .failure(RunError(message: msg?.isEmpty == false ? msg! : "no output from claude-usage"))
        }
        do {
            return .success(try JSONDecoder().decode(Report.self, from: data))
        } catch {
            return .failure(RunError(message: "bad data from claude-usage"))
        }
    }
}

// MARK: - Date helpers

func parseDate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let cleaned = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
    return f.date(from: cleaned)
}

func hhmm(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
}

func resetLabel(_ iso: String?) -> String {
    guard let d = parseDate(iso) else { return "" }
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "→ " + hhmm(d) }
    if cal.isDateInTomorrow(d) { return "→ tmrw " + hhmm(d) }
    let f = DateFormatter(); f.dateFormat = "d MMM"
    return "→ " + f.string(from: d)
}

func severityColor(_ severity: String, _ pct: Double) -> Color {
    if severity == "critical" || pct >= 90 { return .red }
    if severity == "warning"  || pct >= 70 { return .orange }
    return .green
}

// MARK: - Views

struct Bar: View {
    let percent: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(color)
                    .frame(width: max(3, geo.size.width * min(1, max(0, percent / 100))))
            }
        }
        .frame(height: 6)
    }
}

struct LimitRow: View {
    let title: String
    let percent: Double
    let severity: String
    let trailing: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(severityColor(severity, percent))
                Text(trailing)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(.white.opacity(0.45))
            }
            Bar(percent: percent, color: severityColor(severity, percent))
        }
    }
}

struct AccountView: View {
    let account: Account
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(account.label.capitalized)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Text(account.email)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1).truncationMode(.middle)
            }
            if account.ok {
                ForEach(account.limits ?? []) { lim in
                    LimitRow(title: lim.label, percent: lim.percent,
                             severity: lim.severity, trailing: resetLabel(lim.resets_at))
                }
                if let s = account.spend {
                    LimitRow(title: "Extra usage", percent: s.percent, severity: s.severity,
                             trailing: String(format: "%.2f/%.0f %@", s.used, s.limit, s.currency))
                }
            } else {
                HStack(alignment: .top, spacing: 5) {
                    Text("⚠").font(.system(size: 11)).foregroundColor(.yellow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.error ?? "unreachable")
                            .font(.system(size: 11)).foregroundColor(.yellow.opacity(0.9))
                        if let hint = account.hint, !hint.isEmpty {
                            Text(hint).font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
            }
        }
    }
}

struct WidgetView: View {
    @ObservedObject var store: UsageStore
    let onToggleTop: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("⚡").font(.system(size: 12))
                Text("Claude usage").font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if let u = store.updatedAt {
                    Text(hhmm(u)).font(.system(size: 10).monospacedDigit())
                        .foregroundColor(.white.opacity(0.4))
                }
                Button(action: { store.refresh() }) {
                    Image(systemName: store.loading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }

            if let err = store.statusError, store.report == nil {
                Text(err).font(.system(size: 11)).foregroundColor(.yellow)
            } else if let report = store.report {
                ForEach(Array(report.accounts.enumerated()), id: \.element.id) { idx, acct in
                    if idx > 0 {
                        Divider().background(Color.white.opacity(0.12))
                    }
                    AccountView(account: acct)
                }
            } else {
                Text("Loading…").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(14)
        .frame(width: 280)
        .contextMenu {
            Button("Refresh now") { store.refresh() }
            Button("Toggle stay-on-top") { onToggleTop() }
            Divider()
            Button("Quit") { onQuit() }
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = UsageStore()
    var panel: NSPanel!
    let defaults = UserDefaults.standard
    var onTop = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon

        onTop = defaults.bool(forKey: "onTop")

        let hosting = NSHostingView(rootView:
            WidgetView(store: store,
                       onToggleTop: { [weak self] in self?.toggleOnTop() },
                       onQuit: { NSApp.terminate(nil) }))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        let initial = NSRect(x: 0, y: 0, width: 280, height: 260)
        panel = NSPanel(contentRect: initial,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.contentView = effect
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.delegate = self
        applyLevel()

        // Restore saved position, else top-right of the main screen.
        if let s = defaults.string(forKey: "origin") {
            panel.setFrameOrigin(NSPointFromString(s))
        } else if let vis = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vis.maxX - initial.width - 24, y: vis.maxY - initial.height - 24))
        }
        panel.orderFrontRegardless()

        store.start()
        // Resize to fit content once SwiftUI has laid out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.fit(hosting) }
        store.$report.sink { [weak self] _ in
            DispatchQueue.main.async { self?.fit(hosting) }
        }.store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    private func fit(_ hosting: NSView) {
        let size = hosting.fittingSize
        guard size.height > 0 else { return }
        var f = panel.frame
        let dh = size.height - f.size.height
        f.origin.y -= dh            // grow/shrink from the top edge
        f.size = size
        panel.setFrame(f, display: true, animate: false)
    }

    func toggleOnTop() {
        onTop.toggle()
        defaults.set(onTop, forKey: "onTop")
        applyLevel()
    }

    private func applyLevel() {
        if onTop {
            panel.level = .floating
        } else {
            // Sit on the desktop: above the wallpaper/icons, below app windows.
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }

    func windowDidMove(_ notification: Notification) {
        defaults.set(NSStringFromPoint(panel.frame.origin), forKey: "origin")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
