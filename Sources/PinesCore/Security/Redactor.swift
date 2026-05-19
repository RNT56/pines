import Foundation

public struct Redactor: Sendable {
    public init() {}

    public func redact(_ text: String) -> String {
        let providerKeyPattern = /(?i)\b(sk-[A-Za-z0-9_\-]{12,}|sk-ant-[A-Za-z0-9_\-]{12,}|hf_[A-Za-z0-9_\-]{12,}|AIza[A-Za-z0-9_\-]{12,}|pa-[A-Za-z0-9_\-]{12,}|voyage-[A-Za-z0-9_\-]{12,}|gh[o,p,s,u,r]_[A-Za-z0-9_\-]{12,})\b/
        let bearerPattern = /(?i)\bBearer\s+[A-Za-z0-9._\-]{16,}\b/
        let jwtPattern = /\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\b/
        let cookiePattern = /(?i)\b(cookie|set-cookie)\s*:\s*[^;\r\n\s]+/
        let assignmentPattern = /(?i)\b(api[_-]?key|access[_-]?token|refresh[_-]?token|secret|credential|password)\s*[:=]\s*["']?[^"'\s,;}]{8,}/
        let pemPattern = /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/
        let genericLongSecretPattern = /\b[A-Za-z0-9_\-]{40,}\b/

        return text
            .replacing(pemPattern, with: "[redacted-private-key]")
            .replacing(cookiePattern, with: "Cookie: [redacted-cookie]")
            .replacing(assignmentPattern, with: "$1=[redacted-secret]")
            .replacing(providerKeyPattern, with: "[redacted-key]")
            .replacing(bearerPattern, with: "Bearer [redacted-token]")
            .replacing(jwtPattern, with: "[redacted-jwt]")
            .replacing(genericLongSecretPattern, with: "[redacted-secret]")
    }
}
