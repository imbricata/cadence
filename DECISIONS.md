# Cadence — Decision Log

Every non-obvious choice made while building, one line each. Appended chronologically.

## Foundation

- Swift 5 language mode (not Swift 6 strict concurrency) to keep SwiftData + @Observable code free of concurrency errors; spec explicitly permits this.
- Bundle IDs fixed as `com.cadence.ios`, `com.cadence.mac`, `com.cadence.widget` (short + stable; free Personal Team only registers a handful of App IDs/week).
- Unit tests live in an Xcode unit-test bundle (`CadenceCoreTests`, macOS, hostless) so `xcodebuild test` works without a simulator; scoring APIs are `public` and imported without `@testable`.
- Synced models use plain `UUID`/`Date`/`Bool` fields and soft ID references (areaId, itemId), not SwiftData relationships, for trivial JSON sync and tombstone propagation.
- Enums are stored directly on `@Model`s as `String, Codable` raw-enums (SwiftData persists Codable raw enums); JSON sync encodes them to strings.
- Area palette: 10 muted hex colors (see `AreaPalette`); Area stores a hex string, UI interprets with `Color(hex:)`.
- Updated-At is set explicitly in the store layer on every mutation (not via model machinery), keeping sync semantics predictable.