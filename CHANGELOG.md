# Changelog

All notable changes to the `HonkHonk` Swift package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `Accepted.warnings`: what the server corrected before accepting the message (`Warning` with `field`,
  `code`, `message`; codes `truncated`, `normalized`, `ignored`, `clamped`, `downgraded`, `hashed`),
  empty when nothing. An optional `onWarnings` closure on `Honk(…)` and `Honk.fromEnvironment(…)` is
  called after a send that has any.
- A title-only message: `Message(title: "Deploy finished")` (`message` defaults to `""`); a
  message or a title is required.

### Changed
- **Breaking:** the library is a thin wrapper of the "deliver first" server (contracts/API.md
  §5.1). It no longer checks field contents (lengths, enums, URLs, actions, metadata, TTL,
  `source_sequence`, the 16 KiB body): the server shortens or leaves out what it cannot use and
  accepts the message with a warning, and refuses only what it cannot deliver. Before sending,
  only a missing message and title (and an Idempotency-Key a header cannot carry) throw
  `HonkError.validation` with `isLocal`.
- `uhoh`/`phew`/`problem`/`recovery` take an optional `groupKey`:
  recoveries and `sourceSequence` no longer need one; without one, messages group by title.
- `HonkError.description` ends with the server's request id (`[request req_…]`).
- Non-finite metadata numbers (`.nan`, infinities) are sent as text instead of failing the send.
- The docs say that the level alone decides how the push interrupts, and that `.urgent` from a key
  without "allow urgent" is sent as `.high` (it used to be `403 priority_not_allowed`).

### Removed
- **Breaking:** the `validate:` parameter and `Honk.validates`, and the `Limits` enum.

## [0.4.1] - 2026-10-18

### Changed
- The README calls the product Honk! Honk!; the package, the module and the API are unchanged.

## [0.4.0] - 2026-10-15

### Changed
- The module and product are now `HonkHonk` (`import HonkHonk`), at github.com/honk-hq/honk-swift.

## [0.3.0] - 2026-10-14

### Added
- `honk(_:idempotencyKey:)`, `uhoh(groupKey:_:_:idempotencyKey:_:)` and
  `phew(groupKey:_:_:idempotencyKey:_:)` on `Honk`.
- `send`, `problem` and `recovery` stay, without deprecation warnings, as plain aliases of
  `honk`, `uhoh` and `phew`: same arguments, same results.

Upgrading from 0.2: bump the version (`from: "0.3.0"`); nothing else changes. The import stays
`import HonkMe` (the module), and `Honk` is still the client type.

## [0.2.0] - 2026-10-07

### Added
- `Message.actions`: up to 3 `Action(title:url:)` buttons (`https://`, `mailto:`, `tel:` or
  `sms:`), sent as `actions` and omitted when empty. Validated locally like the server, with
  errors on `actions`, `actions[i].title` and `actions[i].url`; `Limits.actions` and
  `Limits.actionTitle`.

## [0.1.0] - 2026-10-04

### Added
- `Honk` client for `POST /v1/messages` (Swift 6.2, strict concurrency, `Sendable`, async/await),
  iOS 17+ / macOS 14+ / Linux, no dependencies; `Honk.fromEnvironment()`.
- `Message` with every field of the v1 ingestion API (including `imageURL`), `MetadataValue`
  literals, `Defaults`, `Accepted`.
- The Honk scale: `Severity.light/.beep/.loud/.long/.blast` aliases, `Severity(parsing:)`, and
  the `light`, `beep`, `loud`, `long`, `blast` helpers (plus `info` … `critical` synonyms),
  `problem(groupKey:)` and `recovery(groupKey:)`.
- Automatic UUIDv7 `Idempotency-Key` (or your own), reused on every retry; retries for network
  errors, timeouts, 429 and 5xx with exponential backoff, full jitter, `Retry-After` and a total
  deadline; redirects are reported, never followed.
- `HonkError` cases (`validation`, `auth`, `quota`, `conflict`, `network`, `timeout`, `server`,
  `http`, `invalidConfiguration`) with `Failure` details; local validation of every field.
