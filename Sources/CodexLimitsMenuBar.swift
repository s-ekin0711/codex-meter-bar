import AppKit
import Darwin
import Foundation
import SwiftUI

@main
struct CodexLimitsMenuBarApp: App {
    @StateObject private var store = LimitsStore()

    var body: some Scene {
        MenuBarExtra {
            LimitsPanel(store: store)
                .frame(width: 320)
        } label: {
            MenuBarLabel(limits: store.limits, isRefreshing: store.isRefreshing)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class LimitsStore: ObservableObject {
    @Published private(set) var limits = CodexLimits.placeholder
    @Published private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?

    init() {
        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000_000)
                self?.refresh()
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func refresh() {
        if isRefreshing {
            return
        }
        isRefreshing = true
        Task {
            let next = await Task.detached(priority: .utility) {
                CodexLimitsReader.read()
            }.value
            self.limits = next
            self.isRefreshing = false
        }
    }
}

struct CodexLimits {
    let plan: String?
    let fiveHour: LimitWindow?
    let weekly: LimitWindow?
    let updatedAt: Date
    let error: String?

    static let placeholder = CodexLimits(
        plan: nil,
        fiveHour: nil,
        weekly: nil,
        updatedAt: Date(),
        error: nil
    )
}

struct LimitWindow {
    let title: String
    let usedPercent: Int
    let resetDate: Date?

    var remainingPercent: Int {
        max(0, 100 - usedPercent)
    }

    var progress: Double {
        Double(remainingPercent) / 100.0
    }

    var statusColor: Color {
        switch remainingPercent {
        case 0..<20:
            return .red
        case 20..<50:
            return .orange
        default:
            return .accentColor
        }
    }
}

struct MenuBarLabel: View {
    let limits: CodexLimits
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarRingImage.make(
                remainingPercent: limits.fiveHour?.remainingPercent,
                isRefreshing: isRefreshing,
                hasError: limits.error != nil
            ))
            Text(menuText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
    }

    private var menuText: String {
        if let remaining = limits.fiveHour?.remainingPercent {
            return "\(remaining)%"
        }
        if limits.error != nil {
            return "!"
        }
        return "--"
    }
}

enum MenuBarRingImage {
    static func make(remainingPercent: Int?, isRefreshing: Bool, hasError: Bool) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high

        let rect = NSRect(x: 2, y: 2, width: 12, height: 12)
        let background = NSBezierPath(ovalIn: rect)
        NSColor.secondaryLabelColor.withAlphaComponent(0.34).setStroke()
        background.lineWidth = 2.6
        background.stroke()

        if hasError {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.systemOrange,
                .paragraphStyle: paragraph
            ]
            NSString(string: "!").draw(
                in: NSRect(x: 0, y: 2.5, width: size.width, height: 11),
                withAttributes: attrs
            )
            return image
        }

        let remaining = remainingPercent.map { max(0, min(100, $0)) } ?? 0
        let progress = max(0.02, Double(remaining) / 100.0)
        ringColor(for: remainingPercent).setStroke()
        let path = NSBezierPath()
        path.appendArc(
            withCenter: NSPoint(x: 8, y: 8),
            radius: 6,
            startAngle: 90,
            endAngle: 90 - 360 * progress,
            clockwise: true
        )
        path.lineWidth = 2.7
        path.lineCapStyle = .round
        path.stroke()

        if isRefreshing {
            NSColor.labelColor.withAlphaComponent(0.88).setFill()
            NSBezierPath(ovalIn: NSRect(x: 7, y: 7, width: 2, height: 2)).fill()
        }

        return image
    }

    private static func ringColor(for remainingPercent: Int?) -> NSColor {
        guard let remainingPercent else {
            return NSColor.secondaryLabelColor
        }
        switch remainingPercent {
        case 0..<20:
            return NSColor.systemRed
        case 20..<50:
            return NSColor.systemOrange
        default:
            return NSColor.systemBlue
        }
    }
}

struct LimitsPanel: View {
    @ObservedObject var store: LimitsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let error = store.limits.error {
                ErrorView(message: error) {
                    store.refresh()
                }
            } else {
                VStack(spacing: 12) {
                    LimitCard(
                        icon: "clock",
                        tint: store.limits.fiveHour?.statusColor ?? .accentColor,
                        window: store.limits.fiveHour,
                        fallbackTitle: "5 小时额度"
                    )
                    LimitCard(
                        icon: "calendar",
                        tint: store.limits.weekly?.statusColor ?? .accentColor,
                        window: store.limits.weekly,
                        fallbackTitle: "1 周额度"
                    )
                }

                footer
            }
        }
        .padding(18)
        .background(.regularMaterial)
        .task {
            store.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex 用量")
                    .font(.system(size: 18, weight: .semibold))
                Text(planText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help("刷新")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("更新于 \(store.limits.updatedAt, style: .time)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("退出") {
                NSApp.terminate(nil)
            }
            .font(.system(size: 11))
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    private var planText: String {
        if store.isRefreshing {
            return "正在刷新"
        }
        if let plan = store.limits.plan, !plan.isEmpty {
            return plan.capitalized
        }
        return "每 3 分钟自动刷新"
    }
}

struct LimitCard: View {
    let icon: String
    let tint: Color
    let window: LimitWindow?
    let fallbackTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                Text(window?.title ?? fallbackTitle)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(percentText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            ProgressView(value: window?.progress ?? 0)
                .tint(tint)
                .controlSize(.small)

            Text(resetText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var percentText: String {
        guard let window else {
            return "--%"
        }
        return "\(window.remainingPercent)%"
    }

    private var resetText: String {
        guard let resetDate = window?.resetDate else {
            return "等待数据"
        }
        if resetDate <= Date() {
            return "即将重置"
        }
        if Calendar.current.isDateInToday(resetDate) {
            return "今天 \(resetDate.formatted(date: .omitted, time: .shortened)) 重置"
        }
        if Calendar.current.isDateInTomorrow(resetDate) {
            return "明天 \(resetDate.formatted(date: .omitted, time: .shortened)) 重置"
        }
        return "\(resetDate.formatted(date: .abbreviated, time: .shortened)) 重置"
    }
}

struct ErrorView: View {
    let message: String
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("重新读取") {
                refresh()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

enum CodexLimitsReader {
    static func read() -> CodexLimits {
        do {
            let result = try callCodexAppServer()
            let limits = parse(result: result, updatedAt: Date())
            try writeCache(result: result)
            return limits
        } catch {
            if let cached = try? readCachedLimits() {
                return cached
            }
            return CodexLimits(
                plan: nil,
                fiveHour: nil,
                weekly: nil,
                updatedAt: Date(),
                error: String(describing: error)
            )
        }
    }

    private static func callCodexAppServer() throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath())
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = codexEnvironment()

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        let reader = JSONLineReader(
            stdout: stdout.fileHandleForReading,
            stderr: stderr.fileHandleForReading
        )
        defer {
            try? stdin.fileHandleForWriting.close()
            reader.stop()
            if process.isRunning {
                process.terminate()
            }
        }

        try writeJSON([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "codex-limits-menubar",
                    "version": "0.1.0"
                ],
                "capabilities": [
                    "experimentalApi": true
                ]
            ]
        ], to: stdin.fileHandleForWriting)
        _ = try reader.waitForMessage(id: 1, process: process, deadline: Date().addingTimeInterval(15))

        try writeJSON([
            "id": 2,
            "method": "account/rateLimits/read"
        ], to: stdin.fileHandleForWriting)

        let message = try reader.waitForMessage(id: 2, process: process, deadline: Date().addingTimeInterval(15))
        if let error = message["error"] {
            throw MenuBarError.codexServerError(serverErrorDescription(error))
        }
        guard let result = message["result"] as? [String: Any] else {
            throw MenuBarError.rateLimitsUnavailable
        }
        return result
    }

    private static func readCachedLimits() throws -> CodexLimits {
        let data = try Data(contentsOf: cacheURL())
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = object["result"] as? [String: Any]
        else {
            throw MenuBarError.rateLimitsUnavailable
        }
        let updatedAt = number(object["updatedAt"])
            .map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        return parse(result: result, updatedAt: updatedAt)
    }

    private static func writeCache(result: [String: Any]) throws {
        let url = cacheURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload: [String: Any] = [
            "updatedAt": Int(Date().timeIntervalSince1970),
            "result": result
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
    }

    private static func parse(result: [String: Any], updatedAt: Date) -> CodexLimits {
        let bucket = pickCodexBucket(from: result)
        return CodexLimits(
            plan: bucket["planType"] as? String,
            fiveHour: parseWindow(bucket["primary"], fallbackTitle: "5 小时额度"),
            weekly: parseWindow(bucket["secondary"], fallbackTitle: "1 周额度"),
            updatedAt: updatedAt,
            error: nil
        )
    }

    private static func pickCodexBucket(from result: [String: Any]) -> [String: Any] {
        if
            let buckets = result["rateLimitsByLimitId"] as? [String: Any],
            let codex = buckets["codex"] as? [String: Any]
        {
            return codex
        }
        return (result["rateLimits"] as? [String: Any]) ?? result
    }

    private static func parseWindow(_ value: Any?, fallbackTitle: String) -> LimitWindow? {
        guard let dict = value as? [String: Any] else {
            return nil
        }
        guard let usedPercent = number(dict["usedPercent"]) else {
            return nil
        }
        let duration = number(dict["windowDurationMins"])
        let title: String
        switch duration {
        case 300:
            title = "5 小时额度"
        case 10080:
            title = "1 周额度"
        default:
            title = fallbackTitle
        }
        return LimitWindow(
            title: title,
            usedPercent: usedPercent,
            resetDate: number(dict["resetsAt"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private static func cacheURL() -> URL {
        let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: realHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        return applicationSupportURL
            .appendingPathComponent("CodexLimitsMenuBar", isDirectory: true)
            .appendingPathComponent("rate-limits.json")
    }

    private static func codexPath() -> String {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? "/Applications/Codex.app/Contents/Resources/codex"
    }

    private static func codexEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = realHomeDirectory()
        environment["HOME"] = home
        environment["CODEX_HOME"] = "\(home)/.codex"
        environment["PATH"] = "/Applications/Codex.app/Contents/Resources:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if environment["USER"] == nil {
            environment["USER"] = NSUserName()
        }
        if environment["LOGNAME"] == nil {
            environment["LOGNAME"] = NSUserName()
        }
        return environment
    }

    private static func realHomeDirectory() -> String {
        if
            let passwd = getpwuid(getuid()),
            let directory = passwd.pointee.pw_dir
        {
            let path = String(cString: directory)
            if !path.isEmpty {
                return path
            }
        }
        return NSHomeDirectory()
    }

    private static func writeJSON(_ object: [String: Any], to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let string = String(data: data, encoding: .utf8) else {
            throw MenuBarError.rateLimitsUnavailable
        }
        handle.write(Data((string + "\n").utf8))
    }

    private static func serverErrorDescription(_ error: Any) -> String {
        if
            let dict = error as? [String: Any],
            let message = dict["message"] as? String
        {
            return message
        }
        return String(describing: error)
    }

    static func number(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }
}

final class JSONLineReader {
    private let stdout: FileHandle
    private let stderr: FileHandle
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var stdoutBuffer = Data()
    private var messages: [[String: Any]] = []
    private var stderrText = ""

    init(stdout: FileHandle, stderr: FileHandle) {
        self.stdout = stdout
        self.stderr = stderr
        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            self?.appendStdout(data)
        }
        stderr.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            self?.appendStderr(data)
        }
    }

    func stop() {
        stdout.readabilityHandler = nil
        stderr.readabilityHandler = nil
    }

    func waitForMessage(id: Int, process: Process, deadline: Date) throws -> [String: Any] {
        while Date() < deadline {
            if let message = takeMessage(id: id) {
                return message
            }
            if !process.isRunning {
                if let message = takeMessage(id: id) {
                    return message
                }
                let stderr = takeStderrText()
                if !stderr.isEmpty {
                    throw MenuBarError.codexServerError(stderr)
                }
                throw MenuBarError.rateLimitsUnavailable
            }
            let milliseconds = max(1, min(200, Int(deadline.timeIntervalSinceNow * 1000)))
            _ = signal.wait(timeout: .now() + .milliseconds(milliseconds))
        }
        if process.isRunning {
            process.terminate()
        }
        throw MenuBarError.timeout
    }

    private func appendStdout(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        stdoutBuffer.append(data)
        let newline = Data([0x0A])
        while let range = stdoutBuffer.range(of: newline) {
            let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<range.lowerBound)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex..<range.upperBound)
            guard
                !lineData.isEmpty,
                let message = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else {
                continue
            }
            messages.append(message)
            signal.signal()
        }
    }

    private func appendStderr(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        if let text = String(data: data, encoding: .utf8) {
            stderrText += text
            signal.signal()
        }
    }

    private func takeMessage(id: Int) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = messages.firstIndex(where: { CodexLimitsReader.number($0["id"]) == id }) else {
            return nil
        }
        return messages.remove(at: index)
    }

    private func takeStderrText() -> String {
        lock.lock()
        defer { lock.unlock() }
        let text = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        stderrText = ""
        return text
    }
}

enum MenuBarError: Error, CustomStringConvertible {
    case codexServerError(String)
    case rateLimitsUnavailable
    case timeout

    var description: String {
        switch self {
        case .codexServerError(let message):
            return message
        case .rateLimitsUnavailable:
            return "未能读取 Codex 用量。"
        case .timeout:
            return "读取 Codex 用量超时。"
        }
    }
}
