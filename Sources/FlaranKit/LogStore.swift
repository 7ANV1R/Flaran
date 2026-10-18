import Foundation
import Observation

public struct LogLine: Identifiable, Sendable {
    public let id: Int
    public let date: Date
    public let text: String
    public let isError: Bool
}

/// Marks Flutter's multi-line exception dumps as errors, not just the first line.
public struct ErrorClassifier {
    private var inBlock = false
    public init() {}

    public mutating func classify(_ line: String, flaggedError: Bool) -> Bool {
        let text = Self.stripPlatformPrefix(line)
        if text.contains("══╡ EXCEPTION CAUGHT BY") { inBlock = true; return true }
        if inBlock {
            if text.hasPrefix("════"), !text.contains("╡") { inBlock = false }
            return true
        }
        return flaggedError || text.hasPrefix("Another exception was thrown:")
    }

    /// iOS prefixes app output with `flutter: `, Android with `I/flutter (1234): `.
    static func stripPlatformPrefix(_ line: String) -> Substring {
        if line.hasPrefix("flutter: ") { return line.dropFirst(9) }
        if line.dropFirst().hasPrefix("/flutter"), let end = line.range(of: "): ") { return line[end.upperBound...] }
        return line[...]
    }
}

@Observable public final class LogStore {
    public static let capacity = 10_000
    public static let trimBatch = 1_000

    public private(set) var lines: [LogLine] = []
    public private(set) var unseenErrors = false
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var classifier = ErrorClassifier()

    public init() {}

    /// `quiet`: flagged lines still show red but don't raise the badge. Used for flutter tool chatter
    /// (stderr, tool log errors such as "Failed to foreground app"). The badge means the app has a problem.
    /// Detected app exceptions always raise it.
    public func append(_ text: String, flaggedError: Bool = false, quiet: Bool = false) {
        var alert = false
        let new = text.split(separator: "\n", omittingEmptySubsequences: false).map { part in
            let s = String(part)
            defer { nextID += 1 }
            let exception = classifier.classify(s, flaggedError: false)
            if exception || (flaggedError && !quiet) { alert = true }
            return LogLine(id: nextID, date: .now, text: s, isError: exception || flaggedError)
        }
        if alert { unseenErrors = true }
        lines.append(contentsOf: new)
        // Trim in batches: the log view redraws fully on a head trim, so do it once per 1,000 lines.
        if lines.count > Self.capacity { lines.removeFirst(lines.count - Self.capacity + Self.trimBatch) }
    }

    public func separator(_ title: String) {
        classifier = ErrorClassifier()  // a dump cut short by a stop must not paint the next run red
        append("──────── \(title) · \(Date.now.formatted(date: .omitted, time: .standard)) ────────")
    }

    public func markSeen() { unseenErrors = false }

    public func clear() {
        lines.removeAll()
        unseenErrors = false
        classifier = ErrorClassifier()
    }
}
