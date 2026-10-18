import Foundation

public enum SDKError: Error, Equatable, LocalizedError {
    case missingSDK(path: String, source: String)
    case noFlutterFound

    public var errorDescription: String? {
        switch self {
        case let .missingSDK(path, source):
            "Flutter SDK pinned by \(source) not found at \(path). Install it (e.g. `fvm install`) and run again."
        case .noFlutterFound:
            "No Flutter SDK found: no FVM pin, no dart.flutterSdkPath, and `flutter` is not on your login shell PATH."
        }
    }
}

/// Returns `bin/flutter` for the project: FVM pin, then VS Code's `dart.flutterSdkPath`,
/// checked from `appDir` up to `root`, then the global SDK. A pin that points nowhere throws.
public func resolveFlutter(appDir: URL, root: URL, globalFlutter: URL?) throws -> URL {
    let fm = FileManager.default
    let rootPath = root.standardizedFileURL.path
    var dir = appDir.standardizedFileURL
    while true {
        let fvm = dir.appending(path: ".fvm/flutter_sdk")
        // attributesOfItem doesn't follow symlinks, so a dangling FVM link still counts as a pin.
        if (try? fm.attributesOfItem(atPath: fvm.path)) != nil {
            return try flutterBinary(in: fvm, source: "fvm")
        }
        if let sdk = readJSONC(dir.appending(path: ".vscode/settings.json"))?["dart.flutterSdkPath"] as? String {
            let expanded = (sdk as NSString).expandingTildeInPath
            let url = expanded.hasPrefix("/") ? URL(filePath: expanded) : dir.appending(path: expanded)
            return try flutterBinary(in: url, source: "settings.json")
        }
        if dir.path == rootPath || dir.path == "/" { break }
        dir = dir.deletingLastPathComponent()
    }
    guard let globalFlutter else { throw SDKError.noFlutterFound }
    return globalFlutter
}

private func flutterBinary(in sdk: URL, source: String) throws -> URL {
    let bin = sdk.appending(path: "bin/flutter")
    guard FileManager.default.fileExists(atPath: bin.path)
    else { throw SDKError.missingSDK(path: sdk.path, source: source) }
    return bin
}
