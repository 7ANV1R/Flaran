import AppKit
import FlaranKit
import Observation
import SwiftUI

/// Where the panel is. Sub-pages slide in from the right, like Control Center.
enum Page: Hashable {
    case home
    case logs(UUID)
    case projects
    case configs(URL)
    case devices(URL, LaunchConfig)
}

/// An emulator or simulator being booted for a run. Shown as its own row until the device
/// comes online (then it becomes a normal session) or fails.
struct PendingBoot: Identifiable {
    let id = UUID()
    let deviceName: String
    let project: URL
    var failure: String?
}

@Observable final class AppModel {
    var sessions: [FlutterSession] = []
    var pendingBoots: [PendingBoot] = []
    var selectedID: UUID?
    private(set) var page: Page = .home
    /// Direction of the last navigation, for the slide transition.
    private(set) var forward = true
    private(set) var recentProjects: [URL]
    private(set) var flutterMissing = false
    private(set) var isQuitting = false
    var hotkeysEnabled: Bool {
        didSet {
            defaults.set(hotkeysEnabled, forKey: "hotkeysEnabled")
            hotKeys.setEnabled(hotkeysEnabled)
        }
    }
    let devices = DeviceService()

    /// Set by the status bar: hides/shows the panel around modal dialogs.
    @ObservationIgnored var setPanelVisible: (Bool) -> Void = { _ in }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let shell = Task { await ShellEnvironment.load() }
    @ObservationIgnored private let hotKeys = HotKeys()

    /// `startDevices: false` and a separate `defaults` suite are for the debug showcase.
    init(defaults: UserDefaults = .standard, startDevices: Bool = true) {
        self.defaults = defaults
        // ponytail: one-time carry-over from the pre-rename bundle id; delete after a release or two.
        let legacy = defaults == .standard
            ? UserDefaults(suiteName: "dev.rivnat.FlutterRunBar")?.stringArray(forKey: "recentProjects") : nil
        recentProjects = (defaults.stringArray(forKey: "recentProjects") ?? legacy ?? [])
            .map { URL(filePath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        hotkeysEnabled = defaults.bool(forKey: "hotkeysEnabled")
        hotKeys.onReload = { [weak self] in Task { await self?.selected?.reload() } }
        hotKeys.onRestart = { [weak self] in Task { await self?.selected?.restart() } }
        hotKeys.setEnabled(hotkeysEnabled)
        if startDevices { Task { await startDeviceDaemon() } }
    }

    /// The run that reload, restart and the hotkeys act on: the picked one while it's alive, else any live one.
    var selected: FlutterSession? {
        let picked = sessions.first { $0.id == selectedID }
        if picked?.isActive == true { return picked }
        return sessions.first(where: \.isActive) ?? picked ?? sessions.first
    }
    var hasUnseenErrors: Bool { sessions.contains { $0.log.unseenErrors } }
    var activeCount: Int { sessions.count { $0.isActive } }

    // MARK: navigation

    /// Closing on a log page goes home, so a hidden log view can't mark new errors as seen.
    func panelClosed() {
        if case .logs = page { page = .home }
    }

    func go(_ page: Page) {
        forward = depth(page) >= depth(self.page)
        withAnimation(.snappy(duration: 0.28)) { self.page = page }
    }

    /// Picking a project skips the config step when there's only one.
    func choose(project: URL) {
        let configs = loadLaunchConfigs(projectDir: project)
        go(configs.count == 1 ? .devices(project, configs[0]) : .configs(project))
    }

    private func depth(_ page: Page) -> Int {
        switch page {
        case .home: 0
        case .logs, .projects: 1
        case .configs: 2
        case .devices: 3
        }
    }

    // MARK: running

    /// Starts (or restarts) a run. The row shows "Preparing…" immediately; the panel goes home so
    /// you watch it come up instead of staring at the device list.
    func run(_ project: URL, _ config: LaunchConfig, _ device: DeviceInfo, navigate: Bool = true) {
        guard !isQuitting else { return }
        remember(project: project, config: config, device: device)
        let session = sessions.first { $0.projectDir == project && $0.device.id == device.id } ?? {
            let s = FlutterSession(projectDir: project, device: device)
            sessions.append(s)
            return s
        }()
        selectedID = session.id
        if navigate, page != .home { go(.home) }
        let wasActive = session.isActive
        if !wasActive { session.prepare(config: config) }
        Task {
            if wasActive {
                guard await session.stopAndWait() else {
                    return session.log.append("Previous run is still stopping; try again in a moment.", flaggedError: true)
                }
                session.prepare(config: config)
            }
            let env = await shell.value
            // Stop pressed while we waited on the shell, a newer run took over, or we're quitting.
            guard session.state == .starting, session.config == config, !isQuitting else { return }
            session.start(config: config, globalFlutter: env.flutter, env: env.env)
        }
    }

    func bootAndRun(_ project: URL, _ config: LaunchConfig, _ emulator: EmulatorInfo, coldBoot: Bool) {
        boot(named: emulator.name, project: project, config: config, boot: { [devices] in
            await devices.launch(emulator, coldBoot: coldBoot)
        }, match: { $0.emulatorId == emulator.id })
    }

    func bootAndRun(_ project: URL, _ config: LaunchConfig, _ simulator: SimulatorInfo) {
        boot(named: simulator.name, project: project, config: config, boot: { [devices] in
            await devices.boot(simulator)
            Self.showSimulatorApp()
            return nil
        }, match: { $0.id == simulator.id })
    }

    func cancelBoot(_ boot: PendingBoot) { pendingBoots.removeAll { $0.id == boot.id } }

    /// True while a boot for this device is pending (its row shouldn't start a second one).
    func isBooting(_ deviceName: String) -> Bool {
        pendingBoots.contains { $0.deviceName == deviceName && $0.failure == nil }
    }

    private func boot(named name: String, project: URL, config: LaunchConfig,
                      boot: @escaping () async -> String?, match: @escaping (DeviceInfo) -> Bool) {
        guard !isQuitting, !isBooting(name) else { return }
        let pending = PendingBoot(deviceName: name, project: project)
        pendingBoots.append(pending)
        go(.home)
        Task {
            if let error = await boot() { return fail(pending.id, "Couldn't start \(name): \(error)") }
            for _ in 0..<240 {  // two minutes
                guard pendingBoots.contains(where: { $0.id == pending.id }) else { return }  // cancelled
                if let device = devices.devices.first(where: match) {
                    pendingBoots.removeAll { $0.id == pending.id }
                    return run(project, config, device, navigate: false)  // don't pull the user off their page
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            fail(pending.id, "\(name) didn't come online within 2 minutes.")
        }
    }

    private func fail(_ id: UUID, _ message: String) {
        guard let i = pendingBoots.firstIndex(where: { $0.id == id }) else { return }
        pendingBoots[i].failure = message
    }

    /// Xcode 27 replaced Simulator.app with Device Hub; open whichever this Xcode has, in the background.
    private static func showSimulatorApp() {
        for bundleID in ["com.apple.dt.Devices", "com.apple.iphonesimulator"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                return NSWorkspace.shared.openApplication(at: url, configuration: config)
            }
        }
    }

    func runAgain(_ session: FlutterSession) { run(session.projectDir, session.config, session.device) }

    /// The session already running this project on this device, if any (the picker marks it).
    func session(for project: URL, on device: DeviceInfo) -> FlutterSession? {
        sessions.first { $0.projectDir == project && $0.device.id == device.id && $0.isActive }
    }

    func dismiss(_ session: FlutterSession) {
        guard !session.isActive else { return }
        sessions.removeAll { $0.id == session.id }
        if selectedID == session.id { selectedID = sessions.first?.id }
    }

    /// Graceful stop of every session (app.stop, then process-group kill), then quit.
    func quit() {
        isQuitting = true
        pendingBoots.removeAll()
        Task {
            await withTaskGroup { group in
                for s in sessions where s.isActive {
                    group.addTask { _ = await s.stopAndWait(timeout: .seconds(8)) }
                }
            }
            NSApp.terminate(nil)
        }
    }

    /// Last resort on any termination path (logout, restart): no awaiting possible here.
    func terminateAll() {
        sessions.forEach { $0.terminateNow() }
        devices.stop()
    }

    func openDevTools(_ session: FlutterSession) {
        Task {
            if let url = await session.devToolsLink() { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: projects & memory

    /// Folder picker, then straight on to that project's devices. The panel steps aside while
    /// the dialog is up and comes back where the flow continues.
    func openFolder() {
        let previous = NSWorkspace.shared.frontmostApplication
        setPanelVisible(false)
        defer {
            previous?.activate()  // hand focus back to the terminal/editor
            setPanelVisible(true)
        }
        NSApp.activate()
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.prompt = "Add Project"
        picker.message = "Choose a Flutter project folder"
        guard picker.runModal() == .OK, let url = picker.url else { return }

        let configs = loadLaunchConfigs(projectDir: url)
        let hasApp = configs.contains { c in
            let dir = c.cwd.map { $0.hasPrefix("/") ? URL(filePath: $0) : url.appending(path: $0) } ?? url
            return FileManager.default.fileExists(atPath: dir.appending(path: "pubspec.yaml").path)
        }
        guard hasApp else {
            let alert = NSAlert()
            alert.messageText = "“\(url.lastPathComponent)” isn’t a Flutter project"
            alert.informativeText = "Flaran couldn’t find a pubspec.yaml there. Pick the app folder, or add a launch.json whose \"cwd\" points to it."
            alert.runModal()
            return
        }
        addRecent(url)
        choose(project: url)
    }

    func removeRecent(_ project: URL) {
        recentProjects.removeAll { $0 == project }
        defaults.set(recentProjects.map(\.path), forKey: "recentProjects")
    }

    func lastConfigName(_ project: URL) -> String? { defaults.string(forKey: "lastConfig.\(project.path)") }
    func lastDeviceID(_ project: URL) -> String? { defaults.string(forKey: "lastDevice.\(project.path)") }

    /// "Run what I ran last time": most recent project, its last config, its last device if connected.
    /// Hidden while that run is already listed; its row has its own stop / run-again controls.
    var quickRun: (project: URL, config: LaunchConfig, device: DeviceInfo)? {
        guard let project = recentProjects.first,
              let device = devices.devices.first(where: { $0.id == lastDeviceID(project) }),
              !sessions.contains(where: { $0.projectDir == project && $0.device.id == device.id })
        else { return nil }
        let configs = loadLaunchConfigs(projectDir: project)
        return (project, configs.first { $0.name == lastConfigName(project) } ?? configs[0], device)
    }

    private func remember(project: URL, config: LaunchConfig, device: DeviceInfo) {
        addRecent(project)
        defaults.set(config.name, forKey: "lastConfig.\(project.path)")
        defaults.set(device.id, forKey: "lastDevice.\(project.path)")
    }

    private func addRecent(_ url: URL) {
        recentProjects.removeAll { $0 == url }
        recentProjects.insert(url, at: 0)
        recentProjects = Array(recentProjects.prefix(15))
        defaults.set(recentProjects.map(\.path), forKey: "recentProjects")
        if !devices.isStarted, !devices.isReady { Task { await startDeviceDaemon() } }
    }

    private func startDeviceDaemon() async {
        let env = await shell.value
        // No global flutter? Borrow the SDK of the most recent project.
        let flutter = env.flutter ?? recentProjects.lazy.compactMap {
            try? resolveFlutter(appDir: $0, root: $0, globalFlutter: nil)
        }.first
        flutterMissing = flutter == nil
        if let flutter { devices.start(flutter: flutter, env: env.env) }
    }
}
