import Foundation

public enum TmuxControlEvent: Equatable, Sendable {
    case begin(tag: Int, flags: [String])
    case end(tag: Int, flags: [String])
    case field(tag: String?, name: String, values: [String])
    case output(String)
}

public enum TmuxControlProtocol {
    public static func parseLine(_ line: String) -> TmuxControlEvent {
        guard line.hasPrefix("%") else {
            return .output(line)
        }
        let body = String(line.dropFirst())
        let parts = splitValues(body)
        guard let first = parts.first else { return .output(line) }

        switch first {
        case "begin":
            let tag = Int(parts.indices.contains(1) ? parts[1] : "") ?? 0
            return .begin(tag: tag, flags: Array(parts.dropFirst(2)))
        case "end":
            let tag = Int(parts.indices.contains(1) ? parts[1] : "") ?? 0
            return .end(tag: tag, flags: Array(parts.dropFirst(2)))
        default:
            // Field lines: %<field-name> $<pane-id> <values>... or %<field-name> %<pane-id> <values>...
            let name = first
            if parts.indices.contains(1) {
                let second = parts[1]
                if second.hasPrefix("$") || second.hasPrefix("%") {
                    let tag = String(second.dropFirst())
                    let values = Array(parts.dropFirst(2))
                    return .field(tag: tag, name: name, values: values)
                }
            }
            return .field(tag: nil, name: name, values: Array(parts.dropFirst(1)))
        }
    }

    public static func parse(block: String, commandTag: Int) -> [TmuxControlEvent] {
        block.split(separator: "\n", omittingEmptySubsequences: false).map { parseLine(String($0)) }
    }

    public static func splitValues(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inQuotes = false
        for ch in s {
            if ch == "\"" {
                inQuotes.toggle()
                continue
            }
            if ch == " " && !inQuotes {
                if !current.isEmpty {
                    out.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
