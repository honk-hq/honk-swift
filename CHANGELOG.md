# Changelog

All notable changes to the `HonkHonk` Swift package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
