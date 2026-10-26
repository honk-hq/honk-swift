import Foundation

/// The exact JSON of `MessageRequest` (snake_case, nil fields omitted).
struct WireMessage: Encodable {
    var title: String?
    var message: String?
    var severity: String?
    var priority: String?
    var category: String?
    var source: String?
    var environment: String?
    var channel: String?
    var group_key: String?
    var event_type: String?
    var occurred_at: String?
    var url: String?
    var image_url: String?
    var actions: [Action]?
    var metadata: [String: MetadataValue]?
    var ttl_seconds: Int?
    var source_sequence: Int64?
}

/// The request body. The SDK does not check field contents: the server delivers first, corrects
/// what it can and reports each correction in `Accepted.warnings` (contracts/API.md §5.1).
enum Wire {
    /// Applies defaults and returns the JSON body. Throws only when there is neither a message
    /// nor a title.
    static func encode(_ m: Message, defaults: Defaults) throws(HonkError) -> Data {
        let nonEmpty: (String?) -> String? = { ($0?.isEmpty ?? true) ? nil : $0 }
        let blank: (String?) -> Bool = { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if blank(m.message) && blank(m.title) {
            throw localValidation([FieldError(field: "message", code: "required", message: "is required (send a message or a title)")])
        }
        let wire = WireMessage(
            title: nonEmpty(m.title),
            message: nonEmpty(m.message),
            severity: m.severity?.rawValue,
            priority: m.priority?.rawValue,
            category: m.category?.rawValue,
            source: nonEmpty(m.source) ?? nonEmpty(defaults.source),
            environment: nonEmpty(m.environment) ?? nonEmpty(defaults.environment),
            channel: nonEmpty(m.channel) ?? nonEmpty(defaults.channel),
            group_key: nonEmpty(m.groupKey),
            event_type: m.eventType?.rawValue,
            occurred_at: m.occurredAt.map(formatTimestamp),
            url: nonEmpty(m.url),
            image_url: nonEmpty(m.imageURL),
            actions: m.actions.isEmpty ? nil : m.actions,
            metadata: m.metadata.isEmpty ? nil : m.metadata,
            ttl_seconds: m.ttlSeconds,
            source_sequence: m.sourceSequence
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        // JSON has no NaN or infinity: those go out as text, so the message is still delivered.
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        do {
            return try encoder.encode(wire)
        } catch {
            throw localValidation([FieldError(field: "body", code: "invalid_format", message: "cannot be encoded as JSON: \(error)")])
        }
    }

    static func localValidation(_ fields: [FieldError]) -> HonkError {
        .validation(.init(code: "validation_failed", message: "invalid message, nothing was sent", fields: fields, isLocal: true))
    }

    /// RFC 3339, UTC, milliseconds: 2026-10-01T21:10:00.123Z
    static func formatTimestamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: TimeZone(identifier: "UTC")!))
    }

    /// 1–128 printable ASCII characters: what an HTTP header can carry and the server accepts.
    static func validIdempotencyKey(_ key: String) -> Bool {
        let bytes = Array(key.utf8)
        return (1...128).contains(bytes.count) && bytes.allSatisfy { (0x21...0x7E).contains($0) }
    }
}
