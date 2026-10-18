import Foundation
import Observation

public struct DeviceInfo: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var platform: String
    public var isEmulator: Bool
    public var emulatorId: String?
    /// e.g. "Android 16 (API 36)", "macOS 27.0".
    public var sdk: String?

    public init(id: String, name: String, platform: String, isEmulator: Bool = false, emulatorId: String? = nil,
                sdk: String? = nil) {
        self.id = id; self.name = name; self.platform = platform
        self.isEmulator = isEmulator; self.emulatorId = emulatorId; self.sdk = sdk
    }

    init?(_ p: [String: Any]) {
        guard let id = p["id"] as? String else { return nil }
        self.init(id: id, name: p["name"] as? String ?? id, platform: p["platform"] as? String ?? "",
                  isEmulator: p["emulator"] as? Bool ?? false, emulatorId: p["emulatorId"] as? String,
                  sdk: p["sdk"] as? String)
    }
}

public struct EmulatorInfo: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var platformType: String

    public init(id: String, name: String, platformType: String) {
        self.id = id; self.name = name; self.platformType = platformType
    }
    /// Android emulators support cold boot; the iOS simulator entry doesn't.
    public var supportsColdBoot: Bool { platformType == "android" }
}

/// An iOS simulator from `xcrun simctl`. Xcode 27 replaced Simulator.app with Device Hub, and
/// Flutter offers just one generic "Start iOS Simulator", so we list and boot them ourselves.
public struct SimulatorInfo: Hashable, Identifiable, Sendable {
    public var id: String  // UDID, which is also the flutter device id once booted
    public var name: String
    public var runtime: String
    public var isBooted: Bool

    public init(id: String, name: String, runtime: String, isBooted: Bool) {
        self.id = id; self.name = name; self.runtime = runtime; self.isBooted = isBooted
    }
}

/// Available iOS simulators from `xcrun simctl list devices available -j`.
public func parseSimulators(_ json: Data) -> [SimulatorInfo] {
    guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
          let runtimes = root["devices"] as? [String: [[String: Any]]]
    else { return [] }
    return runtimes.keys.sorted().reversed().flatMap { key -> [SimulatorInfo] in
        // com.apple.CoreSimulator.SimRuntime.iOS-27-0 -> "iOS 27.0"
        guard let suffix = key.split(separator: ".").last, suffix.hasPrefix("iOS-") else { return [] }
        let runtime = "iOS " + suffix.dropFirst(4).replacingOccurrences(of: "-", with: ".")
        return (runtimes[key] ?? []).compactMap { d in
            guard d["isAvailable"] as? Bool ?? true, let udid = d["udid"] as? String else { return nil }
            return SimulatorInfo(id: udid, name: d["name"] as? String ?? udid, runtime: runtime,
                                 isBooted: d["state"] as? String == "Booted")
        }
    }
}

/// Android emulators report their system image ("sdk gphone16k arm64"); show the AVD name instead.
public func friendlyName(_ device: DeviceInfo, emulators: [EmulatorInfo]) -> DeviceInfo {
    guard let id = device.emulatorId, let avd = emulators.first(where: { $0.id == id }), avd.platformType == "android"
    else { return device }
    var renamed = device
    renamed.name = avd.name
    return renamed
}

/// Device discovery through one long-lived `flutter daemon`, like VS Code.
@Observable public final class DeviceService {
    public private(set) var devices: [DeviceInfo] = []
    public private(set) var emulators: [EmulatorInfo] = []
    public private(set) var simulators: [SimulatorInfo] = []
    /// True once the first device scan has finished, so "no devices" can be told apart from "still looking".
    public private(set) var isReady = false
    public private(set) var launching: Set<String> = []
    public private(set) var lastError: String?

    @ObservationIgnored private var daemon: DaemonProcess?
    @ObservationIgnored private var flutter: URL?
    @ObservationIgnored private var env: [String: String] = [:]

    public init() {}

    public var isStarted: Bool { flutter != nil }

    public func stop() { daemon?.terminateNow() }

    #if DEBUG
    /// Fixed device lists for README screenshots (no flutter daemon).
    public func showcase(devices: [DeviceInfo], simulators: [SimulatorInfo], emulators: [EmulatorInfo]) {
        self.devices = devices
        self.simulators = simulators
        self.emulators = emulators
        isReady = true
    }
    #endif

    /// Android emulators that aren't already running as a device. (iOS is listed per simulator instead.)
    public var offlineEmulators: [EmulatorInfo] {
        let running = Set(devices.compactMap(\.emulatorId))
        return emulators.filter { $0.platformType == "android" && !running.contains($0.id) }
    }

    /// iOS simulators not yet booted (a booted one shows up in `devices`).
    public var offlineSimulators: [SimulatorInfo] {
        let running = Set(devices.map(\.id))
        return simulators.filter { !$0.isBooted && !running.contains($0.id) }
    }

    public func start(flutter: URL, env: [String: String]) {
        self.flutter = flutter
        self.env = env
        refresh()
    }

    /// (Re)starts the daemon if it died, and re-reads the emulator list.
    public func refresh() {
        guard let flutter else { return }
        Task { await loadSimulators() }
        if let daemon, daemon.isRunning {
            Task { await loadEmulators(daemon) }
            return
        }
        let d = DaemonProcess(executable: flutter, arguments: ["daemon"],
                              cwd: FileManager.default.homeDirectoryForCurrentUser, env: env)
        d.onMessage = { [weak self] in self?.handle($0) }
        d.onExit = { [weak self] _ in
            self?.daemon = nil
            self?.devices = []
            self?.isReady = false
            self?.lastError = "Device discovery stopped. Refresh to restart it."
        }
        do { try d.start() } catch {
            lastError = "flutter daemon failed to start: \(error.localizedDescription)"
            return
        }
        daemon = d
        lastError = nil
        Task {
            _ = await d.request("device.enable")
            await loadEmulators(d)
            // flutter reports already-connected devices right after enable; give the events a beat to land.
            try? await Task.sleep(for: .seconds(1))
            isReady = true
        }
    }

    /// Boots an Android emulator. Returns an error message, or nil once flutter accepted the launch.
    public func launch(_ emulator: EmulatorInfo, coldBoot: Bool) async -> String? {
        guard let daemon else { return "Flutter isn't ready yet." }
        launching.insert(emulator.id)
        defer { launching.remove(emulator.id) }
        let reply = await daemon.request("emulator.launch", ["emulatorId": emulator.id, "coldBoot": coldBoot],
                                         timeout: .seconds(180))
        return reply.error
    }

    /// Boots an iOS simulator headless; the app opens Device Hub to show it.
    public func boot(_ simulator: SimulatorInfo) async {
        launching.insert(simulator.id)
        defer { launching.remove(simulator.id) }
        // Fails harmlessly with "already booted"; a real failure surfaces as the device never appearing.
        _ = await runCommand("/usr/bin/xcrun", ["simctl", "boot", simulator.id], env: env, timeout: 120)
        await loadSimulators()
    }

    private func loadSimulators() async {
        guard let out = await runCommand("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "-j"],
                                         env: env, timeout: 30)
        else { return }
        simulators = parseSimulators(Data(out.utf8))
    }

    private func loadEmulators(_ d: DaemonProcess) async {
        let reply = await d.request("emulator.getEmulators")
        emulators = (reply.result as? [[String: Any]] ?? []).compactMap { e in
            guard let id = e["id"] as? String else { return nil }
            return EmulatorInfo(id: id, name: e["name"] as? String ?? id, platformType: e["platformType"] as? String ?? "")
        }
        devices = devices.map { friendlyName($0, emulators: emulators) }
    }

    private func handle(_ message: DaemonMessage) {
        guard case let .event(name, params) = message, let raw = DeviceInfo(params) else { return }
        let device = friendlyName(raw, emulators: emulators)
        switch name {
        case "device.added":
            devices.removeAll { $0.id == device.id }
            devices.append(device)
        case "device.removed":
            devices.removeAll { $0.id == device.id }
        default: break
        }
    }
}
