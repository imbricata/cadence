# Cadence: Quality Overhaul Plan

This plan is for the coding agent. **Read all of it before touching code.**

- `SPEC.md` is still the product definition: concepts, scope and non-goals.
- Where this plan conflicts with `SPEC.md` Section 0 (process, tokens), **this plan wins**.

The owner uses this app **every day** on an iPhone 15 and an M1 Pro Mac. The bar is a first-party Apple app: calm, fast, obvious, and correct. Fewer features done well beats more features done roughly.

---

## 0. Ground rules for the executor

1. **Quality over token savings.** Ignore SPEC Section 0's "keep token usage low", "don't re-read files" and similar rules.
   - Read a file before you edit it.
   - Re-read your work.
   - Look at screenshots of what you built.
2. **Work phase by phase** (Section 3). At the end of every phase:
   - run `xcodegen generate` (if files changed);
   - build **both** apps, with zero errors and **zero new warnings**;
   - run the tests;
   - do the screenshot review (0.4);
   - commit with a clear message. Never leave the tree broken.
3. **Protect the owner's real data.** They already have Areas, Items, logs and an ICS Classes link on their phone, and the data is in Drive.
   - SwiftData changes must be lightweight-migration safe. Only **add** properties with default values, or **add** enum cases. Never rename or remove stored properties, and never change a property's type.
   - Sync snapshot structs must decode older JSON. Use `decodeIfPresent` with defaults for any new field.
   - **Do not change bundle IDs, OAuth scopes or the Drive file names.**
4. **Native first.** Use the native control before building a custom one: `List`, `Form`, `.inspector`, `.popover`, `.searchable`, `ContentUnavailableView`, Swift Charts, `.sensoryFeedback`, `Layout`.
   - No third-party UI packages.
   - Check the installed SDK (Xcode 27) and use only non-deprecated APIs.
5. **Commands that work:**
   ```
   xcodegen generate
   xcodebuild -project Cadence.xcodeproj -scheme CadenceMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build | xcbeautify --quiet
   xcodebuild -project Cadence.xcodeproj -scheme CadenceiOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build | xcbeautify --quiet
   xcodebuild -project Cadence.xcodeproj -scheme CadenceCoreTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test | xcbeautify --quiet
   ```
6. Log every judgment call in `DECISIONS.md`, one line each, under a new heading `## Overhaul`.

### 0.4 Visual verification loop (mandatory)

The previous agent never saw the UI. That is why it shipped a list instead of a timeline, debug strings, and a grid where every click opens a sheet. Fix the process first.

- **Demo mode (DEBUG builds only).** Launch argument `-CadenceDemo YES` does three things:
  - uses `AppStore.inMemory()` seeded with realistic fixtures: 5 Areas plus Classes, about 12 tasks with some due or overdue, about 8 activities, 3 weeks of block logs and unplanned logs, 3 inbox notes in different states (one of them low-confidence);
  - uses a fake event source producing classes plus Area blocks for -21…+14 days, including one all-day event, one zero-length deadline, and two overlapping blocks;
  - skips Google auth, which counts as connected.

  To make this possible, put calendar fetching behind a protocol (`EventSource`, Section 3, Phase 2). Fixture code lives in `Apps/Shared/Demo/` and is compiled only under `#if DEBUG`.
- **iOS screenshots:**
  1. Pick an iPhone simulator (`xcrun simctl list devices available`).
  2. Build for it and install with `simctl install`.
  3. Launch with `simctl launch <udid> com.theocoronges.cadence -CadenceDemo YES`.
  4. Capture with `xcrun simctl io <udid> screenshot /tmp/shots/<name>.png`.
  5. Repeat in dark mode (`simctl ui <udid> appearance dark`) and at a large Dynamic Type size (`simctl ui <udid> content_size extra-extra-large`).
  6. Add a DEBUG-only launch argument `-CadenceTab today|inbox|areas` (and similar for sheets you need to inspect) so each screen can be captured without tapping.
- **Mac screenshots:**
  1. Launch the built `.app` with `-CadenceDemo YES -CadenceSection plan|inbox|insights|area`.
  2. Capture the window with `screencapture -o -l <windowID> /tmp/shots/mac-<name>.png`. Get the window ID with a small `swift -e` script using `CGWindowListCopyWindowInfo`.
  3. If the capture comes back blank, Terminal needs Screen Recording permission. Ask the owner to grant it once, and use iOS-only review until then.
- **Open every screenshot and critique it** against the checklist in Section 2.6. Fix what fails before committing the phase.

---

## 1. Diagnosis: what is wrong today

### 1A. Correctness bugs (the data and scores are wrong). Fix these first.

1. **Filling a block logs it as done.**
   - `BlockFillLogView` defaults `outcome = .full`. `save()` writes that state, and runs `applyOutcomeToTask(.full)` on every added item.
   - So planning a future block marks the block Full and **completes its tasks immediately**.
   - Opening the sheet also creates a `BlockLog`, even if you tap Cancel.
2. **Scores count plans as work.**
   - `computeInsights` turns every `BlockEntry` into minutes, whatever the block's state.
   - Mac drag-to-fill creates Full entries. Planned items inflate hours, form and levels.
3. **Skipped counts as time worked.** `easyWeightedMinutes(.skipped)` returns the full minutes, and a test (`testEasyWeightedMinutes`) locks this bug in.
4. **The form math is wrong.** The EW average runs only over days that *have* data. Zero days are never included, so one 60-minute session a week reads as "60 min/day".
5. **The follow-through day chart uses `max` instead of a sum**, and it depends on the broken event cache (item 6).
6. **The event cache gets clobbered.**
   - `GoogleService.refreshEvents` *replaces* `cachedEvents` with whatever window was just fetched.
   - Different call sites fetch different windows: today+14 on foreground, date±7 on pull-to-refresh, week-7…+14 in Plan, -7…+30 after sign-in.
   - The result: past days vanish, other days appear empty, and follow-through loses planned blocks.
   - Calendar `listEvents` also ignores `nextPageToken`, so busy windows get silently truncated at 250 events.
7. **Sync gaps:**
   - nothing syncs about 5 s after local changes (the spec requires it);
   - there is no periodic refresh while the app is open;
   - `lastSyncAt` is not persisted;
   - sign-in runs `ensureCalendar` *before* syncing, so the second device can create **duplicate Google calendars**;
   - `refreshEvents` resets `needsReconnect = false` even when individual calendars failed auth;
   - concurrent syncs are not serialized.
8. **The ICS parser is minimal.** It has no RRULE/EXDATE/RECURRENCE-ID/DURATION support, ignores DTEND's own TZID, and detects all-day events fragilely. Zero-length deadlines (Blackboard due dates) get drawn as 15-minute blocks.
9. **No low-confidence marker.** The sorter returns `confidence`, but it is never stored or shown.
10. **Easy minutes aren't halved by default**, even though the spec and DECISIONS say they should be.

### 1B. Missing basics (spec or ordinary usability)

- **Blocks:** you can't delete one, rename it, or change its Area.
- **Items:** you can't delete an item or move it to another Area. Tasks can't be marked dropped.
- **Areas:** you can't archive or delete an Area, link an *existing* Google calendar to one (the spec requires this), or change the Classes calendar once it's set (the picker disappears).
- **Area detail:** "recent logs" from the spec is missing.
- **No reconnect banner** in the main UI; it only appears in Settings.
- **No onboarding.** The owner literally "couldn't figure out how to connect calendar" on the Mac.
- **Mac Plan:**
  - it is week-only, and the "Previous/Next Day" shortcuts move by a week;
  - every click on empty space opens New Block, because a `DragGesture(minimumDistance: 0)` sits on the whole column;
  - there is no drag-to-create;
  - all-day events render as 24-hour blocks;
  - there is no now-line, and the grid doesn't scroll to working hours;
  - move and resize show no live preview, and moves aren't snapped;
  - the resize handle is 3 pt;
  - lane layout narrows *every* event in a day if any two overlap;
  - blocks have no context menu, no Delete key, and no hover or selection states.
- **Backlog:** no add, no search, no complete, no edit. Items are just text.
- **iPhone Today:** it is a plain `List`, not the timeline the spec asks for. Five toolbar buttons are crammed together, there's no week strip or swipe between days, and no haptics.
- **Inbox:**
  - the note order is reversed while the composer sits at the bottom, so it doesn't feel like a chat;
  - sending on Mac needs ⌘↩;
  - there's no day grouping and no low-confidence marker;
  - editing an item takes several steps.
- **Settings:**
  - one long dump of sections;
  - debug text shown to the user ("Events loaded 37", "Loaded 3 event(s), but none on this day", raw error strings);
  - the version number is hardcoded.
- **Docs:** the README still mentions the widget, which has been removed.

### 1C. Visual and design-system problems

- The UI uses ad-hoc `Color.secondary.opacity(0.06)` "cards" everywhere instead of native grouped containers.
- There is no AccentColor, so system blue clashes with the teal brand mark (#5C9B96).
- The Area palette is static hex with no dark-mode variants. Fills don't adapt and text on fills isn't contrast-checked.
- Type is inconsistent (`caption2` everywhere in the grid). There is no spacing scale.

### 1D. Architecture problems

- `computeInsights` (which fetches everything) runs inside view `body`s on every render, in Today, Areas, Area detail and Insights.
- Mac menu commands are wired through `NotificationCenter` instead of `FocusedValues`.
- Every view does `@Query` for everything and filters `isDeleted` by hand.

---

## 2. Target experience

### 2.1 Principles

- **One obvious primary action per screen.** Plan: drag to make a block. Today: tap a block to log it. Inbox: type.
- **Planning and logging are different acts.**
  - Planning (choosing items for a block) **never** changes scores or completes tasks.
  - Logging (Full / Easy / Skipped) is explicit.
- **Autosave.** Edits apply immediately, with a few exceptions:
  - "Done" just dismisses;
  - destructive actions offer Undo (a toast or `UndoManager`) rather than a confirmation, except when a block or Area that has logs is deleted.
- **Calm states.**
  - Empty states are one line.
  - Errors are one human sentence plus one action ("Google disconnected. Reconnect").
  - Diagnostics live behind Settings › Advanced.
- **Speed.** Optimistic UI for every Google write (update locally, write in the background, revert and show a toast on failure). No spinners for routine actions.

### 2.2 Design system (`Apps/Shared/Design/`)

**`Theme.swift`**
- Spacing scale: 4, 8, 12, 16, 24, 32.
- Corner radii: block 6, chip = capsule, card 12 (rare).
- Animation: `.snappy(duration: 0.2)`, nothing bouncy.
- Hour height: 52 pt on Mac, 56 pt on iOS.

**`AreaColor`** (the palette, upgraded):
- Each palette entry gets a light and a dark variant (dark is slightly lighter and less saturated).
- It exposes `base`, `fill` (about 16% opacity in light mode, 26% in dark), `stroke`, and `onFill` text colour, which must stay legible at body size on the fill in both modes.
- Keep the 10 hex keys stored in `Area.colorHex`, so existing data still maps.
- Unknown hex values fall back to a computed variant.

**AccentColor**
- Add an `AccentColor` colorset to both asset catalogs: brand teal (light #4F8C87, dark #6FB3AD).
- Classes are always neutral grey, never accent.

**Components** (small and reusable):

| Component | What it is |
|---|---|
| `AreaDot` | Coloured dot for an Area |
| `AreaChip` | Toggle capsule with dot and title |
| `ChipFlow` | A `Layout` that wraps chips. Replaces the equal-width `LazyVGrid` |
| `OutcomePicker` | Full / Easy / Skipped as a 3-segment control with symbols `checkmark`, `circle.lefthalf.filled`, `xmark`, plus a "none" state |
| `MinutesField` | Stepper showing "45 min" in monospaced digits, step 5; on Mac, click to type |
| `StatusBanner` | Reconnect / offline banner |
| `UndoToast` | Toast with an Undo action |
| `EmptyLine` | The one-line empty state |
| `DurationText` | Formats as "1 h 30 min" |
| `PercentText` | Monospaced percentage |

**Rules:**
- Numbers always use `.monospacedDigit()`.
- Never show raw error strings in the UI.
- Respect the 12/24-hour locale (use `Date.FormatStyle` and no hardcoded `"ha"`). Cache formatters.
- Haptics on iOS only:
  - `.sensoryFeedback(.selection)` on chip and outcome taps;
  - `.success` when a block gets its first log.

### 2.3 Mac

**Window structure.** `NavigationSplitView` with a sidebar and detail.

- **Sidebar:**
  - Top items: **Plan** (default), **Inbox** (badge = pending, failed or unseen notes), **Insights**.
  - An **Areas** section listing each Area (symbol tinted in the area colour, name, trailing form % or nothing). This works like Reminders' lists. Selecting an Area shows its detail in the content pane.
  - Areas can be reordered by drag.
  - Each Area has a context menu: Edit, Archive, Delete.
  - A "+ New Area" button sits at the sidebar bottom.
  - Classes are **not** in the sidebar; they live in Settings.
  - Remove the standalone "Areas" page.
- **Plan toolbar:**
  - leading: `‹  Today  ›` and a title ("October 2026" in week mode, "Tuesday, 20 October" in day mode);
  - centre or trailing: a `Day | Week` segmented picker;
  - trailing: "+" (New Block) and a backlog toggle (`sidebar.right`).
  - **Remove the Sync button.** Sync is automatic; "Refresh" lives in the menu.
- **Backlog** = `.inspector`, toggleable with ⌥⌘I. Its open/closed state persists.

**Calendar canvas.** Rewrite `WeekGrid.swift` into `Apps/Cadence-macOS/Calendar/` with these files:
- `CalendarCanvas.swift`: day and week
- `DayColumnView.swift`
- `EventBlockView.swift`
- `AllDayStrip.swift`
- `TimeGutter.swift`
- `CanvasInteraction.swift`: drag state machine

Put the event layout math in `CadenceCore/Calendar/EventLayout.swift` (pure and unit-tested), so iOS uses it too.

*Header and layout*
- **Header:** each column shows the weekday (secondary) and the date. Today's date sits in an accent-filled circle, like Calendar.app.
- **All-day strip** above the scroll area:
  - holds all-day events and zero-length events (deadlines) as small capsules;
  - is hidden when empty;
  - collapses to "+3" beyond 2 rows.
- **Grid:**
  - hour lines at about 8% primary, half-hour lines at about 4%;
  - weekend columns get a barely-there tint;
  - hours *outside* 07:00–23:00 get a very faint shade.
- **On appear, and on "Today":** scroll to one hour before now (or 08:00 when viewing another week).
- **Now line:** accent colour, 1 pt, with a dot at the gutter, only in today's column. Driven by `TimelineView(.everyMinute)`.
- **Overlap layout:** cluster-based. Only events that actually overlap share width, with a 2 pt gap between them.

*Blocks*
- **Area block:**
  - `AreaColor.fill` background with a 3 pt leading bar in `base`;
  - title in `.callout.weight(.semibold)`, then the time range in `.caption` secondary;
  - if the height allows, up to 3 planned item titles in `.caption` (this is the key planning feedback);
  - a small top-trailing glyph for the log state: Full ✓, Easy ◐, Skipped ✕.
  - Blocks that have ended but are unlogged get a dashed stroke.
- **Classes block:** neutral fill with secondary text. Click shows a small read-only popover (title and time). It can't be dragged, logged or dropped onto.

*Interactions*
- **Hover:** subtle brighten, pointing-hand cursor. **Selected:** 1.5 pt stroke in `base`.
- **Create:**
  - drag in empty space draws a live ghost, snapped to 15 minutes;
  - a double-click creates a 60-minute ghost;
  - on release, a **popover anchored to the ghost** asks for the Area: a filterable list of Areas with dots, type to filter, ↩ confirms, Esc cancels;
  - a single click on empty space only clears the selection.
- **Move:**
  - drag a block for a live preview, snapped to 15 minutes;
  - in week view, horizontal movement changes the day;
  - Esc cancels mid-drag;
  - the change commits on release (optimistically).
- **Resize:**
  - a 6 pt hot zone on the bottom edge, with a vertical-resize cursor (`.pointerStyle(.frameResize(position: .bottom))` if available, else NSCursor);
  - live preview, minimum 15 minutes;
  - the top edge works the same way.
- **Open:** double-click or ↩ on a selected block opens the **Block popover** (Section 2.5) anchored to the block.
- **Context menu:** Open · Log ▸ (Full / Easy / Skipped / Clear) · Change Area ▸ (uses Calendar `events.move` to the target Area's calendar and updates the local `BlockLog.areaId`) · Delete.
- **Delete key** on a selected block deletes it and shows an Undo toast. If the block has a log, confirm first.
- **Drop a backlog item onto a block:**
  - the block highlights while targeted (`isTargeted`);
  - the item is added as a **planned** entry and nothing is logged;
  - dropping onto empty grid space creates a block in that item's Area at that time, with the item planned in it.

**Backlog inspector** (rewrite `BacklogView`)
- `.searchable`-style filter field at the top.
- Areas appear as collapsible `DisclosureGroup`s, with expansion persisted. Each header shows the dot, name and a count.
- **Tasks** sort by due date, then oldest. Each row has:
  - a completion circle (click marks done, with an Undo toast);
  - the title;
  - the due date in secondary, or "Overdue" in secondary orange;
  - Areas with nothing open show a muted "No open tasks" line.
- **Activities** sit under a small "Activities" caption. Rows show the title, plus "12 h · Level 1" in secondary.
- Each Area group ends with an inline **"Add task…"** field. ↩ adds the task and keeps focus; ⌘↩ adds it as an activity.
- **Row hover** reveals a "…" menu: Edit (popover), Move to Area ▸, Delete. Double-click opens Edit.
- **Drag preview:** a pill with the dot and title.

**Quick note (⌘N).** A small sheet over whatever screen is open: one text field, ↩ sends, Esc closes. It doesn't navigate away.

**Commands.** Use `FocusedValues` / `focusedSceneValue` and delete the NotificationCenter bus.

| Shortcut | Action |
|---|---|
| ⌘N | New Note |
| ⇧⌘N | New Block (next free 15-minute slot on the visible day) |
| ⌘← / ⌘→ | Previous / next day or week, depending on mode |
| ⌘T | Today |
| ⌘1 / ⌘2 | Day / Week |
| ⌘R | Refresh |
| ⌥⌘I | Toggle Backlog |
| Delete | Delete selected block |
| ↩ | Open selected block |

Drop ⌘S (it is non-standard).

**Settings** (the `Settings` scene) becomes a `TabView` with fixed widths of about 520 pt:
- **General:**
  - Google account: the connected email, read from the primary calendar's id in `calendarList` (no new scopes); Disconnect / Reconnect.
  - Classes source: shows the current one, with "Change…" (Google calendar picker or ICS link).
  - Sync: "Last synced 2 min ago" and "Sync Now".
- **AI Sorting:**
  - key field with a Save button and status ("Key saved");
  - model;
  - "This month $0.012 of $1.00" with a cap stepper.
- **Data:** Export JSON.
- **Advanced:** a diagnostics disclosure (events loaded, last errors, Drive file list).

**Window.** Minimum 900×600, default 1200×760. Remember the frame (`.defaultSize` plus restoration).

### 2.4 iPhone

**Tabs:** Today, Inbox, Areas.
- Settings is a **sheet** opened by a gear in the leading toolbar of *every* tab (or of Today and Areas at minimum).
- Set an Inbox tab badge for failed notes.

**Today, rebuilt as a real timeline.**
- **Title:**
  - large title "Today", or e.g. "Tue 21 Oct";
  - below it, a **week strip**: 7 day circles, today accent-outlined, the selected day filled. Tap to jump; swipe the strip to change weeks.
  - A quiet trailing caption: "Follow-through 82%" in secondary, monospaced.
- **Body:**
  - an all-day/deadline strip, then a vertical timeline using the shared `EventLayout`: gutter, Classes in grey, Area blocks in area colours, now line;
  - on open, auto-scroll to now (or the first event);
  - swipe horizontally on the timeline to change days (paged, keeping a small window of neighbouring days loaded).
- **Toolbar:** gear (leading); a "+" menu (trailing) with New Block and Log Time. Show "Today" only when you're not on today. Remove the arrow buttons.
- **Interactions:**
  - **tap a block** to open the Block sheet (`.presentationDetents([.medium, .large])`);
  - **long-press a block** for a context menu: Log Full / Easy / Skipped, Change Area, Delete;
  - **tap empty time** for Quick Create, prefilled with the tapped time (15-minute snap).
- **Quick Create sheet** (medium detent):
  - Area chips in a horizontal scroll, Area colours, with the last-used Area preselected;
  - a start-time picker;
  - duration chips: 30, 45, 60, 90, 120;
  - a "Create" button.
- **Empty and disconnected states:**
  - empty day: one line, "Nothing planned. Tap the timeline to add a block.";
  - disconnected: a `StatusBanner` at the top, and the cached timeline still shows underneath.
- **Pull to refresh** still works.

**Areas tab:**
- **List:**
  - an Areas section: symbol tinted in the area colour, name, trailing form %;
  - a Classes row at the bottom in secondary, which opens Classes settings;
  - Edit mode supports reorder and swipe-to-archive.
- **Area detail:**
  - header: form % large, in monospaced digits, with a thin bar that has a 100% tick; hours total; target;
  - sections: Activities (hours · level) · Open Tasks (tap the circle to complete) · **Recent** (the last 10 logs: date, block or unplanned, outcome glyph, minutes) · Done (collapsed) · Target.
  - "+" adds an item (Quick add: title, kind segmented, done).

### 2.5 Shared: Block sheet / popover (rewrite `BlockFillLogView` as `BlockDetailView`)

Use one view for both platforms: a popover on Mac, a sheet on iOS.

- **Header:**
  - Area dot and name; the date and time range; the duration;
  - an optional block title, editable inline, which writes the event `summary` (the default summary is the Area name).
- **"In this block"** (planning):
  - planned items as rows, each with remove (×);
  - below them, **Add**: the Area's activities as `ChipFlow` chips, then open tasks as rows with a "+" button;
  - adding or removing is saved **immediately** as `planned` entries;
  - there is no Save button.
- **"How it went"** (logging):
  - a block-level `OutcomePicker` that starts in the **none** state for unlogged blocks;
  - choosing an outcome sets each planned item's outcome to match. Each item can be overridden with a compact per-row picker;
  - default minutes: Full = equal share of the block, Easy = half the share. Use `MinutesField`;
  - if an item has `fullVersion` or `easyVersion` text, show it under the item when that outcome is selected (these spec fields are currently unused anywhere);
  - a one-line note;
  - a "Clear log" text button returns the block to unlogged;
  - before the block starts, this section is visually de-emphasized (secondary header, "Log when you're done"), but it still works.
- **Task completion** happens only when an entry is *logged* Full. Clearing the log or changing the outcome reopens the task.
- **Toolbar:** Done. On Mac, Esc closes the popover.

### 2.6 Inbox (both platforms)

- **Chat order:** oldest at the top, newest at the bottom, using `.defaultScrollAnchor(.bottom)`. Day headers ("Today", "Yesterday", "Mon 13 Oct").
- **Card:** the Area dot, the title, then "Task · Due 24 Oct" or "Activity" in secondary.
  - A low-confidence note gets a small `questionmark.circle` in tertiary, with an accessibility label.
  - Sorting shows a quiet "Sorting…" row with a small `ProgressView`.
  - A failed note shows "Couldn't sort" and a "Sort" button.
- **Tap a card** to open a compact editor. At the top is a row of Area chips, so fixing the Area is one tap. Below: a Task/Activity segmented control, title, due date toggle, and Delete.
  - iOS: swipe to delete.
  - Both: a context menu with Edit · Re-sort · Delete.
- **Composer:**
  - iOS: a rounded field and an accent send button;
  - Mac: ↩ sends and ⇧↩ adds a newline (`onKeyPress`); the column is max 640 pt wide and centred.
  - If there's no OpenRouter key: notes are still accepted (they queue), and one quiet line above the composer says "Add an OpenRouter key in Settings to sort notes", with a button.

### 2.7 Insights (Mac)

One screen, max width 760, using **Swift Charts**:
1. **Follow-through:** the 7-day % as a large monospaced number, plus a small line chart of the last 8 weeks (the spec asks for "over recent weeks").
2. **Form:** one row per Area, made of name, a thin bar with a 100% tick, and a % or "Calibrating".
3. **This week vs target:** per Area, minutes logged against the target (only Areas that have a target).
4. **Hours by activity:** grouped by Area, showing "Spanish · 63 h · Level 4".

Use native `GroupBox` or `Form(.grouped)` sections, not custom opacity cards.

### 2.8 Onboarding (both platforms)

Show it when not connected, or when connected with no Areas. On Mac it's a sheet over the main window; on iOS a full-screen cover. Every step has "Skip for now".

1. **Welcome:** one sentence ("Plan your days around the areas of your life.") and **Connect Google**, with a line explaining it's used for Calendar plus private sync storage.
2. **After connecting:** run **Drive sync first**. If Areas arrive (a second device), jump to done with "Welcome back. Your data is restored."
3. **Classes:** choose a Google calendar from a list, *or* paste an ICS link (validate it by fetching and show "Found 42 events").
4. **First areas:** type a name, pick a colour, add more. Each one creates a Google calendar, or offers "Link existing calendar…".

Afterwards everything stays editable in Settings and Area editors. The `ConnectGooglePlaceholder` remains as the fallback empty state.

### 2.9 Review checklist (use on every screenshot)

- Is there one clear focal point? Is anything decorative, redundant or debug-like?
- Spacing comes from the scale. Edges align. Nothing is cramped at Large Dynamic Type (iOS).
- Colour comes only from Area colours and the accent, and text on fills is legible in **light and dark**.
- Numbers are monospaced. Times follow the locale.
- Empty, loading and error states are calm: one line.
- Every interactive element has a hover/pressed state (Mac) and an accessibility label.

---

## 3. Phases

### Phase 1: Core correctness (tests first)

1. Add `case planned` to `LogOutcome` (weight 0). In the UI it means "in the block, not logged". This is migration-safe.
2. Planning/logging rules, in `BlockMutations.swift`:
   - `planItem(_:in:)` and `unplanItem` create or delete `planned` entries. Create the `BlockLog` lazily, here.
   - `logBlock(state:)` sets the block state and maps planned entries to the same outcome, with default minutes per Section 2.5. It **then** applies task completion.
   - `clearBlockLog` sets the state to unlogged and entries back to `planned`, and reopens tasks that were completed by this block.
   - `addItemToBlock` (drag) → `planItem`.
   - Never create a log just because a view opened.
3. Scoring inputs, in `InsightQueries.swift`:
   - only count entries whose outcome is full or easy **and** whose block state isn't `.unlogged`;
   - unplanned logs count by their own outcome;
   - skipped is always 0 minutes.
   - Fix `easyWeightedMinutes(.skipped) = 0` and update the test.
4. Form:
   - build a **dense** daily series (zeros included) from the first observation day to today;
   - Recent = EW over the dense series with a 7-day half-life; Baseline = 28-day half-life;
   - keep the `ScoringConfig` constants, calibration and cap.
5. Follow-through:
   - planned = non-Classes, non-all-day Area-calendar events with start in [today−6, now], plus logged blocks in the window;
   - the per-day chart **sums** weights;
   - add `weeklyFollowThrough(weeks: 8)` for the Insights line.
6. `InboxNote.isLowConfidence: Bool = false`: stored, synced (`decodeIfPresent`), set from the sorter result.
7. Tests, using the in-memory `AppStore`:
   - planned entries don't count;
   - tasks complete only on a logged Full, and clearing reopens them;
   - skipped = 0;
   - sparse days lower form correctly;
   - target reference;
   - follow-through sums;
   - `SyncEngine.merge` (newest wins, tombstones, purge);
   - old JSON without new fields still decodes.

**Done when:** all tests pass, and a fresh read of `BlockDetailView` shows that it can't log anything by accident.

### Phase 2: Data-layer reliability

1. **`EventSource` protocol** with `GoogleEventSource`, `ICSEventSource` and `DemoEventSource` (DEBUG).
2. **`EventStore`** (`@Observable`, in Core), which replaces `cachedEvents`:
   - events are stored per calendar id, with a set of loaded date ranges per calendar;
   - `ensureLoaded(range:)` fetches only the missing ranges;
   - `refresh(range:)` replaces events for *that calendar and range only*;
   - persist to disk; prune events more than 60 days old;
   - every view asks for its visible range, with a ±7-day pad. Delete the ad-hoc windows in RootView, PlanView and TodayView;
   - handle `nextPageToken` (set `maxResults=2500`);
   - optimistic `create/move/resize/delete/changeArea/rename` with rollback and an error toast.
3. **`SyncScheduler`:**
   - triggers: launch, foreground, sign-in (**sync before `ensureCalendar`**), 5 s debounced after any `store.save()`, Sync Now, and every 5 minutes while active;
   - serialized, so only one sync at a time;
   - `lastSyncAt` persisted.
   - Event refresh runs on foreground and every 5 minutes as well.
4. **Duplicate-calendar guard:**
   - when Cadence creates a calendar, set its description to `Cadence area <uuid>`;
   - before creating one, list calendars and link any calendar whose description matches.
   - Also give a one-time **Area ↔ calendar repair** in Settings › Advanced.
5. **`ConnectionState` enum** (`connected`, `needsReconnect`, `offline`, `disconnected`):
   - only `invalid_grant` or a 401 after a refresh attempt means `needsReconnect`;
   - network failures mean `offline`;
   - drive `StatusBanner` from it.
6. **ICS:**
   - RRULE (DAILY/WEEKLY with BYDAY, INTERVAL, UNTIL, COUNT), EXDATE, RECURRENCE-ID overrides, DURATION, a per-property TZID, `VALUE=DATE`;
   - DTSTART == DTEND means a deadline (shown in the all-day strip);
   - expand only within the requested range;
   - unit tests with a fixture modelled on a Blackboard feed;
   - add a computed `Area.isICSFeed`. Keep the URL stored in `googleCalendarId` (no schema change).
7. **`InsightsModel`** (`@Observable`): recomputes with a 300 ms debounce when the store saves or events change. Views read `insights.snapshot`. Remove every `computeInsights` call from view bodies.

**Done when:** in demo mode, flipping between days and weeks never shows a flash of empty days; tests pass.

### Phase 3: Design system and shell

- Build Section 2.2: Theme, AreaColor with dark variants, AccentColor assets, the components, and the formatters.
- Mac shell: the sidebar with its Areas section, the inspector backlog, FocusedValues commands, and the tabbed Settings.
- iOS shell: the Settings sheet from the gear, tab badges, and `StatusBanner` placement.
- Version comes from the bundle (`MARKETING_VERSION: 1.0` in `project.yml`).
- Remove all debug strings from the main UI; move them to Advanced.

### Phase 4: Mac Plan (the most important screen)

- Build the full spec in Section 2.3: canvas, interactions, popover, backlog and quick note.
- Unit-test `EventLayout` (clusters, lanes, all-day/deadline split, snapping math).
- **Screenshot review** of day and week views, light and dark, with overlaps, all-day items, a deadline, a selected block, the create popover and the backlog open.

### Phase 5: iPhone Today and Quick Create

- Section 2.4 (timeline, week strip, paging, quick create), reusing `EventLayout`.
- Screenshots: today with the now-line, an empty day, the disconnected banner, dark mode, and XXL type.

### Phase 6: Block detail, Inbox, Areas, Insights

- `BlockDetailView` (Section 2.5), Inbox (2.6), Areas and Area detail with Recent logs (2.4), Insights (2.7).
- Item editor: Area picker (move), status Open/Done/Dropped, Delete.
- Area editor: calendar (Create new / Link existing…), Archive, Delete. Delete asks whether to also delete the Google calendar; the default is to keep it.
- Expand the symbol set to about 30 tasteful SF Symbols in a grid.

### Phase 7: Onboarding, final QA and docs

- Onboarding (Section 2.8).
- Accessibility labels on blocks, e.g. "Spanish, 9 to 10 AM, logged Full", plus chips and outcome controls.
- A full screenshot pass of every screen in both modes. Fix anything that fails 2.9.
- Clean up warnings; make sure no `print` calls are left.
- Update `README.md` (remove the widget, describe the new structure), `SETUP.md` (Mac connect flow, the ICS option) and `DECISIONS.md`.
- Write a **manual test script** for the owner in `TESTING.md`. Keep it short and only cover what needs real accounts:
  - sign in on the Mac;
  - check that the phone's data appears;
  - create a block on the Mac and see it on the phone;
  - log on the phone and see the Mac's Insights update;
  - confirm the ICS classes appear.
- Commit, and push with the owner's git push skill.

---

## 4. Decisions already made (the owner can override)

- Mac Areas move into the sidebar (like Reminders' lists), and the separate Areas page goes away.
- The Mac backlog becomes a toggleable inspector, and blocks open as popovers, not sheets.
- Planning autosaves, logging is explicit, and the outcome starts as "none".
- Sync and refresh are automatic, and the Sync button leaves the toolbar.
- ⌘S becomes ⌘R (Refresh).
- iPhone Today becomes a real timeline with a week strip, replacing the list.
- Onboarding goes on both platforms, and Drive restore comes first on the second device.

## 5. Out of scope (do not add)

Everything in SPEC Section 10, plus: widgets (the owner removed them), notifications, streaks, AI anywhere except inbox sorting, and suggestions or auto-planning.
