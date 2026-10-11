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
## Google (Phase 2)

- OAuth uses `ASWebAuthenticationSession` + PKCE (S256), no Google SDK/SPM dependency. Requires one "Web application" OAuth client with redirect `cadence://oauth2redirect`; the same client ID works for both apps (still two xcconfig keys).
- Google Calendar events are fetched as a rolling ~window (no `syncToken`); cached to a JSON file on disk for offline viewing. Token kept in the macOS/iOS Keychain and refreshed before expiry.
- Drive sync stores one JSON file per model type in `appDataFolder` (areas, items, inbox, blocklogs, blockentries, unplanned, targets). Merge = newest `updatedAt` wins; tombstones propagate deletes and are dropped after 90 days.
- Drive upload = multipart create (name+parents) for new files, media-only PATCH for updates.
- Area color writes are pushed to the Google calendar's `backgroundColor` (calendarList) where a calendar is linked; event colorId is left default.
