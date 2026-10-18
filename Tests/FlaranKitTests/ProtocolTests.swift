import Foundation
import Testing
@testable import FlaranKit

@Test func parsesEvent() {
    guard case let .event(name, params) = DaemonMessage.parse(#"[{"event":"app.start","params":{"appId":"abc","deviceId":"macos"}}]"#)
    else { Issue.record("not an event"); return }
    #expect(name == "app.start")
    #expect(params["appId"] as? String == "abc")
}

@Test func parsesResponse() {
    guard case let .response(id, result, error) = DaemonMessage.parse(#"[{"id":3,"result":{"code":1,"message":"x"}}]"#)
    else { Issue.record("not a response"); return }
    #expect(id == 3)
    #expect((result as? [String: Any])?["code"] as? Int == 1)
    #expect(error == nil)
}

@Test func plainAndBracketTextIsText() {
    for line in ["[INFO] gradle", "[", "Running Gradle task 'assembleDebug'...", "[{broken"] {
        guard case .text(line) = DaemonMessage.parse(line) else { Issue.record("\(line) misparsed"); continue }
    }
}

@Test func encodesRequestLine() throws {
    let data = encodeRequest(id: 7, method: "app.restart", params: ["appId": "a", "fullRestart": true])
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.hasPrefix("[{") && text.hasSuffix("}]\n"))
    let obj = try #require((try JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first)
    #expect(obj["id"] as? Int == 7)
    #expect(obj["method"] as? String == "app.restart")
}

@Test func runArgumentsMatchDartCodeOrder() {
    var config = LaunchConfig(name: "dev")
    config.flutterMode = "profile"
    config.toolArgs = ["--flavor", "dev"]
    config.program = "lib/main_dev.dart"
    config.args = ["--dart-define=A=1"]
    #expect(runArguments(config: config, deviceId: "emulator-5554") == [
        "run", "--machine", "-d", "emulator-5554", "--profile",
        "--dart-define=flutter.inspector.structuredErrors=false",
        "--flavor", "dev", "--target", "lib/main_dev.dart", "--dart-define=A=1",
    ])
    config.deviceId = "macos"
    config.flutterMode = nil
    #expect(runArguments(config: config, deviceId: "emulator-5554").prefix(4) == ["run", "--machine", "-d", "macos"])
}

@Test func classifierFlagsWholeExceptionBlock() {
    var c = ErrorClassifier()
    let lines = [
        "══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════════════════",
        "The following assertion was thrown building Foo:",
        "boom",
        "═════════════════════════════════════════════════════════════",
        "flutter: hello",
        "Another exception was thrown: boom again",
        "normal",
    ]
    let flags = lines.map { c.classify($0, flaggedError: false) }
    #expect(flags == [true, true, true, true, false, true, false])
    let flagged = c.classify("x", flaggedError: true)
    #expect(flagged)
}

@Test func logStoreCapsAndTracksErrors() {
    let log = LogStore()
    for i in 0..<10_050 { log.append("line \(i)") }
    // Trims in batches so the log view isn't redrawn on every line once full.
    #expect(log.lines.count <= LogStore.capacity && log.lines.count > LogStore.capacity - LogStore.trimBatch)
    #expect(log.lines.last?.text == "line 10049")
    #expect(!log.unseenErrors)
    log.append("bad\nworse", flaggedError: true)
    #expect(log.lines.suffix(2).map(\.isError) == [true, true])
    #expect(log.unseenErrors)
    log.markSeen()
    #expect(!log.unseenErrors)
}

@Test func lineSplitterHandlesPartialChunks() {
    let s = LineSplitter()
    #expect(s.feed(Data("[{\"ev".utf8)) == [])
    #expect(s.feed(Data("ent\":1}]\r\nsecond\nthi".utf8)) == ["[{\"event\":1}]", "second"])
    #expect(s.flush() == ["thi"])
    #expect(s.flush() == [])
}

@Test func classifierHandlesPlatformLogPrefixes() {
    var c = ErrorClassifier()
    let lines = [
        "flutter: ══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════",
        "flutter: boom",
        "flutter: ═══════════════════════════════════════════",
        "flutter: fine",
        "I/flutter (12345): Another exception was thrown: again",
        "I/flutter (12345): fine",
    ]
    let flags = lines.map { c.classify($0, flaggedError: false) }
    #expect(flags == [true, true, true, false, true, false])
}

@Test func truncatedExceptionBlockDoesNotLeakIntoNextRun() {
    let log = LogStore()
    log.append("══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════\nhalf a dump")
    log.separator("Run again")
    log.append("normal output")
    #expect(log.lines.last?.isError == false)
    log.append("══╡ EXCEPTION CAUGHT BY X ╞═══")
    log.clear()
    log.append("after clear")
    #expect(log.lines.last?.isError == false)
}

@Test func quietErrorsAreRedButDontRaiseTheBadge() {
    let log = LogStore()
    log.append("Failed to foreground app; open returned 1", flaggedError: true, quiet: true)
    #expect(log.lines.last?.isError == true)
    #expect(!log.unseenErrors)
    // An app exception still raises it, even when it arrives on a quiet channel.
    log.append("══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══", quiet: true)
    #expect(log.unseenErrors)
}
