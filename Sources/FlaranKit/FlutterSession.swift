import Foundation
import Observation

public enum SessionState: Equatable, Sendable {
    case starting, running, reloading, stopping, failed(String), exited

    /// One line for a row subtitle; the full text is in the log.
    public var summary: String {
        switch self {
        case .starting: "Starting…"
        case .running: "Running"
        case .reloading: "Reloading…"
        case .stopping: "Stopping…"
        case let .failed(message): message.split(separator: "\n").first.map(String.init) ?? "Failed"
        case .exited: "Stopped"
        }
    }
}

/// One `flutter run --machine` process for a (project, device) pair.
@Observable public final class FlutterSession: Identifiable {
    public let id = UUID()
    public let projectDir: URL
    public let device: DeviceInfo
    public private(set) var config: LaunchConfig = .defaultConfig
    public private(set) var state: SessionState = .exited
    public private(set) var progress: String?
    /// Set briefly after a reload/restart so the menu bar buttons can flash green/red.
    public private(set) var lastActionOK: Bool?
    public let log = LogStore()

    @ObservationIgnored private var process: DaemonProcess?
    @ObservationIgnored private var appId: String?
    @ObservationIgnored private var wsURI: String?
    @ObservationIgnored private var devToolsURL: URL?
    @ObservationIgnored private var stopRequested = false

    public init(projectDir: URL, device: DeviceInfo) {
        self.projectDir = projectDir
        self.device = device
    }

    public var title: String { "\(projectDir.lastPathComponent) · \(device.name)" }
    public var isActive: Bool { [.starting, .running, .reloading, .stopping].contains(state) }
    public var canReload: Bool { state == .running }

    /// Shows the run as starting right away, before the (async) launch begins.
    public func prepare(config: LaunchConfig) {
        guard process == nil else { return }
        self.config = config
        appId = nil; wsURI = nil; devToolsURL = nil; stopRequested = false
        progress = "Preparing…"
        if !log.lines.isEmpty { log.separator("Run \(config.name)") }
        state = .starting
    }

    public func start(config: LaunchConfig, globalFlutter: URL?, env: [String: String]) {
        guard process == nil else { return }
        if state != .starting || self.config != config { prepare(config: config) }

        let appDir = config.cwd.map { $0.hasPrefix("/") ? URL(filePath: $0) : projectDir.appending(path: $0) } ?? projectDir
        guard FileManager.default.fileExists(atPath: appDir.appending(path: "pubspec.yaml").path) else {
            return fail("No pubspec.yaml in \(appDir.path). Set \"cwd\" in launch.json to the Flutter app folder.")
        }
        let flutter: URL
        do { flutter = try resolveFlutter(appDir: appDir, root: projectDir, globalFlutter: globalFlutter) } catch {
            return fail(error.localizedDescription)
        }

        let argv = runArguments(config: config, deviceId: device.id)
        log.append("$ \(flutter.path) \(argv.joined(separator: " "))")
        let p = DaemonProcess(executable: flutter, arguments: argv, cwd: appDir,
                              env: env.merging(config.env ?? [:]) { $1 })
        p.onMessage = { [weak self] in self?.handle($0) }
        p.onStderr = { [weak self] in self?.log.append($0, flaggedError: true, quiet: true) }
        p.onExit = { [weak self] in self?.exited($0) }
        do { try p.start() } catch { return fail("Could not start flutter: \(error.localizedDescription)") }
        process = p
        progress = "Launching…"
    }

    public func reload() async { await restart(full: false) }
    public func restart() async { await restart(full: true) }

    public func stop() async {
        guard isActive, state != .stopping else { return }
        guard let process else {
            // Prepared but not launched yet: just cancel.
            log.append("Cancelled.")
            progress = nil
            state = .exited
            return
        }
        stopRequested = true
        state = .stopping
        if let appId {
            _ = await process.request("app.stop", ["appId": appId], timeout: .seconds(5))
        }
        process.terminate()
    }

    /// Stops and waits for the process to actually exit. False if it's still alive at the deadline.
    public func stopAndWait(timeout: Duration = .seconds(15)) async -> Bool {
        await stop()
        let deadline = ContinuousClock.now + timeout
        while isActive, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        return !isActive
    }

    public func terminateNow() { process?.terminateNow() }

    /// DevTools URL from the `app.devTools` event, else via `devtools.serve`.
    public func devToolsLink() async -> URL? {
        if let devToolsURL { return devToolsURL }
        guard let process, let wsURI else { return nil }
        let reply = await process.request("devtools.serve", timeout: .seconds(30))
        guard let r = reply.result as? [String: Any], let host = r["host"] as? String, let port = r["port"] as? Int,
              var comps = URLComponents(string: "http://\(host):\(port)/")
        else {
            log.append("Could not start DevTools: \(reply.error ?? "no address")", flaggedError: true)
            return nil
        }
        comps.queryItems = [URLQueryItem(name: "uri", value: wsURI)]
        devToolsURL = comps.url
        return devToolsURL
    }

    // MARK: private

    private func restart(full: Bool) async {
        guard canReload, let process, let appId else { return }
        let action = full ? "Hot restart" : "Hot reload"
        state = .reloading
        let reply = await process.request("app.restart",
                                          ["appId": appId, "fullRestart": full, "pause": false, "reason": "manual"])
        if state == .reloading { state = .running }
        let result = reply.result as? [String: Any]
        let code = result?["code"] as? Int ?? 0
        let message = result?["message"] as? String
        if let error = reply.error ?? (code != 0 ? message ?? "code \(code)" : nil) {
            log.append("\(action) failed: \(error)", flaggedError: true)
            flash(false)
        } else {
            log.append("\(action) done\(message.map { ": \($0)" } ?? "")")
            flash(true)
        }
    }

    private func flash(_ ok: Bool) {
        lastActionOK = ok
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.lastActionOK = nil
        }
    }

    private func handle(_ message: DaemonMessage) {
        switch message {
        case let .text(line):
            log.append(line)
        case let .event(name, params):
            switch name {
            case "app.start": appId = params["appId"] as? String
            case "app.debugPort": wsURI = params["wsUri"] as? String
            case "app.devTools": devToolsURL = (params["uri"] as? String).flatMap(URL.init(string:))
            case "app.started":
                if state == .starting { state = .running }
                progress = nil
            case "app.log": log.append(params["log"] as? String ?? "", flaggedError: params["error"] as? Bool ?? false)
            case "app.progress":
                let finished = params["finished"] as? Bool ?? false
                progress = finished ? nil : params["message"] as? String
                if let p = progress { log.append(p) }
            case "app.stop":
                if let error = params["error"] as? String { log.append(error, flaggedError: true) }
            case "app.webLaunchUrl":
                if let url = params["url"] as? String { log.append("Web app: \(url)") }
            case "daemon.logMessage":
                log.append(params["message"] as? String ?? "", flaggedError: params["level"] as? String == "error",
                           quiet: true)
            default: break
            }
        case .response: break  // handled by DaemonProcess
        }
    }

    private func exited(_ code: Int32) {
        process = nil
        progress = nil
        if stopRequested {
            log.append("Stopped.")
            state = .exited
        } else if state == .starting || code != 0 {
            fail("flutter exited with code \(code)\(state == .starting ? " before the app started" : "").")
        } else {
            log.append("App exited.")
            state = .exited
        }
    }

    private func fail(_ message: String) {
        log.append(message, flaggedError: true)
        progress = nil
        state = .failed(message)
    }
}
