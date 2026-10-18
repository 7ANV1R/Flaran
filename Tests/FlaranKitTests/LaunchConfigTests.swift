import Foundation
import Testing
@testable import FlaranKit

@Test func stripsCommentsAndTrailingCommas() throws {
    let text = """
    {
      // line comment
      "a": [1, 2, /* block */ ],
    }
    """
    let obj = try JSONSerialization.jsonObject(with: Data(stripJSONC(text).utf8)) as? [String: [Int]]
    #expect(obj == ["a": [1, 2]])
}

@Test func keepsSlashesInsideStrings() {
    let text = #"{"u": "http://x//y", "e": "a\"//b"}"#
    #expect(stripJSONC(text) == text)
}

@Test func loadsOnlyDartLaunchConfigs() throws {
    let dir = try tempDir()
    try write(dir, ".vscode/launch.json", """
    {
      "version": "0.2.0",
      "configurations": [
        { "name": "dev", "type": "dart", "request": "launch",
          "program": "${workspaceFolder}/lib/main_dev.dart", "toolArgs": ["--flavor", "dev"], },
        { "name": "prod", "type": "dart", "request": "launch", "flutterMode": "release" },
        { "name": "attach", "type": "dart", "request": "attach" },
        { "name": "server", "type": "node", "request": "launch" },
      ]
    }
    """)
    let configs = loadLaunchConfigs(projectDir: dir)
    #expect(configs.map(\.name) == ["dev", "prod"])
    #expect(configs[0].toolArgs == ["--flavor", "dev"])
    #expect(configs[0].program == dir.path + "/lib/main_dev.dart")
    #expect(configs[1].flutterMode == "release")
}

@Test func missingLaunchJsonGivesDefault() throws {
    #expect(loadLaunchConfigs(projectDir: try tempDir()) == [LaunchConfig.defaultConfig])
}

// MARK: helpers

func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "frb-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

func write(_ dir: URL, _ path: String, _ text: String) throws {
    let url = dir.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

@Test func oneMalformedConfigDoesNotDropTheOthers() throws {
    let dir = try tempDir()
    try write(dir, ".vscode/launch.json", """
    { "configurations": [
        { "name": "api", "type": "node", "env": { "PORT": 3000 } },
        { "name": "dev", "type": "dart", "args": ["--dart-define=X=${workspaceFolder}"] },
        { "type": "dart" }
    ] }
    """)
    let configs = loadLaunchConfigs(projectDir: dir)
    #expect(configs.map(\.name) == ["dev"])
    #expect(configs.first?.args == ["--dart-define=X=\(dir.path)"])
}
