# HonkHonk (Swift)

[![CI](https://github.com/honk-hq/honk-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/honk-hq/honk-swift/actions/workflows/ci.yml)

Official Swift client for [Honk! Honk!](https://honk-honk.app), the inbox that turns events from your
apps, scripts, cron jobs and CI into calm, grouped push notifications on your phone.

```swift
import HonkHonk

let honk = try Honk.fromEnvironment()

try await honk.honk(Message("Someone bought 3 rubber chickens", title: "New order", severity: .beep))
try await honk.uhoh(groupKey: "shop/stock", "Rubber chickens sold out", "Someone bought the last 3.")
// a supplier is called, a van is loaded
try await honk.phew(groupKey: "shop/stock", "Rubber chickens restocked", "200 more in the warehouse. Squeak responsibly.")
```

A sale, then a problem and its fix: `uhoh` opens an incident for `shop/stock` and `phew` closes
it, so your phone tells one short story instead of raising two alarms.

- Swift 6.2+, strict concurrency, `Sendable` throughout, async/await. No dependencies.
- macOS 14+, iOS 17+ and Linux (URLSession via FoundationNetworking).
- Retries with backoff, `Retry-After`, a total deadline and an idempotency key on every send,
  so a retry never creates a duplicate.

> **Keep the key on the server.** An ingestion key (`honk_…`) lets anyone post into your
> project, and anything shipped inside an app can be extracted. **Never embed it in an iOS,
> macOS or other client app.** Use this package where the key stays private: server-side Swift
> (Vapor, Hummingbird), macOS tools and agents you run yourself, CLIs and CI. A client app that
> needs to notify you should call your own backend, which then calls Honk! Honk!

## Install

```swift
// Package.swift
.package(url: "https://github.com/honk-hq/honk-swift.git", from: "0.4.0"),
// target:
.product(name: "HonkHonk", package: "honk-swift"),
```

The import is `import HonkHonk`: `HonkHonk` is the module, `Honk` is the client type inside it.
In Xcode: *File → Add Package Dependencies…* and paste `https://github.com/honk-hq/honk-swift`.
Create a project and an ingestion key at [honk-honk.app](https://honk-honk.app). Its
*Integrations* page generates ready-to-paste code for this package.

## Quick start

```swift
import HonkHonk

let honk = try Honk.fromEnvironment()          // HONK_URL, HONK_KEY (+ HONK_SOURCE, HONK_ENVIRONMENT, HONK_CHANNEL)
try await honk.beep("Backup finished", "nightly pg_dump took 42 s")
```

Or explicitly: `let honk = try Honk(url: "https://honk.example.com", key: key)`. The initialiser
throws `HonkError.invalidConfiguration` for a missing or malformed URL or key.

## The Honk scale

Five levels. The Honk app shows them by their standard names (Info, Success, Warning, Error,
Critical); people who prefer horn sounds can switch on the Honk names (Light, Beep, Loud, Long,
Blast) with the "Honk names for levels" switch in Settings. The SDK takes both: the canonical values and the
Honk names as input aliases, in any case, and always sends the canonical value.

| Level | Honk name | Severity | Method | Value |
|---|---|---|---|---|
| Info | Light | `light` (info) | `honk.light(title, message)` | `Severity.light` |
| Success | Beep | `beep` (success) | `honk.beep(…)` | `Severity.beep` |
| Warning | Loud | `loud` (warning) | `honk.loud(…)` | `Severity.loud` |
| Error | Long | `long` (error) | `honk.long(…)` | `Severity.long` |
| Critical | Blast | `blast` (critical) | `honk.blast(…)` | `Severity.blast` |

`Severity.loud == .warning`; `Severity(parsing: "LOUD")` accepts horn and canonical names in any
case. `long` and `blast` push at least as high priority. `info`, `success`, `warning`, `error`
and `critical` remain as synonyms.

## Recipe: notify me when a customer asks for something (Vapor)

One group per request (`requests/<id>`) and a stable idempotency key: two different customers
never fold into one notification, and a retried request never buzzes twice.

```swift
import HonkHonk
import Vapor

func routes(_ app: Application, honk: Honk) {
    app.post("quote") { req async throws -> HTTPStatus in
        let quote = try req.content.decode(QuoteRequest.self)
        try await quote.save(on: req.db)                               // store it first
        let id = try quote.requireID()
        // Message is Sendable: build it here, send it off the request path.
        let message = Message(
            "\(quote.name) (\(quote.company)) asked: \(quote.body.prefix(2000))",
            title: "New request: \(quote.subject)".prefix(150).description,
            severity: .light,
            priority: .high,                                           // push right away
            category: .customers,
            channel: "requests",
            groupKey: "requests/\(id)",                                // one group per request
            url: "https://shop.example.com/admin/requests/\(id)",      // https only
            metadata: ["request_id": .string("\(id)")]
        )
        let logger = req.logger
        Task {
            do { try await honk.honk(message, idempotencyKey: "request-\(id)") }   // same request, same key
            catch { logger.warning("honk: \(error)") }
        }
        return .accepted
    }
}
```

Create the `Honk` once at startup and share it: it is `Sendable` and owns a keep-alive
`URLSession`.

## Grouping in three lines

Messages with the same `groupKey` (per project, environment, source and channel) form one group:
the first one pushes, repeats update it calmly instead of buzzing again. Use one key per customer
request (`requests/<id>`), and a shared key only for repeats of the same problem
(`queue/failed-jobs`). `uhoh`/`phew` pairs need a `groupKey`.

## Sending

```swift
@discardableResult
func honk(_ message: Message, idempotencyKey: String? = nil) async throws -> Accepted   // id, duplicate, receivedAt
```

```swift
let message = Message("Billing API could not connect to Redis", title: "Redis down", severity: .long,
                      groupKey: "billing/redis", url: "https://status.example.com/redis",
                      metadata: ["host": "app-01", "attempts": 3])
try await honk.honk(message, idempotencyKey: "redis-down-2026-10-03")
```

| Field | Notes |
|---|---|
| `message` | **required**, 1–8192 bytes UTF-8, line breaks allowed |
| `title` | ≤ 160 characters, one line; default: first line of `message` |
| `severity` | `.light` `.beep` `.loud` `.long` `.blast` (or `.info` … `.critical`) |
| `priority` | `.low` `.normal` `.high` `.urgent` (`urgent` needs a key with *allow urgent*) |
| `category` | `.infrastructure` `.security` `.backups` `.deployments` `.payments` `.customers` `.sales` `.automation` `.personal` `.other` |
| `source` / `environment` / `channel` | ≤ 64 / 32 / 64 characters; default `api` / `default` / `general` or `Defaults` |
| `groupKey` | ≤ 128 characters |
| `eventType` | `.event` `.problem` `.recovery` (`recovery` needs `groupKey`) |
| `occurredAt` | `Date`, sent as UTC RFC 3339 with milliseconds |
| `url` / `imageURL` | `https://` only, no credentials (`imageURL`: no `#fragment`; fetched by the server afterwards) |
| `actions` | up to 3 `Action(title:url:)` buttons, see [Actions](#actions) |
| `metadata` | `[String: MetadataValue]`, literals work; ≤ 16 keys `[A-Za-z0-9_.-]{1,64}`, strings ≤ 512 characters |
| `ttlSeconds` | push lifetime 60–86400 (default 3600) |
| `sourceSequence` | `Int64`, 0 … 2^53-1, needs `groupKey` |

nil and empty optional fields are omitted. A returned `Accepted` means Honk! Honk! **durably stored**
the message (202), not that a push was delivered or read.

Helpers take the title, the message, an optional idempotency key and a closure that edits the
message:

```swift
try await honk.loud("Disk 91%", "/var on app-01") { $0.groupKey = "disk/app-01/var" }
try await honk.uhoh(groupKey: "db/backup", "Backup failed", "pg_dump exited with 1")   // a problem: a Long message by default
try await honk.phew(groupKey: "db/backup", "Backup OK", "pg_dump finished in 41 s")    // its recovery: a Beep message by default
```

`send`, `problem` and `recovery` still work: they are `honk`, `uhoh` and `phew` under their 0.2
names, with no deprecation warning.

Options: `Honk(url:key:timeout:retries:deadline:defaults:validate:backoff:configuration:userAgent:)`
with `timeout` 5 s per attempt, `retries` 4, `deadline` 30 s, a `URLSessionConfiguration`
(proxies; redirects are never followed) and `validate: false` to leave all checks to the server.

## Actions

Up to three buttons on a message, in display order (the first is the primary). Honk! Honk! never opens
them; the phone does when you tap one: Mail for `mailto:`, the Phone app for `tel:`, Messages for
`sms:`, Safari for `https://`.

```swift
try await honk.light("New quote request", "Maria Tudor asked for a quote: 3 rooms, 2 bathrooms") {
    $0.groupKey = "requests/4812"
    $0.actions = [
        Action(title: "Reply", url: "mailto:maria@example.com?subject=Your%20quote"),
        Action(title: "Call", url: "tel:+15550134"),
    ]
}
```

A title is 1–40 characters on one line, shown as sent. A URL is at most 2048 bytes without
spaces: `https://` (no credentials), `mailto:` with one address and an optional
`?subject=…&body=…`, `tel:` with a number, or `sms:` with a number and an optional `?body=…`.
Anything else (`http:`, `javascript:`, app schemes) is rejected as `actions[i].url`.

## Retries and idempotency, guaranteed

- Every send carries an `Idempotency-Key`: yours, or a fresh UUIDv7 (`UUIDv7.make()`). **The same
  key is reused on every retry.** Within 24 h Honk! Honk! answers a replay with the original id and
  `duplicate == true`, so a lost response never creates a second message.
- Only network errors, timeouts, `429` and `5xx` are retried, with exponential backoff and full
  jitter (`random(0, min(8 s, 0.5 s·2ⁿ))`), never sooner than the server's `Retry-After`.
- Everything stops at the deadline: if the next wait would cross it (for example a daily quota
  that resets at midnight), the error is thrown at once with `retryAfter`.
- `4xx` other than `429` are never retried; task cancellation stops everything with
  `CancellationError`.

## Errors

`HonkError` cases carry a `Failure` (`status`, `code`, `message`, `fields`, `isLocal`,
`requestID`, `idempotencyKey`, `attempts`, `retryAfter`); `error.isRetryable` tells what to do.

| Case | When | What to do |
|---|---|---|
| `.validation` | rejected locally (`isLocal`) or `400`/`413`/`415`/`422`; `fields` lists every problem | fix the message |
| `.auth` | `401 invalid_key`, `403 priority_not_allowed`, `project_suspended`, `workspace_suspended` | fix the key or the priority |
| `.quota` | `429 quota_exceeded` (daily) or `rate_limited`, after retries | retry after `retryAfter` |
| `.conflict` | `409 idempotency_conflict`: same key, different payload | new key or original payload |
| `.network` / `.timeout` | unreachable / no answer before the deadline | retry later, same key |
| `.server` | `5xx` on every attempt | retry later, same key |
| `.http` | anything else (wrong URL → 404, a redirect) | fix the URL |
| `.invalidConfiguration` | bad URL or key passed to `Honk(url:key:)` | fix the configuration |

```swift
do {
    try await honk.long("Payment failed", "Stripe declined order 1042") { $0.groupKey = "payments/stripe" }
} catch HonkError.validation(let failure) {
    logger.error("bug: \(failure.fields)")
} catch let error as HonkError where error.isRetryable {
    queue.retryLater(key: error.failure?.idempotencyKey)
}
```

## Development

```sh
swift test                                           # Swift Testing, mock URLProtocol
HONK_URL=… HONK_KEY=… swift test --filter Integration   # against a real server (use a test project's key)
```

The version lives in `Honk.version` (also the User-Agent). Releases: push a tag `vX.Y.Z`
matching it; the tag is the release for SwiftPM (see `CHANGELOG.md`).

## Links

- [honk-honk.app](https://honk-honk.app): the Honk! Honk! inbox (web, iPhone).
- Other SDKs: [Node.js](https://github.com/honk-hq/node),
  [PHP / Laravel](https://github.com/honk-hq/php), [Go + CLI](https://github.com/honk-hq/go),
  [Kotlin / Java](https://github.com/honk-hq/kotlin).

MIT License.
