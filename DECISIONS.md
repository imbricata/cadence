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

## Blocks (Phase 3)

- Blocks are Google Calendar events: summary = Area name, plus a private extended property `cadence=1` to distinguish blocks from the Classes calendar.
- Move = drag an area block vertically (same calendar, other day via edit); Resize = drag the block's bottom edge (3pt handle); both map to Calendar event PATCH. Tap empty day space = create a 1-hour block at the tapped 15-min-snapped time (no rubber-band drag-to-create; kept simple).
- Drag a backlog item onto a block = add it Full with a share of the block's minutes.
- Logging: block outcome Full/Easy/Skipped + logged minutes + note; each item entry has its own outcome+minutes. Easy minutes are halved. Task Full -> done (completedAt), Easy/Skipped -> stays open (and reopens if previously done).

## Inbox + AI (Phase 4)

- OpenRouter structured output via `response_format: json_schema` (strict), `temperature 0`, `max_tokens 150`, plus the `models` fallback array. Reasoning is left off by default (no reasoning field sent).
- API key lives in the Keychain (service `com.cadence.openrouter`); model id + monthly cap live in UserDefaults. Cost is estimated from reported token usage against a rough price table (documented as estimates).
- When the sorter matches an existing activity (`matchesExistingActivityId`), the note links to that Activity and no duplicate is created.
- Invalid output -> retry once -> then counted as a failure; 3 failures -> `failed` (offers "Sort manually"). Raw text is always hidden and cleared 30 days after a successful sort.
