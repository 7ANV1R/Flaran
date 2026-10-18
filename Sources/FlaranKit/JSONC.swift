import Foundation

/// Turns VS Code-style JSON (comments, trailing commas) into strict JSON.
public func stripJSONC(_ text: String) -> String {
    let chars = Array(text)
    var out: [Character] = []
    var i = 0
    var inString = false
    while i < chars.count {
        let c = chars[i]
        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        if inString {
            out.append(c)
            if c == "\\", let next { out.append(next); i += 2; continue }
            if c == "\"" { inString = false }
            i += 1
        } else if c == "\"" {
            inString = true; out.append(c); i += 1
        } else if c == "/", next == "/" {
            while i < chars.count, chars[i] != "\n" { i += 1 }
        } else if c == "/", next == "*" {
            i += 2
            while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
            i += 2
        } else if c == "}" || c == "]" {
            // Drop a trailing comma before the closer (ignoring whitespace).
            if let last = out.lastIndex(where: { !$0.isWhitespace }), out[last] == "," { out.remove(at: last) }
            out.append(c); i += 1
        } else {
            out.append(c); i += 1
        }
    }
    return String(out)
}

/// Decodes a JSONC file into a dictionary; nil when missing or invalid.
func readJSONC(_ url: URL) -> [String: Any]? {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: Data(stripJSONC(text).utf8))) as? [String: Any]
}
