import Foundation

public enum ConversationTitleDeriver {
    public static let placeholderTitle = "New chat"

    private static let maxTitleWords = 8
    private static let maxTitleCharacters = 64
    private static let placeholderTitles: Set<String> = [
        "",
        "new chat",
        "untitled chat",
        "watch chat",
    ]
    private static let smallWords: Set<String> = [
        "a", "an", "and", "as", "at", "but", "by", "for", "from", "in",
        "into", "nor", "of", "on", "or", "per", "the", "to", "via", "vs", "with",
    ]
    private static let acronyms: Set<String> = [
        "AI", "API", "BYOK", "CPU", "CSV", "GPU", "HTML", "HTTP", "JSON", "LLM",
        "MCP", "MLX", "OCR", "PDF", "REST", "SQL", "UI", "URL", "UX", "XML",
    ]
    private static let leadingRequestPhrases = [
        "can you ",
        "could you ",
        "would you ",
        "can we ",
        "could we ",
        "please ",
        "pls ",
        "help me with ",
        "help me ",
        "i need help with ",
        "i need you to ",
        "i want you to ",
        "i want to ",
        "let's ",
        "lets ",
    ]

    public static func isPlaceholder(_ title: String) -> Bool {
        placeholderTitles.contains(normalizedWhitespace(title).lowercased())
    }

    public static func title(forStoredTitle storedTitle: String, messages: [ChatMessage]) -> String {
        let stored = storedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPlaceholder(stored) else { return stored }
        return title(from: messages) ?? placeholderTitle
    }

    public static func title(forStoredTitle storedTitle: String, titleSource: String?) -> String {
        let stored = storedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPlaceholder(stored) else { return stored }
        return title(from: titleSource ?? "") ?? placeholderTitle
    }

    public static func title(from messages: [ChatMessage]) -> String? {
        let userTitle = messages.lazy
            .filter { $0.role == .user }
            .compactMap(title(from:))
            .first
        if let userTitle {
            return userTitle
        }

        return messages.lazy
            .filter { $0.role != .system && $0.role != .tool }
            .compactMap(title(from:))
            .first
    }

    public static func title(from text: String) -> String? {
        let candidate = titleCandidate(from: text)
        guard !candidate.isEmpty else { return nil }
        return displayTitle(from: candidate)
    }

    private static func title(from message: ChatMessage) -> String? {
        if isGenericAttachmentPrompt(message.content),
           let attachmentTitle = title(from: message.attachments) {
            return attachmentTitle
        }

        if let textTitle = title(from: message.content) {
            return textTitle
        }

        return title(from: message.attachments)
    }

    private static func title(from attachments: [ChatAttachment]) -> String? {
        guard !attachments.isEmpty else { return nil }
        let names = attachments
            .map { sanitizedAttachmentName($0.fileName) }
            .filter { !$0.isEmpty }

        guard let firstName = names.first else {
            return attachments.count == 1 ? "Attachment" : "\(attachments.count) Attachments"
        }

        if names.count == 1 {
            return displayTitle(from: firstName)
        }
        return "\(names.count) Attachments"
    }

    private static func sanitizedAttachmentName(_ fileName: String) -> String {
        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return normalizedWhitespace(
            base
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
        )
    }

    private static func isGenericAttachmentPrompt(_ text: String) -> Bool {
        let normalized = normalizedWhitespace(
            text
                .lowercased()
                .unicodeScalars
                .map { CharacterSet.punctuationCharacters.contains($0) ? " " : String($0) }
                .joined()
        )
        return normalized == "analyze this image"
            || normalized == "analyze these images"
            || normalized == "analyze the attached file"
            || normalized == "analyze the attached files"
            || normalized == "analyze the attached image and files"
    }

    private static func titleCandidate(from text: String) -> String {
        var candidate = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let withoutFences = removingFencedCode(from: candidate)
        if !normalizedWhitespace(withoutFences).isEmpty {
            candidate = withoutFences
        }

        candidate = replacingMatches(in: candidate, pattern: #"!\[([^\]]*)\]\([^)]+\)"#, template: "$1")
        candidate = replacingMatches(in: candidate, pattern: #"\[([^\]]+)\]\([^)]+\)"#, template: "$1")
        candidate = replacingMatches(in: candidate, pattern: #"https?://\S+"#, template: " ")
        candidate = replacingMatches(in: candidate, pattern: #"(?m)^\s{0,3}#{1,6}\s*"#, template: "")
        candidate = replacingMatches(in: candidate, pattern: #"(?m)^\s{0,3}>\s?"#, template: "")
        candidate = replacingMatches(in: candidate, pattern: #"(?m)^\s*[-*+]\s+"#, template: "")
        candidate = replacingMatches(in: candidate, pattern: #"(?m)^\s*\d+[.)]\s+"#, template: "")
        candidate = candidate
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: " ")

        candidate = removingSymbols(from: candidate)
        candidate = normalizedWhitespace(candidate)
        candidate = removingSpeakerLabel(from: candidate)
        candidate = removingLeadingRequestPhrase(from: candidate)
        candidate = firstSentenceOrClause(from: candidate)
        candidate = removingLeadingRequestPhrase(from: candidate)
        return normalizedWhitespace(candidate.trimmingCharacters(in: edgePunctuation))
    }

    private static func removingFencedCode(from text: String) -> String {
        var kept = [String]()
        var isInFence = false
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                isInFence.toggle()
                continue
            }
            if !isInFence {
                kept.append(line)
            }
        }
        return kept.joined(separator: "\n")
    }

    private static func removingSpeakerLabel(from text: String) -> String {
        let labels = ["user:", "assistant:", "question:", "prompt:", "request:"]
        let lower = text.lowercased()
        for label in labels where lower.hasPrefix(label) {
            return String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func removingLeadingRequestPhrase(from text: String) -> String {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var didRemove = true
        while didRemove {
            didRemove = false
            let lower = candidate.lowercased()
            for phrase in leadingRequestPhrases where lower.hasPrefix(phrase) {
                candidate = String(candidate.dropFirst(phrase.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                didRemove = true
                break
            }
        }
        return candidate
    }

    private static func firstSentenceOrClause(from text: String) -> String {
        guard !text.isEmpty else { return text }
        let separators: [Character] = ["?", "!", "."]
        for index in text.indices where separators.contains(text[index]) {
            let next = text.index(after: index)
            if next == text.endIndex || text[next].isWhitespace {
                let prefix = String(text[..<index])
                if prefix.split(separator: " ").count >= 3 || prefix.count >= 18 {
                    return prefix
                }
            }
        }

        let clauseSeparators = [" so ", " because ", " but ", " and then "]
        let lower = text.lowercased()
        for separator in clauseSeparators {
            if let range = lower.range(of: separator) {
                let prefix = String(text[..<range.lowerBound])
                if prefix.split(separator: " ").count >= 3 {
                    return prefix
                }
            }
        }
        return text
    }

    private static func displayTitle(from candidate: String) -> String? {
        let words = candidate
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: edgePunctuation) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }

        var selected = [String]()
        for word in words {
            let next = selected + [word]
            let proposed = next.joined(separator: " ")
            if selected.count >= 3, proposed.count > maxTitleCharacters {
                break
            }
            selected.append(word)
            if selected.count >= maxTitleWords {
                break
            }
        }

        let titled = selected.enumerated()
            .map { index, word in displayWord(word, index: index, total: selected.count) }
            .joined(separator: " ")
            .trimmingCharacters(in: edgePunctuation)
        return titled.isEmpty ? nil : titled
    }

    private static func displayWord(_ word: String, index: Int, total: Int) -> String {
        let trimmed = word.trimmingCharacters(in: edgePunctuation)
        guard !trimmed.isEmpty else { return trimmed }

        let upper = trimmed.uppercased()
        if acronyms.contains(upper) {
            return upper
        }
        if preservesIntentionalCase(trimmed) {
            return trimmed
        }

        let lower = trimmed.lowercased()
        if index > 0, index < total - 1, smallWords.contains(lower) {
            return lower
        }
        guard let first = lower.unicodeScalars.first else { return lower }
        return String(first).uppercased() + String(lower.unicodeScalars.dropFirst())
    }

    private static func preservesIntentionalCase(_ word: String) -> Bool {
        let scalars = Array(word.unicodeScalars)
        guard scalars.contains(where: { CharacterSet.uppercaseLetters.contains($0) }) else {
            return false
        }
        if word == word.uppercased() {
            return word.count <= 5
        }
        return scalars.dropFirst().contains { CharacterSet.uppercaseLetters.contains($0) }
    }

    private static func removingSymbols(from text: String) -> String {
        let preservedSymbols = CharacterSet(charactersIn: "+#")
        return text.unicodeScalars.map { scalar in
            if CharacterSet.symbols.contains(scalar), !preservedSymbols.contains(scalar) {
                return " "
            }
            return String(scalar)
        }.joined()
    }

    private static func normalizedWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func replacingMatches(in text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static var edgePunctuation: CharacterSet {
        var set = CharacterSet.punctuationCharacters
        set.remove(charactersIn: "+#/-")
        return set.union(.whitespacesAndNewlines)
    }
}
