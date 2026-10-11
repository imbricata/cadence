# Cadence: Product & Technical Spec

> Working title. A personal system for planning days around areas of life, filling time blocks with tasks and activities, and seeing honest, minimal scores of what actually happens.
> Single user (me). Native macOS + iOS apps, installed from Xcode with a **free Apple ID (Personal Team)**. Not for the App Store.

---

## 0. How to work on this (instructions for the coding agent)

**Build the entire app in one uninterrupted run. Do not stop to ask me questions or wait for approval.**

- Read this whole file first. Then work through the phases in Section 11 in order, without pausing between them.
- When something is ambiguous, choose the most reasonable option, keep going, and record the choice in `DECISIONS.md` (one line each).
- After each phase: build **both** apps with `xcodebuild` and run the unit tests. Fix all errors before moving on. Never leave the project in a non-compiling state at the end.
- Use **XcodeGen** (`project.yml`) to define the Xcode project. Never hand-edit `.pbxproj`. Regenerate with `xcodegen generate` after changing targets/files.
- **Keep token usage low:**
  - Pipe builds through `xcbeautify` (or use `-quiet`) and only look at errors/warnings, never full build logs.
  - Don't re-read files you just wrote. Read only the files you need.
  - Prefer small focused files over huge ones, so edits are cheap.
- **Toolchain flexibility:** don't hardcode Xcode/SDK versions beyond the minimum deployment targets. Check what's installed (`xcodebuild -version`, `xcodebuild -showsdks`) and use only APIs available in that SDK. If unsure an API exists, use a well-established alternative rather than guessing. Use Swift 6 language mode if it compiles cleanly; otherwise Swift 5 mode is acceptable.
- Never commit secrets. Google client ID and similar go in a git-ignored `Secrets.xcconfig`; provide `Secrets.example.xcconfig`. The OpenRouter key is entered in the app's Settings at runtime, not built in.
- Commit to git at the end of each phase with a clear message.
- **At the very end**, write:
  - `SETUP.md`: everything I must do by hand, as plain numbered steps (Google Cloud project + OAuth client, consent screen to "In production", filling `Secrets.xcconfig`, signing with my Personal Team, installing on iPhone and Mac, reinstalling weekly, entering the OpenRouter key).
  - `README.md`: what the app is and how the code is organized (short).
  - A final summary in chat: what works, what's untested, anything I should check first.
- **Finally, push to my GitHub** using my git push skill. Use a **private** repo named `cadence` (create it if it doesn't exist). Before pushing, double-check that `Secrets.xcconfig` and any keys/tokens are git-ignored and not in the history.
- UI quality bar: this should feel like a first-party Apple app. See Section 9. Restraint over features.

---

## 1. Platforms & stack

- **Minimum** macOS 26 and iOS 26 (deployment target 26.0). Must keep working as I update to newer OS/Xcode versions, so avoid deprecated or beta-only APIs.
- Hardware: M1 Pro Mac, iPhone 15.
- **Swift + SwiftUI**, Observation (`@Observable`). No UIKit/AppKit unless strictly necessary.
- **Signing: free Personal Team only.** That means:
  - No CloudKit / iCloud, no push notifications, no paid-only capabilities.
  - Keep bundle IDs fixed once chosen (free accounts can only register a few App IDs per week). Use as few targets as possible.
  - iPhone install expires every 7 days and I reinstall from Xcode. Data must survive reinstalling (same bundle ID keeps the local store) and is also synced to Google Drive (below).
- **Local persistence:** SwiftData (local store only).
- **Sync between Mac and iPhone:** Google Drive **appDataFolder** (hidden, app-private storage, scope `https://www.googleapis.com/auth/drive.appdata`), using the same Google sign-in as Calendar. See Section 4b.
- **Calendar:** Google Calendar API v3 (REST). OAuth via Google Sign-In for iOS/macOS SDK or AppAuth, whichever is cleaner. PKCE. Tokens in Keychain.
- **AI:** OpenRouter API (OpenAI-compatible chat completions), used for inbox sorting only. Key entered in Settings, stored in Keychain.
- **Widgets:** WidgetKit (iOS). If App Groups are not available with a Personal Team, keep only the Capture widget (which just deep-links into the app and needs no shared data) and skip the Next-block widget. Note it in DECISIONS.md.
- No third-party UI libraries. Dependencies limited to Google auth (via Swift Package Manager).

### Project layout
```
Cadence/
  project.yml
  Packages/CadenceCore/        # Swift package shared by both apps
    Models/                    # SwiftData models
    Google/                    # OAuth, Calendar client, Drive sync
    AI/                        # OpenRouter client + inbox sorter
    Scoring/                   # pure functions, fully unit-tested
    Store/                     # repositories / queries
  Apps/Cadence-iOS/
  Apps/Cadence-macOS/
  Apps/CadenceWidgets/
  Tests/
```
Shared views where sensible, but each platform gets layouts that feel native to it.

---

## 2. Core concepts (keep the app built around exactly these)

| Concept | Meaning |
|---|---|
| **Area** | A user-defined part of life: name, color, SF Symbol icon, sort order. Each Area maps 1:1 to a Google calendar. Fully customizable (create, rename, recolor, reorder, archive). |
| **Classes** | A special read-only Area linked to my existing college Google calendar. Shown, never edited, never logged, never scored. |
| **Block** | A Google Calendar event in an Area's calendar. Says *when* and *what kind*, not exactly what. |
| **Item** | Something to do, belonging to one Area. Two kinds: **Task** (finite; disappears when done) and **Activity** (reusable; never "done"; accumulates history). |
| **Inbox** | Rough notes I send from my phone or Mac, each turned into an Item by AI. |
| **Log** | What happened in a Block: which items, full/easy/skipped, minutes, optional note. |

### Item details
- `title` (short, clean)
- `kind`: task | activity
- `area`
- `fullVersion` / `easyVersion` (optional short texts, set by me, never auto-generated)
- Task only: optional `dueDate`, `status` (open | done | dropped)
- Activity only: archived flag
- Optional freeform `notes`

---

## 3. Data model (SwiftData)

Every synced model has: `id: UUID`, `updatedAt: Date`, `isDeleted: Bool` (soft delete / tombstone for sync).

- `Area`: name, colorHex, symbolName, sortOrder, googleCalendarId, isClassesCalendar, isArchived, createdAt
- `Item`: kind, title, areaId, fullVersion?, easyVersion?, dueDate?, status, notes?, createdAt, completedAt?
- `InboxNote`: rawText, createdAt, state (pending | sorted | failed), resultingItemId?, sortedAt?
- `BlockLog`: googleEventId, eventStart (instance start, handles recurring events), areaId, plannedMinutes, state (unlogged | full | easy | skipped), loggedMinutes, note?
- `BlockEntry`: blockLogId, itemId?, outcome (full | easy | skipped), minutes
- `UnplannedLog`: areaId, itemId?, date, outcome, minutes, note?
- `Target`: areaId, weeklyMinutes?, weeklySessions?, setAt

Blocks themselves live in Google Calendar; only their logs live locally, keyed by `googleEventId + eventStart`.

---

## 4. Google integration

### 4a. Calendar
- One Google sign-in (Settings / onboarding), scopes: `calendar` and `drive.appdata`.
- **Onboarding:** pick my existing college calendar as "Classes". For each Area I create, either create a new Google calendar named after it (default) or link an existing one.
- Read events for visible date ranges from Classes + all Area calendars. Cache locally for offline viewing. Use incremental sync (`syncToken`) where practical.
- Create / move / resize / delete Blocks from the app → writes to Google. Edits made in Google Calendar directly appear in the app on refresh (on launch, on foreground, pull-to-refresh, and periodically while open).
- Area renames/recolors update the Google calendar name/color where possible.
- On `invalid_grant` or auth failure: calm "Reconnect Google" banner. Never crash, never lose local data.

### 4b. Sync via Google Drive appDataFolder
- Simple, robust, single-user sync. No server.
- Store the app's data as JSON in the appDataFolder (one file per model type, or one file per record if you judge that more robust; document the choice).
- Merge rule: per record, **newest `updatedAt` wins**; tombstones propagate deletions; tombstones older than 90 days are purged.
- Sync on launch, on foreground, ~5 s after local changes (debounced), and via a manual "Sync now" in Settings. Show last sync time in Settings, nothing more prominent.
- Offline: queue and sync later. Local store is always the source of truth for the UI.
- This also acts as a backup: if the iPhone app expires and has to be reinstalled fresh, signing in restores everything.

---

## 5. Inbox & AI sorting

### UX
- iPhone Inbox is a **chat-style composer**: text field at the bottom, send button, keyboard up immediately when opened from the widget. Send → note shows as a subtle "sorting…" row → becomes a compact item card (title, area color dot, kind, due date if any).
- Tapping a card lets me fix area, kind, title, due date, or delete it, in 1–2 taps.
- The raw text is **never shown**. It is kept hidden only for a "Re-sort" action and deleted 30 days after successful sorting.
- Offline: notes queue as `pending` and sort when the network returns. Failed sorts retry with backoff; after 3 failures the note stays with a "Sort manually" option.
- Same Inbox on Mac (sidebar section).

### AI call
- Endpoint `https://openrouter.ai/api/v1/chat/completions`.
- Default model `google/gemini-2.5-flash-lite`, reasoning disabled. Model ID editable in Settings. Use OpenRouter's `models` fallback array with one backup (`openai/gpt-5-nano`).
- **Structured output** via `response_format` JSON schema (strict). `temperature` 0, `max_tokens` ~150.
- Input: short fixed system prompt + my Areas (name + id) + existing Activity titles per area + today's date + the note. Nothing else.
- Output schema:
  ```json
  {
    "kind": "task" | "activity",
    "areaId": "<one of the provided ids>",
    "title": "short clean title, max ~60 chars",
    "matchesExistingActivityId": "<id or null>",
    "dueDate": "YYYY-MM-DD or null",
    "confidence": "high" | "low"
  }
  ```
- If it matches an existing activity, don't create a duplicate; choose sensible behavior and log it in DECISIONS.md.
- Validate output (areaId must exist, etc.). Invalid → retry once → mark failed.
- Low confidence: still file it, with a small unobtrusive marker.
- Settings shows this month's estimated token cost and a soft monthly cap (default $1) after which sorting pauses until next month or until I raise it.
- No other AI features anywhere.

---

## 6. Planning, filling and logging blocks

- **I plan my own day, from nothing.** No smart defaults, no pre-filled blocks, no suggestions, no auto-selected items.
- **Mac planning view (main screen):** day/week calendar on the left showing Classes + Area blocks; backlog on the right grouped by Area (tasks sorted by due date, then oldest first; activities listed separately). Drag an item onto a block to add it. Drag on empty space to create a block (choose Area). Move/resize blocks directly.
- **Filling a block** (both platforms): open a block → that Area's activities as chips on top, open tasks below → tap to add. Zero, one or several items. Zero is fine: the block counts as "did [Area]".
- **Logging:** each block and each item in it gets **Full / Easy / Skipped**. Default minutes: full = item's share of block time, easy = half (editable via a simple stepper). Optional one-line note on block or item.
- **Unplanned:** a "+" to log something done without a block (area, optional item, minutes, outcome).
- Tasks logged Full → done. Easy, Skipped, or unlogged by end of day → stay open in the backlog.
- iPhone can quick-create a block (area, start, duration); full planning is on Mac.

---

## 7. Scores (computed locally, pure functions, unit-tested)

Exactly these, nothing more:

1. **Hours.** Cumulative logged hours per Activity and per Area.
2. **Form (per Area).** Recent activity vs reference, shown as a percentage where **100% = my normal level** (or my target once set).
   - Daily value = logged minutes in that area (easy minutes weighted ×0.75).
   - Recent = exponentially weighted average over ~7 days; Baseline = over ~28 days.
   - Form = Recent / Reference, displayed rounded ("Fitness 84%"), capped at 200%.
   - First 14 days: "Calibrating" instead of a number.
   - All constants in one place; document defaults in DECISIONS.md.
3. **Follow-through (overall).** Last 7 days: logged blocks (full = 1, easy = 0.75, skipped/unlogged = 0) ÷ planned blocks. Classes excluded.
4. **Levels.** Quiet hour milestones per Activity: 10, 25, 50, 100, 250, 500, 1000 h. Small label, e.g. "Spanish · 63 h · Level 4".
5. **Observation → targets.** After 21 days, a one-time calm prompt per Area proposing a weekly target (median of observed weeks). Accept, adjust, or skip. With a target, Form's reference becomes the target. Editable any time in Area settings.

No streaks, points, badges, confetti, or notifications.

---

## 8. Screens

### iPhone (TabView)
1. **Today**: the day's timeline (Classes muted grey, Area blocks in area colors). Tap a block → fill/log sheet. Header: date, follow-through % small and quiet. Swipe or arrows for other days.
2. **Inbox**: chat-style capture (Section 5).
3. **Areas**: list of areas with form %; tap → detail: activities (hours, level), open tasks, recent logs, target.
- **Settings** via a toolbar button: Google account, Areas management, sync status, OpenRouter key + model + cost, JSON export.

### Mac (NavigationSplitView)
Sidebar: **Plan** (default), **Inbox**, **Areas**, **Insights**; standard Settings window.
- **Plan**: Section 6 planning view.
- **Insights**: form per area (thin bars), follow-through over recent weeks (small line), hours per activity, levels. One clean screen.
- Keyboard shortcuts: new note, new block, previous/next day, today, sync.

### Widgets (iOS)
- **Capture** (small + lock screen): opens straight into the Inbox composer, keyboard up.
- **Next block** (only if App Groups work with a Personal Team): current/next block with Full / Easy / Skip buttons via App Intents.

---

## 9. Design direction (important)

- Feels like a first-party Apple app: native controls, system materials (use the current system look of the installed SDK, without overdoing translucency), SF Pro, SF Symbols, Dynamic Type, full dark mode, standard spacing.
- **Restraint.** Generous whitespace, few elements per screen, no decorative gradients, no emoji, no illustrations.
- Color comes only from Area colors: a curated palette of ~10 muted, tasteful colors that work in light and dark mode, used as small dots, thin bars and block fills. Everything else neutral.
- Numbers use `.monospacedDigit()`.
- Subtle, quick animations; light haptics on iPhone when logging. Nothing bouncy or game-like.
- Empty states: one calm line of text.
- Write a short note on the visual approach into DECISIONS.md, then build it. Don't wait for approval.

---

## 10. Non-goals (do not build)

AI suggestions or auto-planning, smart defaults, activity auto-detection, AI summaries, weekly review flows, streaks, social features, notifications/reminders, App Store distribution, Android/web, CloudKit/iCloud.

---

## 11. Phases (do all of them in one run; build + test + commit after each)

1. **Foundation.** XcodeGen project, CadenceCore package, SwiftData models, Areas + Items CRUD on both platforms, navigation shells, test target.
2. **Google.** OAuth, Classes calendar selection, Area ↔ calendar creation/linking, reading events, iPhone Today timeline, Mac day/week view, Drive appDataFolder sync.
3. **Blocks.** Create/edit/move blocks (Mac) and quick-create (iPhone), filling blocks with items, Full/Easy/Skipped logging, unplanned logs, task completion rules.
4. **Inbox + AI.** Chat-style capture, OpenRouter structured-output sorter, offline queue, retries, re-sort, cost tracking and cap.
5. **Scores.** Hours, form, follow-through, levels, target proposals, Insights screen. Thorough unit tests of the scoring math.
6. **Widgets & polish.** Capture widget (+ Next-block widget if possible), keyboard shortcuts, design pass over every screen, JSON export, SETUP.md, README.md, final summary.
