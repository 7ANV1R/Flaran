import Foundation
import Testing
@testable import FlaranKit

private func fakeSDK(_ dir: URL) throws -> URL {
    let flutter = dir.appending(path: "bin/flutter")
    try write(dir, "bin/flutter", "#!/bin/sh\n")
    return flutter
}

@Test func fvmAtRootWinsForNestedApp() throws {
    let root = try tempDir()
    let flutter = try fakeSDK(root.appending(path: ".fvm/flutter_sdk"))
    let app = root.appending(path: "packages/app")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    #expect(try resolveFlutter(appDir: app, root: root, globalFlutter: nil) == flutter)
}

@Test func brokenFvmLinkFailsLoudly() throws {
    let root = try tempDir()
    try FileManager.default.createDirectory(at: root.appending(path: ".fvm"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        at: root.appending(path: ".fvm/flutter_sdk"),
        withDestinationURL: URL(filePath: "/nonexistent/fvm/versions/3.99.0"))
    #expect(throws: SDKError.missingSDK(path: root.appending(path: ".fvm/flutter_sdk").path, source: "fvm")) {
        try resolveFlutter(appDir: root, root: root, globalFlutter: URL(filePath: "/usr/bin/true"))
    }
}

@Test func relativeSettingsSdkPath() throws {
    let root = try tempDir()
    let flutter = try fakeSDK(root.appending(path: "sdks/flutter"))
    try write(root, ".vscode/settings.json", "{ \"dart.flutterSdkPath\": \"sdks/flutter\", // pinned\n }")
    #expect(try resolveFlutter(appDir: root, root: root, globalFlutter: nil) == flutter)
}

@Test func fallsBackToGlobal() throws {
    let root = try tempDir()
    let global = URL(filePath: "/opt/homebrew/bin/flutter")
    #expect(try resolveFlutter(appDir: root, root: root, globalFlutter: global) == global)
    #expect(throws: SDKError.noFlutterFound) { try resolveFlutter(appDir: root, root: root, globalFlutter: nil) }
}

@Test func loginShellEnvironmentHasPath() async {
    let shell = await ShellEnvironment.load()
    #expect(shell.env["PATH"]?.contains("/usr/bin") == true)
}
