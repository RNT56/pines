import Foundation

public struct Redactor: Sendable {
    public init() {}

    public func redact(_ text: String) -> String {
        let keyPattern = /(?i)\b(sk-[A-Za-z0-9_\-]{12,}|hf_[A-Za-z0-9_\-]{12,}|AIza[A-Za-z0-9_\-]{12,})\b/
        let bearerPattern = /(?i)\bBearer\s+[A-Za-z0-9._\-]{16,}\b/

        return text
            .replacing(keyPattern, with: "[redacted-key]")
            .replacing(bearerPattern, with: "Bearer [redacted-token]")
    }
}
