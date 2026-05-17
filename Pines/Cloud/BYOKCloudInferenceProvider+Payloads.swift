import Foundation
import ImageIO
import PinesCore
import UniformTypeIdentifiers

extension BYOKCloudInferenceProvider {
    static func openAIMessageObject(_ message: ChatMessage, providerKind: CloudProviderKind) throws -> [String: Any] {
        if message.role == .tool {
            return [
                "role": "tool",
                "tool_call_id": message.toolCallID ?? "",
                "content": message.content,
            ]
        }

        var object: [String: Any] = [
            "role": message.role.rawValue,
            "content": try openAIChatContent(from: message, providerKind: providerKind),
        ]
        if !message.toolCalls.isEmpty {
            object["tool_calls"] = message.toolCalls.map { toolCall in
                [
                    "id": toolCall.id,
                    "type": "function",
                    "function": [
                        "name": toolCall.name,
                        "arguments": toolCall.argumentsFragment,
                    ],
                ] as [String: Any]
            }
        }
        return object
    }

    static func openAIChatContent(from message: ChatMessage, providerKind: CloudProviderKind) throws -> Any {
        let attachments = try normalizedCloudAttachments(from: message)
        guard !attachments.isEmpty else {
            return message.content
        }
        guard message.role == .user else {
            throw InferenceError.invalidRequest("Cloud attachments are only supported on user messages.")
        }

        var parts = [[String: Any]]()
        if !message.content.isEmpty {
            parts.append(["type": "text", "text": message.content])
        }
        for attachment in attachments {
            switch attachment.kind {
            case .image:
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": attachment.dataURL],
                ])
            case .pdf:
                guard providerKind == .openRouter else {
                    throw unsupportedAttachment(attachment, providerName: "this OpenAI-compatible provider")
                }
                parts.append([
                    "type": "file",
                    "file": [
                        "filename": attachment.fileName,
                        "file_data": attachment.dataURL,
                    ],
                ])
            case .textDocument:
                throw unsupportedAttachment(attachment, providerName: providerKind == .openRouter ? "OpenRouter" : "this OpenAI-compatible provider")
            }
        }
        return parts.isEmpty ? message.content : parts
    }

    static func openAIResponsesPayload(from messages: [ChatMessage]) throws -> OpenAIResponsesPayload {
        let instructions = messages
            .filter { $0.role == .system }
            .map(\.content)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let previousResponse = messages.enumerated().last { _, message in
            message.providerMetadata[openAIResponseIDMetadataKey]?.isEmpty == false
        }
        let replayStartIndex = previousResponse.map { messages.index(after: $0.offset) } ?? messages.startIndex
        let replayMessages = messages[replayStartIndex...]
        let input = try replayMessages.reduce(into: [[String: Any]]()) { input, message in
            guard message.role != .system else { return }
            if message.role == .tool {
                input.append([
                    "type": "function_call_output",
                    "call_id": message.toolCallID ?? "",
                    "output": message.content,
                ])
                return
            }
            if message.role == .assistant,
               let outputItems = openAIStoredOutputItems(from: message) {
                input.append(contentsOf: outputItems)
                return
            }
            if message.role == .assistant, !message.toolCalls.isEmpty {
                for toolCall in message.toolCalls {
                    input.append([
                        "type": "function_call",
                        "call_id": toolCall.id,
                        "name": toolCall.name,
                        "arguments": toolCall.argumentsFragment,
                    ])
                }
                return
            }

            let content = try openAIResponsesMessageContent(from: message)
            if !content.isEmpty {
                input.append([
                    "role": message.role == .assistant ? "assistant" : "user",
                    "content": content,
                ])
            }
        }

        return OpenAIResponsesPayload(
            input: input,
            instructions: instructions,
            previousResponseID: previousResponse?.element.providerMetadata[openAIResponseIDMetadataKey]
        )
    }

    static func openAIStoredOutputItems(from message: ChatMessage) -> [[String: Any]]? {
        guard let raw = message.providerMetadata[CloudProviderMetadataKeys.openAIOutputItemsJSON],
              let data = raw.data(using: .utf8)
        else {
            return nil
        }
        let items: [[String: Any]]
        do {
            guard let parsedItems = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return nil
            }
            items = parsedItems
        } catch {
            return nil
        }
        guard !items.isEmpty else { return nil }
        return items
    }

    static func openAIResponsesMessageContent(from message: ChatMessage) throws -> [[String: Any]] {
        var content = [[String: Any]]()
        if !message.content.isEmpty {
            content.append([
                "type": message.role == .assistant ? "output_text" : "input_text",
                "text": message.content,
            ])
        }
        guard message.role == .user else {
            return content
        }
        for attachment in try normalizedCloudAttachments(from: message) {
            switch attachment.kind {
            case .image:
                content.append([
                    "type": "input_image",
                    "image_url": attachment.dataURL,
                    "detail": "auto",
                ])
            case .pdf, .textDocument:
                content.append([
                    "type": "input_file",
                    "filename": attachment.fileName,
                    "file_data": attachment.dataURL,
                ])
            }
        }
        return content
    }

    static func anthropicImageBlock(from attachment: CloudAttachmentPayload) -> [String: Any] {
        [
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": attachment.contentType,
                "data": attachment.base64Data,
            ],
        ]
    }

    static func anthropicDocumentBlock(from attachment: CloudAttachmentPayload) -> [String: Any] {
        [
            "type": "document",
            "source": [
                "type": "base64",
                "media_type": attachment.contentType,
                "data": attachment.base64Data,
            ],
        ]
    }

    static func anthropicTextDocumentBlock(from attachment: CloudAttachmentPayload) throws -> [String: Any] {
        [
            "type": "text",
            "text": try textDocumentPrompt(from: attachment),
        ]
    }

    static func geminiInlinePart(from attachment: CloudAttachmentPayload) throws -> [String: Any] {
        let geminiAttachment = try geminiCompatibleAttachment(attachment)
        return [
            "inlineData": [
                "mimeType": geminiAttachment.contentType,
                "data": geminiAttachment.base64Data,
            ],
        ]
    }

    static func openAIResponsesFunctionToolObject(_ spec: AnyToolSpec) -> [String: Any] {
        [
            "type": "function",
            "name": spec.name,
            "description": spec.description,
            "parameters": jsonSerializable((spec.inputJSONSchema ?? spec.inputSchema.jsonValue).anySendable),
        ]
    }

    static func anthropicMessageObject(_ message: ChatMessage) throws -> [String: Any] {
        if message.role == .tool {
            return [
                "role": "user",
                "content": [[
                    "type": "tool_result",
                    "tool_use_id": message.toolCallID ?? "",
                    "content": message.content,
                ]],
            ]
        }

        var content = anthropicThinkingContentBlocks(from: message)
        if message.role == .user {
            for attachment in try normalizedCloudAttachments(from: message) {
                switch attachment.kind {
                case .image:
                    content.append(anthropicImageBlock(from: attachment))
                case .pdf:
                    content.append(anthropicDocumentBlock(from: attachment))
                case .textDocument:
                    content.append(try anthropicTextDocumentBlock(from: attachment))
                }
            }
        } else if !message.attachments.isEmpty {
            throw InferenceError.invalidRequest("Cloud attachments are only supported on user messages.")
        }
        if !message.content.isEmpty {
            content.append(["type": "text", "text": message.content])
        }
        for toolCall in message.toolCalls {
            content.append([
                "type": "tool_use",
                "id": toolCall.id,
                "name": toolCall.name,
                "input": Self.jsonObject(fromJSONString: toolCall.argumentsFragment) ?? [:],
            ])
        }
        return [
            "role": message.role == .assistant ? "assistant" : "user",
            "content": content.isEmpty ? [["type": "text", "text": message.content]] : content,
        ]
    }

    static func anthropicThinkingContentBlocks(from message: ChatMessage) -> [[String: Any]] {
        guard message.role == .assistant,
              let rawContent = message.providerMetadata[anthropicThinkingContentMetadataKey],
              let data = rawContent.data(using: .utf8)
        else {
            return []
        }
        do {
            guard let blocks = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            return blocks.filter { $0["type"] as? String == "thinking" }
        } catch {
            return []
        }
    }

    static func geminiContentObject(_ message: ChatMessage) throws -> [String: Any] {
        if message.role == .assistant,
           let rawContent = message.providerMetadata[geminiModelContentMetadataKey],
           let data = rawContent.data(using: .utf8) {
            do {
                if let content = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   content["role"] as? String == "model",
                   content["parts"] is [[String: Any]] {
                    return content
                }
            } catch {}
        }

        if message.role == .tool {
            var functionResponse: [String: Any] = [
                "name": message.toolName ?? "",
                "response": Self.jsonObject(fromJSONString: message.content) ?? ["result": message.content],
            ]
            if let toolCallID = message.toolCallID, !toolCallID.isEmpty {
                functionResponse["id"] = toolCallID
            }
            return [
                "role": "user",
                "parts": [["functionResponse": functionResponse]],
            ]
        }

        var parts = [[String: Any]]()
        if message.role == .user {
            for attachment in try normalizedCloudAttachments(from: message) {
                switch attachment.kind {
                case .image, .pdf:
                    parts.append(try geminiInlinePart(from: attachment))
                case .textDocument:
                    parts.append(["text": try textDocumentPrompt(from: attachment)])
                }
            }
        } else if !message.attachments.isEmpty {
            throw InferenceError.invalidRequest("Cloud attachments are only supported on user messages.")
        }
        if !message.content.isEmpty {
            parts.append(["text": message.content])
        }
        for toolCall in message.toolCalls {
            var functionCall: [String: Any] = [
                "name": toolCall.name,
                "args": Self.jsonObject(fromJSONString: toolCall.argumentsFragment) ?? [:],
            ]
            if !toolCall.id.isEmpty {
                functionCall["id"] = toolCall.id
            }
            parts.append(["functionCall": functionCall])
        }
        return [
            "role": message.role == .assistant ? "model" : "user",
            "parts": parts.isEmpty ? [["text": message.content]] : parts,
        ]
    }

    static func latestGeminiInteractionID(from messages: [ChatMessage]) -> String? {
        messages.reversed().compactMap { message in
            let id = message.providerMetadata[geminiInteractionIDMetadataKey]
            return id?.isEmpty == false ? id : nil
        }.first
    }

    static func geminiInteractionInput(from messages: [ChatMessage]) throws -> [[String: Any]] {
        try messages.reduce(into: [[String: Any]]()) { input, message in
            guard message.role != .system else { return }
            switch message.role {
            case .user:
                input.append([
                    "type": "user_input",
                    "content": try geminiInteractionContent(from: message),
                ])
            case .assistant:
                if !message.content.isEmpty {
                    input.append([
                        "type": "model_output",
                        "content": [["type": "text", "text": message.content]],
                    ])
                }
                for toolCall in message.toolCalls {
                    input.append([
                        "type": "function_call",
                        "id": toolCall.id,
                        "name": toolCall.name,
                        "arguments": Self.jsonObject(fromJSONString: toolCall.argumentsFragment) ?? [:],
                    ])
                }
            case .tool:
                input.append([
                    "type": "function_result",
                    "name": message.toolName ?? "",
                    "call_id": message.toolCallID ?? "",
                    "result": message.content,
                ])
            case .system:
                break
            }
        }
    }

    static func geminiInteractionContent(from message: ChatMessage) throws -> [[String: Any]] {
        var content = [[String: Any]]()
        if !message.content.isEmpty {
            content.append(["type": "text", "text": message.content])
        }
        for attachment in try normalizedCloudAttachments(from: message) {
            switch attachment.kind {
            case .image:
                let geminiAttachment = try geminiCompatibleAttachment(attachment)
                content.append([
                    "type": "image",
                    "mime_type": geminiAttachment.contentType,
                    "data": geminiAttachment.base64Data,
                ])
            case .pdf:
                content.append([
                    "type": "document",
                    "mime_type": attachment.contentType,
                    "data": attachment.base64Data,
                ])
            case .textDocument:
                content.append(["type": "text", "text": try textDocumentPrompt(from: attachment)])
            }
        }
        return content.isEmpty ? [["type": "text", "text": message.content]] : content
    }

    static func geminiInteractionFunctionToolObject(_ spec: AnyToolSpec) -> [String: Any] {
        [
            "type": "function",
            "name": spec.name,
            "description": spec.description,
            "parameters": jsonSerializable((spec.inputJSONSchema ?? spec.inputSchema.jsonValue).anySendable),
        ]
    }

    static func jsonSerializable(_ dictionary: [String: any Sendable]) -> [String: Any] {
        dictionary.mapValues { jsonSerializable($0) }
    }

    static func jsonSerializable(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: any Sendable]:
            return jsonSerializable(dictionary)
        case let array as [any Sendable]:
            return array.map { jsonSerializable($0) }
        default:
            return value
        }
    }

    static func normalizedCloudAttachments(from message: ChatMessage) throws -> [CloudAttachmentPayload] {
        try message.attachments.map(normalizedCloudAttachment)
    }

    static func normalizedCloudAttachment(_ attachment: ChatAttachment) throws -> CloudAttachmentPayload {
        let contentType = normalizedCloudAttachmentContentType(attachment.normalizedContentType)
        let kind: CloudAttachmentPayload.Kind
        switch attachment.cloudInputKind {
        case .image:
            kind = .image
        case .pdf:
            kind = .pdf
        case .textDocument:
            kind = .textDocument
        case .unsupported:
            throw InferenceError.unsupportedCapability("Cloud attachment \(attachment.fileName) has unsupported MIME type \(contentType).")
        }

        guard let localURL = attachment.localURL else {
            throw InferenceError.invalidRequest("Cloud attachment \(attachment.fileName) is missing a local file URL.")
        }
        guard localURL.isFileURL else {
            throw InferenceError.invalidRequest("Cloud attachment \(attachment.fileName) must be a local file.")
        }

        let data: Data
        do {
            data = try Data(contentsOf: localURL)
        } catch {
            throw InferenceError.invalidRequest("Cloud attachment \(attachment.fileName) could not be read from disk: \(error.localizedDescription)")
        }
        guard !data.isEmpty else {
            throw InferenceError.invalidRequest("Cloud attachment \(attachment.fileName) is empty.")
        }

        let maxBytes = kind == .image ? maxInlineImageBytes : maxInlineFileBytes
        guard data.count <= maxBytes else {
            throw InferenceError.invalidRequest("Cloud attachment \(attachment.fileName) exceeds the \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)) inline limit.")
        }

        let rawFileName = attachment.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = rawFileName.isEmpty ? localURL.lastPathComponent : rawFileName
        return CloudAttachmentPayload(
            kind: kind,
            fileName: fileName.isEmpty ? "attachment" : fileName,
            contentType: contentType,
            data: data
        )
    }

    static func normalizedCloudAttachmentContentType(_ contentType: String) -> String {
        switch contentType.lowercased() {
        case "image/jpg":
            return "image/jpeg"
        case "text/x-markdown":
            return "text/markdown"
        default:
            return contentType.lowercased()
        }
    }

    static func unsupportedAttachment(_ attachment: CloudAttachmentPayload, providerName: String) -> InferenceError {
        .unsupportedCapability("\(providerName) does not support \(attachment.contentType) attachment inputs in Pines yet.")
    }

    static func textDocumentPrompt(from attachment: CloudAttachmentPayload) throws -> String {
        guard let text = String(data: attachment.data, encoding: .utf8) else {
            throw InferenceError.invalidRequest("Cloud text attachment \(attachment.fileName) is not valid UTF-8.")
        }
        return """
        Attached file \(attachment.fileName) (\(attachment.contentType)):

        \(text)
        """
    }

    static func geminiCompatibleAttachment(_ attachment: CloudAttachmentPayload) throws -> CloudAttachmentPayload {
        guard attachment.kind == .image,
              attachment.contentType == "image/gif"
        else {
            return attachment
        }
        let pngData = try pngDataFromFirstGIFFrame(attachment.data, fileName: attachment.fileName)
        return CloudAttachmentPayload(
            kind: .image,
            fileName: attachment.fileName.replacingFileExtension(with: "png"),
            contentType: "image/png",
            data: pngData
        )
    }

    static func pngDataFromFirstGIFFrame(_ data: Data, fileName: String) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw InferenceError.invalidRequest("Gemini image attachment \(fileName) could not be decoded as a GIF.")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw InferenceError.invalidRequest("Gemini image attachment \(fileName) could not be converted to PNG.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw InferenceError.invalidRequest("Gemini image attachment \(fileName) could not be finalized as PNG.")
        }
        return output as Data
    }

    static func jsonObject(fromJSONString string: String) -> Any? {
        guard let data = string.data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }

    static func providerErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let json = jsonDictionary(from: data) {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = json["message"] as? String {
                return message
            }
            if let detail = json["detail"] as? String {
                return detail
            }
            if let errors = json["errors"] as? [[String: Any]],
               let message = errors.compactMap({ $0["message"] as? String }).first {
                return message
            }
        }
        let fallback = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback?.isEmpty == false ? fallback : nil
    }

    static func parseEmbeddingVectors(data: Data, providerKind: CloudProviderKind) throws -> [[Float]] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudProviderError.invalidResponse
        }

        switch providerKind {
        case .gemini:
            if let embeddings = json["embeddings"] as? [[String: Any]] {
                return try embeddings.map { item in
                    guard let values = item["values"] as? [Double] else {
                        throw CloudProviderError.invalidResponse
                    }
                    return values.map(Float.init)
                }
            }
            if let embedding = json["embedding"] as? [String: Any],
               let values = embedding["values"] as? [Double] {
                return [values.map(Float.init)]
            }
            throw CloudProviderError.invalidResponse
        case .openAI, .openAICompatible, .openRouter, .voyageAI, .custom:
            guard let data = json["data"] as? [[String: Any]] else {
                throw CloudProviderError.invalidResponse
            }
            return try data.sorted { lhs, rhs in
                (lhs["index"] as? Int ?? 0) < (rhs["index"] as? Int ?? 0)
            }.map { item in
                if let values = item["embedding"] as? [Double] {
                    return values.map(Float.init)
                }
                if let values = item["embedding"] as? [Float] {
                    return values
                }
                throw CloudProviderError.invalidResponse
            }
        case .anthropic:
            throw InferenceError.unsupportedCapability("Anthropic does not provide a native embedding API.")
        }
    }

    static func httpResponse(from response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw CloudProviderError.invalidResponse
        }
        return http
    }

    static func normalizedEmbedding(_ vector: [Float]) -> [Float] {
        let magnitude = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    static func messageWithRequestID(_ message: String, requestID: String?, providerKind: CloudProviderKind) -> String {
        guard let requestID, !requestID.isEmpty else { return message }
        return "\(message) (\(requestIDLabel(for: providerKind)): \(requestID))"
    }

    static func requestIDLabel(for providerKind: CloudProviderKind) -> String {
        switch providerKind {
        case .anthropic:
            return "Anthropic request ID"
        case .gemini:
            return "Gemini request ID"
        case .voyageAI:
            return "Voyage AI request ID"
        case .openAI, .openAICompatible, .openRouter, .custom:
            return "OpenAI request ID"
        }
    }

    static func providerRequestID(from response: HTTPURLResponse, body: Data?, providerKind: CloudProviderKind) -> String? {
        switch providerKind {
        case .anthropic:
            return response.value(forHTTPHeaderField: "request-id")
                ?? response.value(forHTTPHeaderField: "x-request-id")
                ?? requestIDFromErrorBody(body, keys: ["request_id"])
        case .gemini:
            return response.value(forHTTPHeaderField: "x-request-id")
                ?? response.value(forHTTPHeaderField: "x-goog-request-id")
                ?? response.value(forHTTPHeaderField: "x-cloud-trace-context")
        case .openAI, .openAICompatible, .openRouter, .voyageAI, .custom:
            return response.value(forHTTPHeaderField: "x-request-id")
        }
    }

    static func requestIDFromErrorBody(_ body: Data?, keys: [String]) -> String? {
        guard let body, let json = jsonDictionary(from: body) else {
            return nil
        }
        for key in keys {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func jsonDictionary(from data: Data) -> [String: Any]? {
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

}

struct OpenAIResponsesPayload {
    var input: [[String: Any]]
    var instructions: String
    var previousResponseID: String?
}

struct CloudAttachmentPayload {
    enum Kind {
        case image
        case pdf
        case textDocument
    }

    var kind: Kind
    var fileName: String
    var contentType: String
    var data: Data

    var base64Data: String {
        data.base64EncodedString()
    }

    var dataURL: String {
        "data:\(contentType);base64,\(base64Data)"
    }
}

private extension String {
    func replacingFileExtension(with newExtension: String) -> String {
        let url = URL(fileURLWithPath: self)
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? "attachment.\(newExtension)" : "\(base).\(newExtension)"
    }
}
