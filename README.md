# Cadence

Native macOS and iOS app for planning days around life areas, time-blocking tasks and activities, and tracking honest follow-through and activity scores.

## Features

- **Areas & Calendar:** Each Area links to a Google Calendar (plus a read-only `.ics` or Google Calendar for classes).
- **Plan (Mac) & Today (iPhone):** Interactive day/week canvas on Mac and timeline on iPhone. Planning items into blocks is separate from logging outcomes (**Full / Easy / Skipped**).
- **Tasks & Inbox:** Cross-area task agenda and chat-style inbox sorted via OpenRouter structured outputs or manually.
- **Scores:** Cumulative hours/levels per activity, exponentially weighted Area Form vs. baseline/target, and 7-day follow-through.
- **Sync:** Serverless Mac ↔ iPhone sync via Google Drive `appDataFolder` (newest-`updatedAt` merge with tombstones) over local SwiftData.

## Layout

```text
Packages/CadenceCore/   # Models, EventStore, Google OAuth/Calendar/Drive sync, ICS parser, OpenRouter, Scoring
Apps/Shared/            # Shared views, design system, and demo fixtures
Apps/Cadence-iOS/       # iPhone app (Today timeline, Tasks, Inbox, Areas)
Apps/Cadence-macOS/     # Mac app (Plan canvas, backlog inspector, Tasks, Inbox, Insights)
Tests/                  # Unit tests (scoring, logging, sync merge, ICS, layout, migration)
```

## Build & Test

```bash
xcodegen generate
xcodebuild -project Cadence.xcodeproj -scheme CadenceMac build
xcodebuild -project Cadence.xcodeproj -scheme CadenceiOS -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Cadence.xcodeproj -scheme CadenceCoreTests test
```

See `SETUP.md` for Google OAuth, signing, and iOS packaging.
