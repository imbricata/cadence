# Cadence

A personal system for planning days around the areas of your life, filling time blocks with tasks and activities, and seeing honest, minimal scores of what actually happens. Single user, native macOS + iOS, installed from Xcode with a free Apple ID (not for the App Store).

## What it does

- **Areas**: parts of your life (name, color, symbol), each tied to a Google calendar. A read-only **Classes** calendar (Google calendar or a plain `.ics` link) shows your timetable.
- **Plan** (Mac): a day/week calendar. Drag in empty space to make a block, drag blocks to move or resize them, drop backlog items onto blocks. **Today** (iPhone): the same day as a timeline with a week strip.
- **Planning vs logging**: choosing items for a block is just a plan and never changes your scores. Logging a block **Full / Easy / Skipped** is a separate, explicit step.
- **Inbox**: chat-style notes, each sorted into a task or activity by OpenRouter (structured output, offline queue, retries, monthly cost cap).
- **Scores**: hours and levels per activity, Form per area (recent vs. your normal or your target), and follow-through over recent weeks. No streaks, badges or notifications.
- **Sync**: Google Drive `appDataFolder`, one JSON file per model type, newest-`updatedAt`-wins with tombstones. Local SwiftData is always the source of truth.

## Code layout

```
project.yml                  XcodeGen project (never edit the .pbxproj)
Packages/CadenceCore/        shared Swift package
  Models/                    SwiftData models + enums
  Calendar/                  EventStore (per-calendar cache), EventSource, EventLayout (pure geometry)
  Google/                    OAuth (PKCE), Calendar REST, Drive sync, ICS parser, GoogleService
  AI/                        OpenRouter client, inbox sorter, cost tracking
  Scoring/                   pure scoring functions
  Store/                     queries, mutations, block logging rules, InsightsModel
Apps/Shared/                 views used by both apps (+ Design/: theme, colors, components; Demo/: DEBUG fixtures)
Apps/Cadence-iOS/           iPhone app (Today timeline, Inbox, Areas)
Apps/Cadence-macOS/         Mac app (Plan canvas, backlog inspector, Inbox, Insights, Settings)
Tests/                       unit tests (scoring, logging rules, sync merge, ICS, event store, layout)
scripts/                     screenshot helpers for demo mode
```

## Build / test

```
xcodegen generate
xcodebuild -project Cadence.xcodeproj -scheme CadenceMac build
xcodebuild -project Cadence.xcodeproj -scheme CadenceiOS -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Cadence.xcodeproj -scheme CadenceCoreTests test
```

`SETUP.md` has the by-hand setup (Google Cloud, signing, secrets, weekly reinstall). `TESTING.md` is the short manual check that needs real accounts. `DECISIONS.md` logs every judgment call. `PLAN.md` is the plan the overhaul followed.
