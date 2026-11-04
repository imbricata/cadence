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

- OAuth uses `ASWebAuthenticationSession` + PKCE (no Google SDK). Two iOS-type OAuth clients (bundle ids com.cadence.ios / com.cadence.mac); redirect is the reversed client id `com.googleusercontent.apps.<id>:/oauth2redirect` (Google rejects custom schemes on Web clients). The session intercepts the callback itself, so no Info.plist URL scheme is needed for auth.
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

## Scores (Phase 5)

- All scoring constants live in `ScoringConfig` (7/28-day half-lives, form cap 200%, 14-day calibration, easy weight 0.75, 7-day follow-through, 21-day target proposal, level thresholds 10/25/50/100/250/500/1000 h).
- Easy minutes are stored as actual logged minutes; form applies the x0.75 weight only when scoring (so "hours" and "levels" use real time).
- Form reference = target weekly/7 once set, otherwise the baseline (28-day EW daily average). Before 14 observed days with no target, form shows "Calibrating" (nil).
- Target proposal = median of observed ISO-week minute totals; shown once per area (UserDefaults flag).
- Follow-through planned count comes from cached non-class events plus any local block logs in the last 7 days (union keyed by event id); logged weight from the matching block log state.

## Design (visual approach)

- Native materials, no gradients/emoji/illustrations. Color comes only from the 10 muted Area palette via small dots, thin bars, and translucent block fills; everything else neutral. Monospaced digits for numbers. Calm one-line empty states. Subtle rounded cards (secondary.opacity(0.06)) for Insight groups.

## Widgets & polish (Phase 6)

- Only the Capture widget (systemSmall + lock-screen accessory), which just deep-links `cadence://capture` and needs no shared data. The "Next-block" widget is skipped because it needs App Groups + App Intents, which are not reliably available on a free Personal Team (per SPEC Section 1).
- Widget bundle id is `com.cadence.ios.widgets` (must inherit the parent app id).
- Mac keyboard shortcuts via a Commands menu: Cmd+N new note, Cmd+Shift+B new block, Cmd+Left/Right previous/next day, Cmd+T today, Cmd+S sync.
- JSON export reuses the sync snapshot structs (pretty-printed, ISO-8601 dates) and uses SwiftUI `.fileExporter`.
- Bundle ids fixed as: iOS `com.cadence.ios`, macOS `com.cadence.mac`, widget `com.cadence.ios.widgets`.
- Review fixes: the calendar list includes read-only calendars (so a subscribed college calendar shows up); creating an area auto-creates its Google calendar (also for existing areas on sign-in); rename/recolor pushes to Google.
- Bundle IDs renamed to `com.theocoronges.cadence` / `.widgets` / `.mac` because `com.cadence.ios` was already registered by someone else on Apple's Personal Team registry (Xcode "cannot register ... not available").
- Widget removed at owner request (app-only install). App icons added: single-size 1024 for iOS, full multi-size set for macOS, generated from the Cadence mark (teal bars on light background, full-bleed opaque).
- Classes can now be an ICS feed URL instead of a Google calendar: the app fetches + parses the raw `.ics` directly (auto-updating), because Google's Calendar API returns 400 for URL-subscribed calendars (e.g. Blackboard Learn feeds).

## Overhaul

- Phase 1: added `LogOutcome.planned` (weight 0) = "in the block, not logged". Planning (`planItem`) never touches scores or tasks; only `logBlock` / `setEntryOutcome` do. Opening a block no longer creates a `BlockLog`.
- Scores count only Full/Easy entries in blocks that are not `unlogged`; Skipped and planned are 0 minutes. Block-level minutes are used only when a block has no item entries.
- Form uses a dense daily series (zero-filled) from the first logged day; today is included only once something is logged, so mornings don't drag form down.
- Default minutes: Full = item's share of the block, Easy = half of that (rounded to 5), Skipped = 0.
- Follow-through: planned = non-Classes, non-all-day, non-zero-length events on Area calendars that have started, plus logged blocks missing from the cache. Per-day/week values are sums, keyed by event id + start.
- `InboxNote.isLowConfidence` added (default false, `decodeIfPresent` in sync). Sync now refuses to overwrite a Drive file it cannot decode (throws `SyncError.undecodable`) instead of treating it as empty. **Update both devices together** after this change: an old build cannot decode the new `planned` outcome.
- Phase 2: `EventStore` caches events per calendar with the loaded date ranges; views call `google.ensureEvents(in:)` for what they show, refreshes replace only their own calendar+range, and a local edit during a download discards that stale download. History is kept 60 days.
- `GoogleService` is now a facade over `EventStore` + `SyncEngine`. Sync: on activation, every 5 min while active, 5 s (debounced) after local saves, on sign-in (before any calendar is created), and via Sync Now; syncs are serialized and `lastSyncAt` is persisted.
- Connection state: only a 401 / insufficient-scope / `invalid_grant` means "reconnect"; network errors mean "offline"; rate-limit 403s are neither. Cancelling sign-in changes nothing.
- Calendars Cadence creates carry the description `Cadence area <uuid>`; before creating one, an existing tagged calendar is linked instead (prevents duplicates when a second device signs in).
- Block edits (create, move, resize, change area, delete) are optimistic with rollback and a toast message; delete offers Undo (PATCH the cancelled event back to confirmed). Moving a block re-keys its `BlockLog`.
- ICS: full RRULE (DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, COUNT, UNTIL, BYDAY incl. ordinals, BYMONTHDAY, BYMONTH), EXDATE, RECURRENCE-ID overrides, DURATION, per-property TZID (with common Windows names), unique per-instance ids. Zero-length events are "deadlines" (`CalendarEvent.isDeadline`) and go in the all-day strip.
- `InsightsModel` replaces every `computeInsights` call in views (300 ms debounce on store/event changes).
- Phase 3: design system in `Apps/Shared/Design/` (Theme spacing/radii, `AreaColor` with derived dark variants, chips, `ChipFlow`, `OutcomePicker`, `MinutesField`, `StatusBanner`, toast). Brand `AccentColor` (#4F8C87 light / #6FB3AD dark) in both asset catalogs; Classes are always neutral grey.
- Demo mode (`-CadenceDemo YES`, DEBUG only) seeds an in-memory store + fake calendar; `-CadenceTab`, `-CadenceSection`, `-CadenceSheet` jump to screens. `scripts/mac-shot.sh` and `scripts/ios-shot.sh` capture screenshots (iPhone 17 simulator, iOS 27).
- Mac: Areas live in the sidebar (like Reminders lists), backlog is an inspector, commands use FocusedValues (⌘S dropped for ⌘R), Settings is a tabbed window, ⌘N opens a Quick Note sheet. iOS: Settings is a sheet from a gear on every tab. The leftover widget URL/notification plumbing was removed.
- Phase 4: Mac Plan rewritten as `CalendarCanvas` (day/week). One owner for all interaction: drag empty space to create (live 15-min ghost + Area picker popover), double-click for a 1 h ghost, drag a block to move (snaps, crosses days), drag top/bottom edges to resize, Esc cancels, Return/double-click opens the block popover, Delete removes (confirm only if logged, Undo otherwise), right-click menu (Open, Log, Change Area, Delete), backlog items drop on blocks (plan) or empty space (new block in the item's Area). Overlapping blocks cascade (later ones sit over the right side) instead of splitting into unreadably thin lanes. Layout math lives in `CadenceCore.EventLayout` (tested). Default scroll is 07:00, or just before now between 09:00 and 17:00.
- Screenshots only ever capture Cadence's own windows (`screencapture -l <window id>`); no synthetic mouse/keyboard input is used.
- Phase 5: iPhone Today is a real timeline (shared `EventLayout`): week strip (tap or swipe), deadline/all-day strip, now line, cascaded overlaps, swipe the timeline to change day, tap empty time for Quick Create (last-used Area, duration chips), tap a block for the detail sheet, long-press for Log / Change Area / Delete. Title is inline (the strip already shows the date). The timeline scales with Dynamic Type; the week strip and header are capped at xxxLarge so seven days always fit.
- Phase 6: one shared Inbox (chat order, day headers, low-confidence marker, swipe/context delete removes the item too, key hint when no OpenRouter key, Return sends on Mac). Item editor has Area chips, status and Delete (with Undo); Area editor can link an existing Google calendar, archive, or delete (optionally deleting the calendar too, default keeps it). Area detail has a Form header with a 100% tick, Recent logs and collapsed Done. Insights uses Swift Charts for the 8-week follow-through line plus Form, this-week-vs-target, and hours by activity. Block detail uses chips to add activities and `MinutesField` / `OutcomePicker`.

## Daily usability — November 2026

- Shared Tasks screen (iPhone tab / Mac sidebar) brings all active Areas' open tasks together by date; Due includes overdue + today, Done excludes dropped tasks, and search includes titles, Area names and notes.
- Date-only task deadlines follow the current calendar, including daylight-saving boundaries; the list refreshes its date groups while open.
- Today links directly to due tasks and can create a task without navigating through Areas. Its date/follow-through header stacks when text needs more space.
- Screenshot review: Mac Tasks uses a centered readable column; compact calendar blocks show start times and clip content to their bounds so text never spills into adjacent blocks on either platform.
- Inbox manual sorting is available for pending and failed notes, including when no AI key is configured; it includes due-date editing. Removing a note only removes capture history, preserving tasks and shared activities (supersedes the previous Inbox deletion behavior).
- Inbox processing is single-flight, drains newly captured notes, checks the monthly cap between requests, and ignores responses superseded by manual sorting/deletion. Re-sorting updates the existing item instead of creating a duplicate.
- Persistence correction: the old stored `isDeleted` name collided with Core Data's internal deletion getter and read false after saving. All seven models now store `isTombstoned` with `@Attribute(originalName: "isDeleted")`; the public computed `isDeleted` and JSON wire key are retained. This is a deliberate exception to PLAN's no-renaming rule: an additive flag cannot recover the unreadable legacy values. A synthetic on-disk legacy-schema test verifies all seven models migrate, including active/deleted records, IDs, timestamps and data, plus delete/undo across contexts.
- Demo mode uses an injected empty AI-key provider, so screenshot runs cannot send fixture notes to OpenRouter; `-CadenceAppearance light|dark`, `-CadenceTaskFilter due|done` and `-CadenceSheet task` support review of the new screens.
- Free iPhone signing still lasts seven days; AltStore Classic or SideStore can automate refresh. `scripts/package-ios.sh` produces a Release unsigned IPA, verifies its bundle ID, and stages a fresh archive each time; installer setup remains a device/account step.
