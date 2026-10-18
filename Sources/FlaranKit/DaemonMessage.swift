import Foundation

/// One stdout line from `flutter run --machine` / `flutter daemon`.
public enum DaemonMessage {
    case event(name: String, params: [String: Any])
    case response(id: Int, result: Any?, error: String?)
    case text(String)

    public static func parse(_ line: String) -> DaemonMessage {
        guard line.hasPrefix("[{"), line.hasSuffix("}]"),
              let array = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [[String: Any]],
              array.count == 1, let obj = array.first
        else { return .text(line) }
        if let name = obj["event"] as? String {
            return .event(name: name, params: obj["params"] as? [String: Any] ?? [:])
        }
        if let id = obj["id"] as? Int {
            let error = obj["error"].map { ($0 as? String) ?? String(describing: $0) }
            return .response(id: id, result: obj["result"], error: error)
        }
        return .text(line)
    }
}

public func encodeRequest(id: Int, method: String, params: [String: Any]) -> Data {
    let body: [String: Any] = ["id": id, "method": method, "params": params]
    var data = (try? JSONSerialization.data(withJSONObject: [body])) ?? Data()
    data.append(0x0A)
    return data
}
