# Cadence

A personal system for planning days around the areas of your life, filling time blocks with tasks and activities, and seeing honest, minimal scores of what actually happens. Single user, native macOS + iOS, installed from Xcode with a free Apple ID (not for the App Store).

## What it does

- **Areas**: parts of your life (name, color, symbol), each tied to a Google calendar. A read-only **Classes** calendar (Google calendar or a plain `.ics` link) shows your timetable.
- **Tasks** (both apps): one searchable list across Areas, grouped into Overdue, Today, Upcoming and No due date. Filter to due tasks or completed tasks, complete/reopen with Undo, and adjust due dates from the context menu. iPhone Today links straight to tasks needing attention.
- **Plan** (Mac): a day/week calendar. Drag in empty space to make a block, drag blocks to move or resize them, drop backlog items onto blocks. **Today** (iPhone): the same day as a timeline with a week strip.
- **Planning vs logging**: choosing items for a block is just a plan and never changes your scores. Logging a block **Full / Easy / Skipped** is a separate, explicit step.
- **Inbox**: chat-style notes, sorted into a task or activity by OpenRouter or manually, including without an AI key. Pending notes show their actual state. Removing an inbox note keeps its task/activity; delete items from their editor.
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
Apps/Cadence-iOS/           iPhone app (Today timeline, Tasks, Inbox, Areas)
Apps/Cadence-macOS/         Mac app (Plan canvas, backlog inspector, Tasks, Inbox, Insights, Settings)
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

`SETUP.md` covers Google Cloud, signing, secrets and free automatic-renewal options for iPhone (AltStore Classic / SideStore). `bash scripts/package-ios.sh` produces an unsigned `build/Cadence.ipa` for those installers. `TESTING.md` is the manual check that needs real accounts. `DECISIONS.md` logs judgment calls. `PLAN.md` is the historical overhaul plan.
