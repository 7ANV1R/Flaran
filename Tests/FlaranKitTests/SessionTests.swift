import Foundation
import Testing
@testable import FlaranKit

/// A project whose FVM pin is a fake `flutter` script, so sessions run without a real SDK.
private func fakeProject(script: String) throws -> URL {
    let root = try tempDir()
    try write(root, "pubspec.yaml", "name: demo\n")
    let flutter = root.appending(path: ".fvm/flutter_sdk/bin/flutter")
    try write(root, ".fvm/flutter_sdk/bin/flutter", "#!/bin/bash\n" + script)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: flutter.path)
    return root
}

private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(25)) }
}

private let device = DeviceInfo(id: "macos", name: "macOS", platform: "darwin")

@Test func buildFailureBeforeStartIsFailedWithLogs() async throws {
    let root = try fakeProject(script: """
    echo "Launching lib/main.dart on macOS in debug mode..."
    echo "lib/main.dart:3:1: Error: Expected ';' after this." >&2
    exit 1
    """)
    let session = FlutterSession(projectDir: root, device: device)
    session.start(config: .defaultConfig, globalFlutter: nil, env: ProcessInfo.processInfo.environment)
    await waitUntil { !session.isActive }
    guard case .failed = session.state else { Issue.record("state \(session.state) log \(session.log.lines.map(\.text))"); return }
    #expect(session.log.unseenErrors)
    #expect(session.log.lines.contains { $0.isError && $0.text.contains("Expected ';'") })
    #expect(session.log.lines.contains { $0.text.contains("Launching lib/main.dart") })
}

@Test func hotReloadRoundTripAndFailure() async throws {
    // Answers the first app.restart with success, the second with a compile error.
    let root = try fakeProject(script: """
    echo '[{"event":"app.start","params":{"appId":"A1"}}]'
    echo '[{"event":"app.started","params":{"appId":"A1"}}]'
    n=0
    while read -r line; do
      id=$(echo "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
      n=$((n+1))
      if [ $n -eq 1 ]; then echo "[{\\"id\\":$id,\\"result\\":{\\"code\\":0,\\"message\\":\\"Reloaded 1 of 1 libraries\\"}}]"
      else echo "[{\\"id\\":$id,\\"result\\":{\\"code\\":1,\\"message\\":\\"Compilation failed\\"}}]"; exit 0; fi
    done
    """)
    let session = FlutterSession(projectDir: root, device: device)
    session.start(config: .defaultConfig, globalFlutter: nil, env: ProcessInfo.processInfo.environment)
    await waitUntil { session.state == .running }
    #expect(session.state == .running)

    await session.reload()
    #expect(session.lastActionOK == true)
    #expect(session.log.lines.last?.text == "Hot reload done: Reloaded 1 of 1 libraries")
    #expect(!session.log.unseenErrors)

    await session.restart()
    #expect(session.lastActionOK == false)
    #expect(session.log.lines.contains { $0.isError && $0.text == "Hot restart failed: Compilation failed" })
}

@Test func missingPinnedSdkFailsWithoutRunning() throws {
    let root = try tempDir()
    try write(root, "pubspec.yaml", "name: demo\n")
    try write(root, ".vscode/settings.json", #"{"dart.flutterSdkPath": "/nope/flutter"}"#)
    let session = FlutterSession(projectDir: root, device: device)
    session.start(config: .defaultConfig, globalFlutter: URL(filePath: "/usr/bin/false"), env: [:])
    guard case let .failed(message) = session.state else { Issue.record("state \(session.state)"); return }
    #expect(message.contains("/nope/flutter"))
}

@Test func stopKillsWholeProcessGroupAndWaits() async throws {
    // Like gradle/xcodebuild: a grandchild that ignores the parent's death. Flutter itself ignores app.stop.
    let marker = UUID().uuidString
    let root = try fakeProject(script: """
    trap '' TERM
    sleep 300 &
    echo '[{"event":"app.start","params":{"appId":"A1"}}]'
    echo '[{"event":"app.started","params":{"appId":"A1"}}]'
    exec -a frb-\(marker) sleep 300
    """)
    let session = FlutterSession(projectDir: root, device: device)
    session.start(config: .defaultConfig, globalFlutter: nil, env: ProcessInfo.processInfo.environment)
    await waitUntil { session.state == .running }
    let stopped = await session.stopAndWait()
    #expect(stopped)
    #expect(session.state == .exited)
    let pgrep = Process()
    pgrep.executableURL = URL(filePath: "/usr/bin/pgrep")
    pgrep.arguments = ["-f", "frb-\(marker)"]
    try pgrep.run()
    pgrep.waitUntilExit()
    #expect(pgrep.terminationStatus == 1, "process still alive after stop")
}

@Test func prepareShowsStartingImmediatelyThenStartReusesIt() throws {
    let root = try fakeProject(script: "sleep 5\n")
    let session = FlutterSession(projectDir: root, device: device)
    session.prepare(config: .defaultConfig)
    #expect(session.state == .starting)
    #expect(session.progress == "Preparing…")
    session.start(config: .defaultConfig, globalFlutter: nil, env: ProcessInfo.processInfo.environment)
    #expect(session.state == .starting)
    #expect(session.log.lines.filter { $0.text.hasPrefix("────") }.isEmpty)  // no separator on a first run
}

@Test func stoppingStateIsVisibleWhileStopping() async throws {
    let root = try fakeProject(script: """
    echo '[{"event":"app.start","params":{"appId":"A1"}}]'
    echo '[{"event":"app.started","params":{"appId":"A1"}}]'
    while read -r line; do :; done
    """)
    let session = FlutterSession(projectDir: root, device: device)
    session.start(config: .defaultConfig, globalFlutter: nil, env: ProcessInfo.processInfo.environment)
    await waitUntil { session.state == .running }
    let stop = Task { await session.stop() }
    await waitUntil { session.state != .running }
    #expect(session.state == .stopping)
    #expect(session.isActive && !session.canReload)
    await stop.value
    await waitUntil { !session.isActive }
    #expect(session.state == .exited)
}

@Test func failureSummaryIsFirstLine() {
    #expect(SessionState.failed("Gradle task assembleDebug failed with exit code 1.\nmore").summary
            == "Gradle task assembleDebug failed with exit code 1.")
}
