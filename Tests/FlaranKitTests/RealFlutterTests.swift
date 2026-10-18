import Foundation
import Testing
@testable import FlaranKit

/// Opt-in end-to-end run against a real Flutter macOS app:
/// `FLARAN_FLUTTER_PROJECT=/path/to/app swift test --filter RealFlutter`
@Test(.enabled(if: ProcessInfo.processInfo.environment["FLARAN_FLUTTER_PROJECT"] != nil), .timeLimit(.minutes(5)))
func realFlutterRunReloadRestartStop() async throws {
    let project = URL(filePath: ProcessInfo.processInfo.environment["FLARAN_FLUTTER_PROJECT"]!)
    let main = project.appending(path: "lib/main.dart")
    let original = try String(contentsOf: main, encoding: .utf8)
    defer { try? original.write(to: main, atomically: true, encoding: .utf8) }

    let shell = await ShellEnvironment.load()
    let session = FlutterSession(projectDir: project, device: DeviceInfo(id: "macos", name: "macOS", platform: "darwin"))
    session.start(config: .defaultConfig, globalFlutter: shell.flutter, env: shell.env)
    for _ in 0..<1200 where session.state == .starting { try await Task.sleep(for: .milliseconds(100)) }
    #expect(session.state == .running, "log: \(session.log.lines.suffix(20).map(\.text))")

    await session.reload()
    #expect(session.lastActionOK == true)

    // Break the build method, then reload: the exception must surface as an error.
    try original.replacingOccurrences(of: "Widget build(BuildContext context) {",
                                      with: "Widget build(BuildContext context) { throw StateError('frb boom');")
        .write(to: main, atomically: true, encoding: .utf8)
    await session.reload()
    for _ in 0..<50 where !session.log.unseenErrors { try await Task.sleep(for: .milliseconds(100)) }
    #expect(session.log.lines.contains { $0.isError && $0.text.contains("frb boom") })

    try original.write(to: main, atomically: true, encoding: .utf8)
    await session.restart()
    #expect(session.lastActionOK == true)

    let devTools = await session.devToolsLink()
    #expect(devTools != nil)
    print("DevTools:", devTools?.absoluteString ?? "nil")

    await session.stop()
    for _ in 0..<100 where session.isActive { try await Task.sleep(for: .milliseconds(100)) }
    #expect(session.state == .exited)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FLARAN_FLUTTER_PROJECT"] != nil), .timeLimit(.minutes(2)))
func realDeviceDaemonListsDevicesAndEmulators() async throws {
    let shell = await ShellEnvironment.load()
    let service = DeviceService()
    service.start(flutter: try #require(shell.flutter), env: shell.env)
    for _ in 0..<300 where service.devices.isEmpty || service.emulators.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
    print("devices:", service.devices.map { "\($0.name) [\($0.id)]" })
    print("offline emulators:", service.offlineEmulators.map(\.name))
    #expect(service.devices.contains { $0.id == "macos" })
}
