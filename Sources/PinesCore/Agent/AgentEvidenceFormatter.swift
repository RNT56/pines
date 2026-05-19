import Foundation

public enum AgentEvidenceFormatter {
    public static let defaultTextLimit = 4_000

    public static func modelVisibleOutput(
        toolName: String,
        rawOutputJSON: String,
        textLimit: Int = defaultTextLimit
    ) -> String {
        if let error = errorMessage(from: rawOutputJSON) {
            return """
            Tool evidence from \(toolName):
            Error: \(error)
            """
        }

        switch toolName {
        case "web.search":
            return searchEvidence(from: rawOutputJSON, textLimit: textLimit)
        case WebFetchTool.name:
            return fetchEvidence(from: rawOutputJSON, textLimit: textLimit)
        case "browser.observe":
            return browserEvidence(from: rawOutputJSON, snapshotKey: "snapshot", textLimit: textLimit)
        case "browser.action":
            return browserEvidence(from: rawOutputJSON, snapshotKey: "snapshot", textLimit: textLimit)
        default:
            return clipped(rawOutputJSON, limit: textLimit)
        }
    }

    public static func fallbackAnswer(from messages: [ChatMessage], userRequest: String) -> String {
        let evidenceMessages = messages
            .filter { $0.role == .tool }
            .map(\.content)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let sources = sourceURLs(from: evidenceMessages)
        var lines = evidenceMessages.isEmpty
            ? ["I could not gather usable web evidence or produce a final synthesis for this request."]
            : ["I gathered web evidence for this request but the local model did not produce a final synthesis."]
        if !userRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Request: \(userRequest.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        lines.append("Summary: I found relevant source material, but there was not enough reliable generated synthesis to provide a stronger answer without risking unsupported claims.")
        if !sources.isEmpty {
            lines.append("")
            lines.append("Sources:")
            lines.append(contentsOf: sources.prefix(8).map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    private static func searchEvidence(from rawOutputJSON: String, textLimit: Int) -> String {
        guard let object = jsonObject(rawOutputJSON),
              let resultsJSON = object["resultsJSON"] as? String,
              let data = resultsJSON.data(using: .utf8),
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return genericEvidence(toolName: "web.search", rawOutputJSON: rawOutputJSON, textLimit: textLimit)
        }

        var lines = ["Tool evidence from web.search:"]
        if results.isEmpty {
            lines.append("No search results were returned.")
        } else {
            for (index, result) in results.prefix(8).enumerated() {
                let title = string(result["title"]) ?? "Untitled result"
                let url = string(result["url"]) ?? "No URL"
                let snippet = string(result["snippet"]) ?? ""
                lines.append("\(index + 1). \(title)")
                lines.append("URL: \(url)")
                if !snippet.isEmpty {
                    lines.append("Snippet: \(snippet)")
                }
            }
        }
        return clipped(lines.joined(separator: "\n"), limit: textLimit)
    }

    private static func fetchEvidence(from rawOutputJSON: String, textLimit: Int) -> String {
        guard let object = jsonObject(rawOutputJSON) else {
            return genericEvidence(toolName: "web.fetch", rawOutputJSON: rawOutputJSON, textLimit: textLimit)
        }
        var lines = ["Tool evidence from web.fetch:"]
        appendIfPresent("Title", object["title"], to: &lines)
        appendIfPresent("URL", object["finalURL"] ?? object["url"], to: &lines)
        appendIfPresent("Status", object["statusCode"], to: &lines)
        appendIfPresent("Content-Type", object["contentType"], to: &lines)
        if let text = string(object["text"]), !text.isEmpty {
            lines.append("Text:")
            lines.append(text)
        }
        if let truncated = object["truncated"] as? Bool, truncated {
            lines.append("[The fetched text was truncated.]")
        }
        return clipped(lines.joined(separator: "\n"), limit: textLimit)
    }

    private static func browserEvidence(from rawOutputJSON: String, snapshotKey: String, textLimit: Int) -> String {
        guard let object = jsonObject(rawOutputJSON) else {
            return genericEvidence(toolName: "browser", rawOutputJSON: rawOutputJSON, textLimit: textLimit)
        }
        var lines = ["Tool evidence from browser:"]
        appendIfPresent("Summary", object["summary"], to: &lines)
        if let snapshot = string(object[snapshotKey]), !snapshot.isEmpty {
            lines.append("Snapshot:")
            lines.append(snapshot)
        }
        return clipped(lines.joined(separator: "\n"), limit: textLimit)
    }

    private static func genericEvidence(toolName: String, rawOutputJSON: String, textLimit: Int) -> String {
        var lines = [
            "Tool evidence from \(toolName):",
            "The tool output did not match the expected schema.",
        ]
        guard let data = rawOutputJSON.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data)
        else {
            lines.append("No readable fields were available.")
            return lines.joined(separator: "\n")
        }
        appendReadableFields(from: value, to: &lines, depth: 0, itemLimit: 8)
        if lines.count == 2 {
            lines.append("No readable fields were available.")
        }
        return clipped(lines.joined(separator: "\n"), limit: textLimit)
    }

    private static func appendReadableFields(
        from value: Any,
        to lines: inout [String],
        depth: Int,
        itemLimit: Int
    ) {
        guard depth < 3, lines.count < itemLimit * 3 else { return }
        if let dictionary = value as? [String: Any] {
            appendIfPresent("Title", dictionary["title"], to: &lines)
            appendIfPresent("URL", dictionary["url"] ?? dictionary["finalURL"], to: &lines)
            appendIfPresent("Snippet", dictionary["snippet"], to: &lines)
            appendIfPresent("Summary", dictionary["summary"], to: &lines)
            appendIfPresent("Status", dictionary["statusCode"] ?? dictionary["status"], to: &lines)
            appendIfPresent("Content-Type", dictionary["contentType"], to: &lines)
            appendIfPresent("Message", dictionary["message"], to: &lines)
            if let text = string(dictionary["text"]), !text.isEmpty {
                lines.append("Text:")
                lines.append(text)
            }
            if let nestedJSON = dictionary["resultsJSON"] as? String,
               let nestedData = nestedJSON.data(using: .utf8),
               let nested = try? JSONSerialization.jsonObject(with: nestedData) {
                appendReadableFields(from: nested, to: &lines, depth: depth + 1, itemLimit: itemLimit)
            }
            for nested in dictionary.values {
                appendReadableFields(from: nested, to: &lines, depth: depth + 1, itemLimit: itemLimit)
            }
        } else if let array = value as? [Any] {
            for item in array.prefix(itemLimit) {
                appendReadableFields(from: item, to: &lines, depth: depth + 1, itemLimit: itemLimit)
            }
        }
    }

    private static func errorMessage(from rawOutputJSON: String) -> String? {
        guard let object = jsonObject(rawOutputJSON),
              object["error"] as? Bool == true
        else { return nil }
        return string(object["message"]) ?? "Tool failed."
    }

    private static func sourceURLs(from messages: [String]) -> [String] {
        var seen = Set<String>()
        let pattern = #"https?://[^\s\]\)\}">]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return messages.flatMap { message in
            let range = NSRange(message.startIndex..<message.endIndex, in: message)
            return regex.matches(in: message, range: range).compactMap { match -> String? in
                guard let urlRange = Range(match.range, in: message) else { return nil }
                let value = String(message[urlRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
                guard seen.insert(value).inserted else { return nil }
                return value
            }
        }
    }

    private static func jsonObject(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func appendIfPresent(_ label: String, _ value: Any?, to lines: inout [String]) {
        guard let value = string(value), !value.isEmpty else { return }
        lines.append("\(label): \(value)")
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case let value as Int:
            return String(value)
        case let value as Double:
            return String(value)
        case let value as Bool:
            return String(value)
        default:
            return nil
        }
    }

    private static func clipped(_ value: String, limit: Int) -> String {
        let normalizedLimit = max(256, limit)
        guard value.count > normalizedLimit else { return value }
        return "\(value.prefix(normalizedLimit))\n[Evidence truncated.]"
    }
}
