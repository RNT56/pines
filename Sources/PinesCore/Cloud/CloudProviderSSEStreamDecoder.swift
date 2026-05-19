import Foundation

public struct CloudProviderSSEEvent: Hashable, Sendable {
    public var eventName: String?
    public var eventID: String?
    public var payload: String

    public init(eventName: String?, eventID: String? = nil, payload: String) {
        self.eventName = eventName
        self.eventID = eventID
        self.payload = payload
    }

    public func jsonData(eventTypeField: String = "type") -> Data? {
        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPayload != "[DONE]", let data = trimmedPayload.data(using: .utf8) else {
            return nil
        }
        guard let eventName, !eventName.isEmpty,
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object[eventTypeField] == nil
        else {
            return data
        }
        object[eventTypeField] = eventName
        if let eventID, !eventID.isEmpty, object["id"] == nil {
            object["id"] = eventID
        }
        guard JSONSerialization.isValidJSONObject(object) else {
            return data
        }
        return try? JSONSerialization.data(withJSONObject: object)
    }
}

public struct CloudProviderSSEStreamDecoder: Sendable {
    private var eventName: String?
    private var eventID: String?
    private var dataLines = [String]()

    public init() {}

    public mutating func ingest(_ rawLine: String) -> CloudProviderSSEEvent? {
        let line = rawLine.trimmingCharacters(in: .newlines)
        guard !line.isEmpty else {
            return dispatch()
        }
        guard !line.hasPrefix(":") else {
            return nil
        }

        let field: Substring
        var value: Substring
        if let separator = line.firstIndex(of: ":") {
            field = line[..<separator]
            value = line[line.index(after: separator)...]
            if value.first == " " {
                value = value.dropFirst()
            }
        } else {
            field = Substring(line)
            value = ""
        }

        switch field {
        case "event":
            if let pending = dispatchBeforeStartingNextEvent() {
                eventName = String(value)
                return pending
            }
            eventName = String(value)
        case "id":
            if let pending = dispatchBeforeStartingNextEvent() {
                eventID = String(value)
                return pending
            }
            eventID = String(value)
        case "data":
            if eventName == nil,
               let pending = dispatchBeforeStartingNextDataLine() {
                dataLines.append(String(value))
                return pending
            }
            dataLines.append(String(value))
        default:
            break
        }
        return nil
    }

    public mutating func finish() -> CloudProviderSSEEvent? {
        dispatch()
    }

    private mutating func dispatch() -> CloudProviderSSEEvent? {
        defer {
            eventName = nil
            eventID = nil
            dataLines.removeAll(keepingCapacity: true)
        }
        guard !dataLines.isEmpty else {
            return nil
        }
        return CloudProviderSSEEvent(
            eventName: eventName,
            eventID: eventID,
            payload: dataLines.joined(separator: "\n")
        )
    }

    private mutating func dispatchBeforeStartingNextEvent() -> CloudProviderSSEEvent? {
        guard !dataLines.isEmpty else { return nil }
        return dispatch()
    }

    private mutating func dispatchBeforeStartingNextDataLine() -> CloudProviderSSEEvent? {
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard payload == "[DONE]" || payloadIsCompleteJSON(payload) else {
            return nil
        }
        return dispatch()
    }

    private func payloadIsCompleteJSON(_ payload: String) -> Bool {
        guard let data = payload.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
