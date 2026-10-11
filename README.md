# Cadence

A personal system for planning days around areas of life, filling time blocks with tasks and activities, and seeing honest, minimal scores of what actually happens. Single user, native macOS + iOS, installed from Xcode with a free Apple ID (not for the App Store).

## What it does

- **Areas** — user-defined parts of life (name, color, icon), each mapped 1:1 to a Google calendar. A read-only **Classes** area links your college calendar.
- **Blocks** — Google Calendar events in an Area's calendar. Plan them on the Mac (week grid + backlog); open one on either device to fill it with that Area's activities/tasks and log **Full / Easy / Skipped** (plus unplanned time).
- **Inbox** — chat-style note capture; each note is sorted into an Item by OpenRouter (structured JSON output), with offline queueing, retries, and a soft monthly cost cap.
- **Scores** — hours per activity/area, per-area Form (recent vs baseline/target), overall Follow-through, and quiet milestone Levels. Target proposals appear after 21 days. No streaks, badges, or notifications.
- **Sync** — Google Drive `appDataFolder` (hidden app-private storage), one JSON file per model type, newest-`updatedAt`-wins merged with tombstones. Local SwiftData is always the source of truth for the UI.

## Platforms

- iOS 26 and macOS 26. Swift + SwiftUI + SwiftData + Observation.
- iOS widgets: a **Capture** widget that deep-links into the Inbox composer.

## Code layout

```
Cadence/
  project.yml                 # XcodeGen project definition (never edit .pbxproj)
  Secrets.example.xcconfig    # copy to Secrets.xcconfig (git-ignored)
  Packages/CadenceCore/       # shared Swift package
    Models/                   #   SwiftData models + enums
    Google/                   #   OAuth (PKCE), Calendar REST, Drive appDataFolder sync
    AI/                       #   OpenRouter client, inbox sorter, cost tracking
    Scoring/                  #   pure scoring functions (unit-tested)
    Store/                    #   repositories, queries, mutations, insights, export
  Apps/Cadence-iOS/           # iPhone app (TabView)
  Apps/Cadence-macOS/         # Mac app (NavigationSplitView)
  Apps/CadenceWidgets/        # Capture widget extension
  Apps/Shared/                # views shared by both apps
  Tests/                      # unit tests (scoring math)
```

Shared logic lives in `CadenceCore`; each platform has native layouts built from the shared components in `Apps/Shared`.

## Build / test

```
xcodegen generate
xcodebuild -project Cadence.xcodeproj -scheme CadenceiOS -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Cadence.xcodeproj -scheme CadenceMac build
xcodebuild -project Cadence.xcodeproj -scheme CadenceCoreTests test
```

See `SETUP.md` for the full by-hand setup (Google Cloud, signing, secrets, weekly reinstall). See `DECISIONS.md` for every judgment call made during the build.