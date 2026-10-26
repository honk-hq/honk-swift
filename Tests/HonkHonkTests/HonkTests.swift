import Foundation
import Testing

@testable import HonkHonk

func isUUIDv7(_ s: String) -> Bool {
    s.wholeMatch(of: /[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/) != nil
}

@Suite(.serialized)
struct ClientTests {
    @Test func serialisesEveryFieldWithTheOpenAPINames() async throws {
        MockURLProtocol.script([.accepted()])
        let honk = try mockClient()
        let accepted = try await honk.send(
            Message(
                "Billing API could not connect to Redis after 3 attempts.",
                title: "Redis connection failed", severity: .long, priority: .high, category: .infrastructure,
                source: "billing-api", environment: "production", channel: "infrastructure",
                groupKey: "billing/redis/connectivity", eventType: .problem,
                occurredAt: ISO8601DateFormatter().date(from: "2026-10-01T21:10:00Z"),
                url: "https://example.com/incidents/redis", imageURL: "https://cdn.example.com/a.jpg?w=1&h=2",
                actions: [Action(title: "Runbook", url: "https://example.com/runbooks/redis"), Action(title: "Call on-call", url: "tel:+15550134")],
                metadata: ["host": "app-01", "attempts": 3, "retried": true, "ratio": 0.5],
                ttlSeconds: 3600, sourceSequence: 42
            ))
        #expect(accepted.id == "msg_01k6h3w4z5x6y7z8a9b0c1d2e3")
        #expect(!accepted.duplicate)
        #expect(Wire.formatTimestamp(accepted.receivedAt) == "2026-10-02T21:10:00.123Z")

        let r = try #require(MockURLProtocol.requests.first)
        #expect(r.url.absoluteString == "https://honk.test/v1/messages")
        #expect(r.header("Authorization") == "Bearer \(testKey)")
        #expect(r.header("Content-Type") == "application/json")
        #expect(r.header("User-Agent") == "honk-swift/\(Honk.version)")
        #expect(isUUIDv7(r.header("Idempotency-Key") ?? ""))
        let json = r.json
        #expect(json["title"] as? String == "Redis connection failed")
        #expect(json["severity"] as? String == "error")
        #expect(json["priority"] as? String == "high")
        #expect(json["category"] as? String == "infrastructure")
        #expect(json["group_key"] as? String == "billing/redis/connectivity")
        #expect(json["event_type"] as? String == "problem")
        #expect(json["occurred_at"] as? String == "2026-10-01T21:10:00.000Z")
        #expect(json["image_url"] as? String == "https://cdn.example.com/a.jpg?w=1&h=2")
        #expect(json["actions"] as? [[String: String]] == [["title": "Runbook", "url": "https://example.com/runbooks/redis"], ["title": "Call on-call", "url": "tel:+15550134"]])
        #expect(json["ttl_seconds"] as? Int == 3600)
        #expect(json["source_sequence"] as? Int == 42)
        let md = try #require(json["metadata"] as? [String: Any])
        #expect(md["host"] as? String == "app-01" && md["attempts"] as? Int == 3 && md["retried"] as? Bool == true)
        #expect(Set(json.keys) == ["title", "message", "severity", "priority", "category", "source", "environment", "channel", "group_key", "event_type", "occurred_at", "url", "image_url", "actions", "metadata", "ttl_seconds", "source_sequence"])
        #expect(!String(decoding: r.body, as: UTF8.self).contains(#"\/"#))
    }

    @Test func minimalMessageAndDefaults() async throws {
        MockURLProtocol.script([.accepted()])
        let honk = try mockClient(defaults: Defaults(source: "cron", environment: "production", channel: ""))
        try await honk.send(Message("a"))
        try await honk.send(Message("b", source: "laravel", channel: "requests"))
        try await honk.send(Message("c", actions: []))
        let r = MockURLProtocol.requests
        #expect(r[0].json as NSDictionary == ["message": "a", "source": "cron", "environment": "production"])
        #expect(r[1].json as NSDictionary == ["message": "b", "source": "laravel", "environment": "production", "channel": "requests"])
        #expect(r[2].json as NSDictionary == ["message": "c", "source": "cron", "environment": "production"])
    }

    @Test func helpersAndTheHonkScale() async throws {
        MockURLProtocol.script([.accepted()])
        let honk = try mockClient()
        try await honk.light("a", "m")
        try await honk.beep("b", "m")
        try await honk.loud("c", "m") { $0.groupKey = "disk/var" }
        try await honk.long("d", "m")
        try await honk.blast("e", "m") { $0.severity = .light }
        try await honk.problem(groupKey: "db/backup", "Backup failed", "exit 1", idempotencyKey: "p-1")
        try await honk.recovery(groupKey: "db/backup", "Backup OK", "exit 0")
        try await honk.problem(groupKey: "q", "Queue", "failing") { $0.severity = .blast }
        try await honk.warning(nil, "synonym")
        let r = MockURLProtocol.requests
        #expect(r.map { $0.json["severity"] as? String } == ["info", "success", "warning", "error", "critical", "error", "success", "critical", "warning"])
        #expect(r[2].json["group_key"] as? String == "disk/var")
        #expect(r[5].json["event_type"] as? String == "problem" && r[5].header("Idempotency-Key") == "p-1")
        #expect(r[6].json["event_type"] as? String == "recovery")
        #expect(r[8].json["title"] == nil)
        #expect(Severity.loud == .warning && Severity.blast == .critical && Severity(parsing: " LOUD ") == .warning && Severity(parsing: "fatal") == nil)
        #expect(Severity.warning.horn == "loud")
    }

    @Test func honkUhohAndPhewSendWhatSendProblemAndRecoverySend() async throws {
        MockURLProtocol.script([.accepted()])
        let honk = try mockClient()
        let order = Message("Someone bought 3 rubber chickens", title: "New order", severity: .beep, category: .sales)
        try await honk.honk(order, idempotencyKey: "order-1042")
        try await honk.send(order, idempotencyKey: "order-1042")
        try await honk.uhoh(groupKey: "shop/stock", "Rubber chickens sold out", "Someone bought the last 3.", idempotencyKey: "stock-1") { $0.priority = .high }
        try await honk.problem(groupKey: "shop/stock", "Rubber chickens sold out", "Someone bought the last 3.", idempotencyKey: "stock-1") { $0.priority = .high }
        try await honk.phew(groupKey: "shop/stock", "Rubber chickens restocked", "200 more in the warehouse.", idempotencyKey: "stock-2")
        try await honk.recovery(groupKey: "shop/stock", "Rubber chickens restocked", "200 more in the warehouse.", idempotencyKey: "stock-2")
        try await honk.honk(order)
        try await honk.uhoh(groupKey: "q", nil, "failing") { $0.groupKey = "ignored"; $0.severity = .blast }

        let r = MockURLProtocol.requests
        #expect(r.count == 8)
        for i in stride(from: 0, to: 6, by: 2) {
            #expect(r[i].json as NSDictionary == r[i + 1].json as NSDictionary)
            #expect(r[i].header("Idempotency-Key") == r[i + 1].header("Idempotency-Key"))
        }
        #expect(r[0].header("Idempotency-Key") == "order-1042")
        #expect(r[0].json as NSDictionary == ["title": "New order", "message": "Someone bought 3 rubber chickens", "severity": "success", "category": "sales"])
        #expect(r[2].json as NSDictionary == ["title": "Rubber chickens sold out", "message": "Someone bought the last 3.", "severity": "error", "priority": "high", "group_key": "shop/stock", "event_type": "problem"])
        #expect(r[4].json as NSDictionary == ["title": "Rubber chickens restocked", "message": "200 more in the warehouse.", "severity": "success", "group_key": "shop/stock", "event_type": "recovery"])
        #expect(isUUIDv7(r[6].header("Idempotency-Key") ?? ""))
        #expect(r[7].json as NSDictionary == ["message": "failing", "severity": "critical", "group_key": "q", "event_type": "problem"])
    }

    /// Users qualify names with the module when their own code has a `Message` or `Severity` too.
    /// That only works while the module (`HonkHonk`) and the client class (`Honk`) have different
    /// names: in a module named `Honk`, `Honk.Message` would look for a member of the class.
    @Test func moduleQualifiedNamesResolve() async throws {
        MockURLProtocol.script([.accepted()])
        let honk: HonkHonk.Honk = try mockClient()
        let message: HonkHonk.Message = HonkHonk.Message("Someone bought 3 rubber chickens", severity: HonkHonk.Severity.beep)
        try await honk.honk(message)
        do {
            try await honk.honk(HonkHonk.Message(""))
            Issue.record("an empty message must not be sent")
        } catch let error as HonkHonk.HonkError {
            #expect(error.failure?.isLocal == true)
        }
        #expect(HonkHonk.Honk.version == Honk.version)
    }

    @Test func retriesReuseTheIdempotencyKeyAndBody() async throws {
        MockURLProtocol.script([.error(503, "unavailable", retryAfter: "0"), .error(500, "internal"), .fail(.networkConnectionLost), .accepted()])
        let accepted = try await mockClient().send(Message("x"))
        #expect(accepted.id.hasPrefix("msg_"))
        let r = MockURLProtocol.requests
        #expect(r.count == 4)
        #expect(Set(r.map { $0.header("Idempotency-Key") }).count == 1)
        #expect(Set(r.map(\.body)).count == 1)
    }

    @Test func retriesATimedOutAttempt() async throws {
        MockURLProtocol.script([.respond(status: 202, body: "{}", delay: .milliseconds(600)), .accepted()])
        try await mockClient(timeout: .milliseconds(150)).send(Message("x"), idempotencyKey: "k-1")
        let r = MockURLProtocol.requests
        #expect(r.count == 2 && r.allSatisfy { $0.header("Idempotency-Key") == "k-1" })
    }

    @Test func honoursRetryAfter() async throws {
        MockURLProtocol.script([.error(429, "rate_limited", retryAfter: "1"), .accepted()])
        let start = ContinuousClock.now
        try await mockClient().send(Message("x"))
        #expect(ContinuousClock.now - start >= .seconds(1))
    }

    @Test func retryAfterBeyondTheDeadlineFailsFast() async throws {
        MockURLProtocol.script([.error(429, "quota_exceeded", retryAfter: "7200", extra: #","limit":"messages_per_day""#)])
        let start = ContinuousClock.now
        await #expect {
            try await mockClient().send(Message("x"), idempotencyKey: "q-1")
        } throws: { error in
            guard case HonkError.quota(let f) = error else { return false }
            return f.code == "quota_exceeded" && f.status == 429 && f.retryAfter == .seconds(7200) && f.attempts == 1
                && f.idempotencyKey == "q-1" && (error as! HonkError).isRetryable
        }
        #expect(ContinuousClock.now - start < .seconds(1))
        #expect(MockURLProtocol.requests.count == 1)
    }

    @Test func givesUpAfterRetries() async throws {
        MockURLProtocol.script([.error(503, "unavailable", retryAfter: "0")])
        await #expect {
            try await mockClient(retries: 2).send(Message("x"))
        } throws: { error in
            guard case HonkError.server(let f) = error else { return false }
            return f.attempts == 3 && f.code == "unavailable" && f.requestID == "req_test"
        }
        #expect(MockURLProtocol.requests.count == 3)
    }

    @Test func stopsAtTheDeadline() async throws {
        MockURLProtocol.script([.error(503, "unavailable", retryAfter: "1")])
        let start = ContinuousClock.now
        await #expect(throws: HonkError.self) {
            try await mockClient(retries: 10, deadline: .milliseconds(1500)).send(Message("x"))
        }
        #expect(ContinuousClock.now - start < .milliseconds(1600))
        #expect(MockURLProtocol.requests.count == 2)
    }

    @Test func timeoutError() async throws {
        MockURLProtocol.script([.respond(status: 202, body: "{}", delay: .milliseconds(500))])
        await #expect {
            try await mockClient(timeout: .milliseconds(50), retries: 1).send(Message("x"))
        } throws: { error in
            guard case HonkError.timeout(let f) = error else { return false }
            return f.attempts == 2 && f.code == "timeout" && (error as! HonkError).isRetryable
        }
    }

    @Test func networkError() async throws {
        MockURLProtocol.script([.fail(.cannotConnectToHost)])
        await #expect {
            try await mockClient(retries: 1).send(Message("x"))
        } throws: { error in
            guard case HonkError.network(let f) = error else { return false }
            return f.code == "network_error" && f.attempts == 2 && isUUIDv7(f.idempotencyKey ?? "")
        }
    }

    @Test func cancellationThrowsCancellationError() async throws {
        MockURLProtocol.script([.respond(status: 202, body: "{}", delay: .seconds(2))])
        let honk = try mockClient()
        let task = Task { try await honk.send(Message("x")) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test(arguments: [
        (Step.error(422, "validation_failed", extra: #","fields":[{"field":"severity","code":"invalid_enum","message":"must be one of"}]"#), "validation", "validation_failed"),
        (Step.error(413, "payload_too_large"), "validation", "payload_too_large"),
        (Step.error(401, "invalid_key"), "auth", "invalid_key"),
        (Step.error(403, "project_suspended"), "auth", "project_suspended"),
        (Step.error(409, "idempotency_conflict"), "conflict", "idempotency_conflict"),
        (Step.error(404, "not_found"), "http", "not_found"),
    ])
    func errorMappingIsNeverRetried(step: Step, kind: String, code: String) async throws {
        MockURLProtocol.script([step])
        do {
            try await mockClient().send(Message("x"))
            Issue.record("expected an error")
        } catch let error as HonkError {
            let actual: String =
                switch error {
                case .validation: "validation"
                case .auth: "auth"
                case .conflict: "conflict"
                case .http: "http"
                default: "other"
                }
            #expect(actual == kind)
            #expect(error.failure?.code == code && error.failure?.requestID == "req_test" && error.failure?.attempts == 1)
            #expect(!error.isRetryable && error.failure?.isLocal == false)
        }
        #expect(MockURLProtocol.requests.count == 1)
    }

    @Test func serverRefusalsExposeCodeFieldsAndRequestID() async throws {
        MockURLProtocol.script([.error(422, "validation_failed", extra: #","fields":[{"field":"event_type","code":"invalid_enum","message":"must be one of event, problem, recovery"}]"#)])
        do {
            try await mockClient().send(Message("x"))
            Issue.record("expected an error")
        } catch let error as HonkError {
            let f = try #require(error.failure)
            #expect(f.fields == [FieldError(field: "event_type", code: "invalid_enum", message: "must be one of event, problem, recovery")])
            #expect(f.code == "validation_failed" && f.requestID == "req_test" && !f.isLocal)
            #expect(error.description == "Honk 422 validation_failed: validation_failed happened (event_type must be one of event, problem, recovery) [request req_test]")
        }
        MockURLProtocol.script([.error(401, "invalid_key")])
        do {
            try await mockClient().send(Message("x"))
            Issue.record("expected an error")
        } catch let error as HonkError {
            #expect(error.description == "Honk 401 invalid_key: invalid_key happened [request req_test]")
        }
    }

    @Test func warningsAreReturnedAndPassedToOnWarnings() async throws {
        let warnings = #"[{"field":"title","code":"truncated","message":"title was 212 characters; shortened to 160"},"#
            + #"{"field":"actions[1].url","code":"ignored","message":"not an https, mailto, tel or sms URL; action left out"}]"#
        let seen = Seen()
        MockURLProtocol.script([.accepted(warnings: warnings), .accepted()])
        let honk = try mockClient(onWarnings: { warnings, accepted in seen.append(warnings, accepted.id) })
        let accepted = try await honk.send(Message("x"))
        let expected = [
            Warning(field: "title", code: "truncated", message: "title was 212 characters; shortened to 160"),
            Warning(field: "actions[1].url", code: "ignored", message: "not an https, mailto, tel or sms URL; action left out"),
        ]
        #expect(accepted.warnings == expected)
        #expect(accepted.warnings[0].description == "title truncated: title was 212 characters; shortened to 160")
        #expect(seen.calls.count == 1 && seen.calls[0].0 == expected && seen.calls[0].1 == "msg_01k6h3w4z5x6y7z8a9b0c1d2e3")
        #expect(try await honk.send(Message("y")).warnings.isEmpty)
        #expect(seen.calls.count == 1)  // not called without warnings

        // An older server without warnings, and an odd warning, still accept the message.
        MockURLProtocol.script([.respond(status: 202, body: #"{"id":"msg_old","duplicate":false}"#)])
        #expect(try await mockClient().send(Message("x")).warnings.isEmpty)
        MockURLProtocol.script([.respond(status: 202, body: #"{"id":"msg_odd","warnings":[{"code":"truncated"}]}"#)])
        #expect(try await mockClient().send(Message("x")).warnings == [Warning(field: "", code: "truncated", message: "")])
    }

    @Test func fieldContentsAreSentUnchecked() async throws {
        MockURLProtocol.script([.accepted()])
        let honk = try mockClient()
        try await honk.send(
            Message(
                "bell\u{07}", title: String(repeating: "t", count: 200), groupKey: String(repeating: "g", count: 200), url: "http://example.com",
                actions: [Action(title: "Open", url: "javascript:alert(1)"), Action(title: "a", url: "tel:1"), Action(title: "b", url: "tel:2"), Action(title: "c", url: "tel:3")],
                metadata: ["bad key": 1, "n": .double(.nan)], ttlSeconds: 5
            ), idempotencyKey: "k-1")
        try await honk.send(Message("recovered", eventType: .recovery, sourceSequence: 3))
        try await honk.phew(groupKey: nil, "Backup OK", "fine")
        let r = MockURLProtocol.requests
        #expect(r.count == 3)
        #expect(r[0].json["title"] as? String == String(repeating: "t", count: 200))
        #expect(r[0].json["ttl_seconds"] as? Int == 5 && r[0].json["url"] as? String == "http://example.com")
        #expect(r[0].json["metadata"] as? NSDictionary == ["bad key": 1, "n": "NaN"])
        #expect((r[0].json["actions"] as? [Any])?.count == 4)
        #expect(r[1].json as NSDictionary == ["message": "recovered", "event_type": "recovery", "source_sequence": 3])
        #expect(r[2].json as NSDictionary == ["title": "Backup OK", "message": "fine", "severity": "success", "event_type": "recovery"])
    }

    @Test func aMessageOrATitleIsEnoughNeitherIsRefusedBeforeSending() async throws {
        MockURLProtocol.script([.accepted()])
        let honk = try mockClient()
        try await honk.send(Message(title: "Deploy finished"))
        try await honk.beep("Title only", "")
        #expect(MockURLProtocol.requests.map { $0.json as NSDictionary } == [["title": "Deploy finished"], ["title": "Title only", "severity": "success"]])
        for message in [Message(""), Message("  ", title: " ")] {
            await #expect {
                try await honk.send(message)
            } throws: { error in
                guard case HonkError.validation(let f) = error else { return false }
                return f.isLocal && f.attempts == 0 && f.fields == [FieldError(field: "message", code: "required", message: "is required (send a message or a title)")]
            }
        }
        #expect(MockURLProtocol.requests.count == 2)
    }

    @Test func idempotencyKeysAHeaderCannotCarry() async throws {
        let honk = try Honk(url: "https://honk.example.com", key: testKey)
        for key in ["", "has space", String(repeating: "x", count: 129), "ünicode"] {
            await #expect {
                try await honk.send(Message("x"), idempotencyKey: key)
            } throws: { error in
                (error as? HonkError)?.failure?.fields.first?.field == "Idempotency-Key" && (error as? HonkError)?.failure?.isLocal == true
            }
        }
    }

    @Test func multilineMessageAndLargeSequence() async throws {
        MockURLProtocol.script([.accepted()])
        try await mockClient().send(Message("line1\nline2\ttab\r\n", sourceSequence: (1 << 53) - 1))
        let body = String(decoding: MockURLProtocol.requests[0].body, as: UTF8.self)
        #expect(body.contains(#""source_sequence":9007199254740991"#))
        #expect(body.contains(#""message":"line1\nline2\ttab\r\n""#))
    }

    @Test func proxyHTMLErrorIsRetriedThenReported() async throws {
        MockURLProtocol.script([.respond(status: 502, body: "<html>Bad Gateway</html>")])
        await #expect {
            try await mockClient(retries: 1).send(Message("x"))
        } throws: { error in
            guard case HonkError.server(let f) = error else { return false }
            return f.status == 502 && f.code == nil
        }
        #expect(MockURLProtocol.requests.count == 2)
    }

    @Test func duplicateAndExplicitKey() async throws {
        MockURLProtocol.script([.accepted(duplicate: true)])
        let accepted = try await mockClient().send(Message("x"), idempotencyKey: "deploy-4812")
        #expect(accepted.duplicate)
        #expect(MockURLProtocol.requests[0].header("Idempotency-Key") == "deploy-4812")
    }

}

/// Records `onWarnings` calls (the hook is `@Sendable`).
final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [([Warning], String)] = []
    var calls: [([Warning], String)] { lock.withLock { _calls } }
    func append(_ warnings: [Warning], _ id: String) { lock.withLock { _calls.append((warnings, id)) } }
}

@Suite struct ConfigurationTests {
    @Test func rejectsMissingOrMalformedURLAndKey() {
        let cases: [(String, String, String)] = [
            ("", testKey, "HONK_URL"), ("honk.example.com", testKey, "https://"),
            ("https://h", "", "HONK_KEY"), ("https://h", "hka_mobile", "honk_"),
        ]
        for (url, key, needle) in cases {
            #expect {
                _ = try Honk(url: url, key: key)
            } throws: { error in
                guard case HonkError.invalidConfiguration(let message) = error else { return false }
                return message.contains(needle)
            }
        }
    }

    @Test func normalisesTheURL() throws {
        #expect(try Honk(url: "https://honk.example.com/v1/messages/", key: testKey).url.absoluteString == "https://honk.example.com")
    }

    @Test func fromEnvironment() throws {
        let honk = try Honk.fromEnvironment(["HONK_URL": "https://honk.example.com", "HONK_KEY": testKey, "HONK_SOURCE": "cron"])
        #expect(honk.defaults == Defaults(source: "cron"))
    }

    @Test func uuidv7IsVersion7AndTimeOrdered() throws {
        let a = UUIDv7.make(at: Date(timeIntervalSince1970: 1_700_000_000))
        let b = UUIDv7.make(at: Date(timeIntervalSince1970: 1_700_000_000.001))
        #expect(isUUIDv7(a))
        #expect(a < b)
        #expect(a.prefix(13).replacingOccurrences(of: "-", with: "") == "018bcfe56800")
    }

    @Test func parsesRetryAfter() {
        let now = ISO8601DateFormatter().date(from: "2026-10-02T10:00:00Z")!
        #expect(Honk.parseRetryAfter("3") == .seconds(3))
        #expect(Honk.parseRetryAfter(" 120 ") == .seconds(120))
        #expect(Honk.parseRetryAfter(nil) == nil)
        #expect(Honk.parseRetryAfter("soon") == nil)
        #expect(Honk.parseRetryAfter("Fri, 02 Oct 2026 10:00:30 GMT", now: now) == .seconds(30))
        #expect(Honk.parseRetryAfter("Fri, 02 Oct 2026 09:00:00 GMT", now: now) == .seconds(0))
    }
}
