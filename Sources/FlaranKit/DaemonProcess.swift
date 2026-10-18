import Foundation

public struct DaemonReply: @unchecked Sendable {
    public var result: Any?
    public var error: String?
}

/// A `flutter … --machine`/`flutter daemon` child process speaking JSON-RPC over stdio.
public final class DaemonProcess {
    public var onMessage: (DaemonMessage) -> Void = { _ in }
    public var onStderr: (String) -> Void = { _ in }
    public var onExit: (Int32) -> Void = { _ in }
    public var isRunning: Bool { process.isRunning }

    private let process = Process()
    private let stdin = Pipe()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<DaemonReply, Never>] = [:]
    private let stdoutLines = LineSplitter()
    private let stderrLines = LineSplitter()
    private var stdoutEOF = false
    private var exitCode: Int32?
    private var finished = false

    public init(executable: URL, arguments: [String], cwd: URL, env: [String: String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.environment = env
    }

    public func start() throws {
        signal(SIGPIPE, SIG_IGN)  // writing to a dead child must throw, not kill us
        let stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        // ponytail: readabilityHandler, not FileHandle.bytes.lines: the async sequence buffers pipe
        // output and doesn't deliver lines as they arrive.
        stdout.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            if chunk.isEmpty { h.readabilityHandler = nil }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receiveStdout(chunk) } }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            if chunk.isEmpty { h.readabilityHandler = nil }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receiveStderr(chunk) } }
        }
        process.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.processExited(code) } }
        }
        try process.run()
    }

    /// Sends a request and waits for its reply; times out with an error instead of hanging.
    public func request(_ method: String, _ params: [String: Any] = [:], timeout: Duration = .seconds(120)) async -> DaemonReply {
        guard process.isRunning else { return DaemonReply(error: "process is not running") }
        let id = nextID
        nextID += 1
        let data = encodeRequest(id: id, method: method, params: params)
        return await withCheckedContinuation { cont in
            pending[id] = cont
            do { try stdin.fileHandleForWriting.write(contentsOf: data) } catch {
                resolve(id, DaemonReply(error: error.localizedDescription))
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resolve(id, DaemonReply(error: "\(method) timed out"))
            }
        }
    }

    /// SIGTERM to the whole process group (gradle, xcodebuild…), SIGKILL to what's left after 3 seconds.
    /// `Process` makes the child its own group leader, so the group is exactly flutter and its children.
    public func terminate() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        killpg(pid, SIGTERM)
        Task {
            try? await Task.sleep(for: .seconds(3))
            // ponytail: fires even if the leader is gone, to catch children; pgid reuse within 3s is negligible.
            killpg(pid, SIGKILL)
        }
    }

    /// Synchronous SIGTERM to the group, for app termination where nothing async will run.
    public func terminateNow() {
        if process.isRunning { killpg(process.processIdentifier, SIGTERM) }
    }

    private func resolve(_ id: Int, _ reply: DaemonReply) {
        pending.removeValue(forKey: id)?.resume(returning: reply)
    }

    private func receiveStdout(_ chunk: Data) {
        let lines = chunk.isEmpty ? stdoutLines.flush() : stdoutLines.feed(chunk)
        for line in lines {
            let message = DaemonMessage.parse(line)
            if case let .response(id, result, error) = message {
                resolve(id, DaemonReply(result: result, error: error))
            } else {
                onMessage(message)
            }
        }
        if chunk.isEmpty {
            stdoutEOF = true
            if let exitCode { finish(exitCode) }
        }
    }

    private func receiveStderr(_ chunk: Data) {
        for line in chunk.isEmpty ? stderrLines.flush() : stderrLines.feed(chunk) { onStderr(line) }
    }

    /// Reports exit once stdout is drained, so the last error lines land first. A launched app or
    /// Gradle daemon can inherit the pipe and hold it open, so wait at most a second.
    private func processExited(_ code: Int32) {
        exitCode = code
        if stdoutEOF { return finish(code) }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.finish(code)
        }
    }

    private func finish(_ code: Int32) {
        guard !finished else { return }
        finished = true
        for id in pending.keys { resolve(id, DaemonReply(error: "process exited")) }
        onExit(code)
    }
}

/// Splits a byte stream into lines, holding back an unfinished last line.
final class LineSplitter {
    private var buffer = Data()

    func feed(_ data: Data) -> [String] {
        buffer.append(data)
        guard let lastNewline = buffer.lastIndex(of: 0x0A) else { return [] }
        let complete = buffer[buffer.startIndex..<lastNewline]
        buffer = Data(buffer[(lastNewline + 1)...])
        return complete.split(separator: 0x0A, omittingEmptySubsequences: false).map {
            var line = String(decoding: $0, as: UTF8.self)
            if line.hasSuffix("\r") { line.removeLast() }
            return line
        }
    }

    func flush() -> [String] {
        defer { buffer = Data() }
        return buffer.isEmpty ? [] : [String(decoding: buffer, as: UTF8.self)]
    }
}
