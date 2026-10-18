import Foundation

public struct LaunchConfig: Codable, Hashable, Sendable {
    public var name: String
    public var type: String?
    public var request: String?
    public var program: String?
    public var cwd: String?
    public var flutterMode: String?
    public var deviceId: String?
    public var toolArgs: [String]?
    public var args: [String]?
    public var env: [String: String]?

    public static let defaultConfig = LaunchConfig(name: "Default")
}

/// Flutter launch configurations from `.vscode/launch.json`, or `[.defaultConfig]`.
/// Entries are decoded one by one so one odd (often non-Dart) entry can't hide the rest.
public func loadLaunchConfigs(projectDir: URL) -> [LaunchConfig] {
    let entries = readJSONC(projectDir.appending(path: ".vscode/launch.json"))?["configurations"] as? [[String: Any]] ?? []
    let expand = { (s: String) in s.replacingOccurrences(of: "${workspaceFolder}", with: projectDir.path) }
    let configs = entries
        .filter { $0["type"] as? String == "dart" && $0["request"] as? String != "attach" }
        .compactMap { entry -> LaunchConfig? in
            guard let data = try? JSONSerialization.data(withJSONObject: entry),
                  var c = try? JSONDecoder().decode(LaunchConfig.self, from: data)
            else { return nil }
            c.program = c.program.map(expand)
            c.cwd = c.cwd.map(expand)
            c.args = c.args?.map(expand)
            c.toolArgs = c.toolArgs?.map(expand)
            c.env = c.env?.mapValues(expand)
            return c
        }
    return configs.isEmpty ? [.defaultConfig] : configs
}
