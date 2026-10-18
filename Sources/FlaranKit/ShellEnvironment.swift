import Foundation

/// GUI apps don't inherit the terminal's PATH, so we ask the login shell once.
public struct ShellEnvironment: Sendable {
    public var env: [String: String]
    public var flutter: URL?

    public static func load() async -> ShellEnvironment {
        let fallback = ShellEnvironment(env: ProcessInfo.processInfo.environment, flutter: nil)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let marker = "__FLARAN_ENV__"
        // -i so .zshrc (where most people put fvm/flutter PATH) is read too.
        guard let output = await runCommand(shell, ["-lic", "echo \(marker); env -0; echo; echo \(marker); command -v flutter"]),
              let start = output.range(of: marker + "\n"),
              let end = output.range(of: "\n" + marker + "\n", range: start.upperBound..<output.endIndex)
        else { return fallback }

        var env: [String: String] = [:]
        for entry in output[start.upperBound..<end.lowerBound].split(separator: "\0") {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            env[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        let flutterPath = output[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return ShellEnvironment(
            env: env.isEmpty ? fallback.env : env,
            flutter: flutterPath.hasPrefix("/") ? URL(filePath: flutterPath) : nil)
    }

}

/// Runs a command and returns stdout, or nil on launch failure or after `timeout` seconds
/// (a blocking .zshrc, such as a tmux attach or a prompt, must not stall the app).
func runCommand(_ path: String, _ args: [String], env: [String: String]? = nil, timeout: Double = 10) async -> String? {
    await withCheckedContinuation { cont in
        let once = ResumeOnce(cont)
        let p = Process()
        p.executableURL = URL(filePath: path)
        p.arguments = args
        if let env { p.environment = env }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { once.resume(nil); return }
        let pid = p.processIdentifier
        DispatchQueue.global().async {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            once.resume(String(decoding: data, as: UTF8.self))
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            // Only kill if the command never answered; otherwise the pid may already be reused.
            if once.resume(nil) { kill(pid, SIGKILL) }
        }
    }
}

nonisolated private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<String?, Never>?

    init(_ cont: CheckedContinuation<String?, Never>) { self.cont = cont }

    /// True if this call was the one that resumed.
    @discardableResult func resume(_ value: String?) -> Bool {
        lock.withLock {
            defer { cont = nil }
            cont?.resume(returning: value)
            return cont != nil
        }
    }
}
