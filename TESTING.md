# Manual test (needs your real accounts)

Everything else is covered by unit tests and demo-mode screenshots. Run this after installing both apps, ten minutes in total.

## Setup
1. Install on iPhone and Mac (see `SETUP.md`). Both on the same Google account.

## Mac first
2. Open the Mac app. The welcome appears. **Connect Google**, approve. Set Classes (paste your `.ics` link and tap *Check link*), add an Area. 
3. In **Plan**, your classes show in grey. Drag in empty space on Wednesday afternoon: a ghost appears and an Area picker opens. Pick the Area with the arrow keys and Return. A block appears.
4. Drag the block to another day, then drag its bottom edge. Press Esc halfway through a drag: nothing changes.
5. Open Google Calendar in a browser: the block is in the Area's calendar at the new time.

## iPhone
6. Open the iPhone app, **Connect Google**. You should see "Welcome back" and your Areas, no setup needed.
7. **Today**: the block you made on the Mac is there. Tap it, add an activity, then set the outcome to **Full**. 
8. Back on the Mac, wait ~10 seconds (or ⌘R): the block shows a check mark, and **Insights** counts the time.

## Checks that matter
9. Add an item to a block but don't log it: the item's task stays open and Insights doesn't change.
10. Set a block to Full for a task, then **Clear log**: the task reopens.
11. Delete a block on the iPhone (long-press): it disappears on the Mac after sync. Tap **Undo** right after deleting: it comes back.
12. Turn on Airplane mode: the offline bar appears and your cached day still shows. Turn it off: it clears by itself.
13. Add your OpenRouter key and send a note in the Inbox: it becomes a card in a few seconds. A low-confidence one has a small question mark.
