# Cadence — Setup

Do these steps by hand, in order. Anything you skip will show up as "not connected" rather than crashing.

## 1. Tools

1. Make sure Xcode 26 or newer is installed.
2. Install XcodeGen (used to generate the Xcode project): `brew install xcodegen`

## 2. Google Cloud project + OAuth client

3. Go to https://console.cloud.google.com and create a new project named "Cadence".
4. Enable two APIs (APIs & Services → Library):
   - **Google Calendar API**
   - **Google Drive API**
5. Create the OAuth consent screen:
   - User type: **External**.
   - App name "Cadence", your email as support email.
   - Add your own Google account as a **test user** while in "Testing" mode (you can switch to "In production" once it works).
6. Create two OAuth clients (APIs & Services → Credentials → Create credentials → OAuth client ID), both of application type **iOS**:
   - "Cadence iPhone" — Bundle ID `com.theocoronges.cadence`
   - "Cadence Mac" — Bundle ID `com.theocoronges.cadence.mac` (Google uses the iOS client type for native Mac apps too)
   - No redirect URI or secret to configure: iOS clients automatically allow `com.googleusercontent.apps.<id>:/oauth2redirect`, which Cadence uses with PKCE.
7. Copy both **Client IDs**. On the consent screen (Audience), switch publishing status to **In production** — in Testing mode, Google expires refresh tokens after 7 days. The `calendar` scope is classed as sensitive, so on first sign-in Google shows "Google hasn't verified this app": tap **Advanced → Go to Cadence (unsafe)**. That's expected for a personal, unverified app; no review is needed.

## 3. Secrets

8. In the repo root, copy the example file:
   ```
   cp Secrets.example.xcconfig Secrets.xcconfig
   ```
9. Paste the iPhone client ID into `GOOGLE_IOS_CLIENT_ID` and the Mac client ID into `GOOGLE_MAC_CLIENT_ID`.

`Secrets.xcconfig` is git-ignored and never committed.

## 4. Generate and open

10. Run `xcodegen generate` in the repo root (this creates `Cadence.xcodeproj`).
11. Open `Cadence.xcodeproj`.

## 5. Signing (free Personal Team)

12. For the **CadenceiOS** target: Signing & Capabilities → check "Automatically manage signing", select your **Personal Team**.
13. For the **CadenceMac** target, select your Personal Team.
14. Keep the bundle identifiers as-is (`com.theocoronges.cadence` and `com.theocoronges.cadence.mac`). They must match the Google OAuth clients, and a free Personal Team can only register a few App IDs per week, so don't change them. If Xcode says an ID is taken, change the prefix once everywhere (project.yml + the Google clients) and run `xcodegen generate` again.

## 6. Run

15. Build & run the **CadenceiOS** scheme on your iPhone (plug in, select it as the destination).
16. Build & run the **CadenceMac** scheme on your Mac (destination "My Mac").

## 7. First launch

The first time you open either app, a short welcome appears. Every step has **Skip for now**.

17. **Connect Google** and approve the scopes. Use the same Google account on both devices.
18. **On your second device** this is all you do: Cadence restores your Areas, items and logs from Google Drive and says "Welcome back".
19. **On the first device**, set up **Classes**: either paste your university's calendar link (the `.ics` URL, e.g. from Blackboard; tap *Check link* to see how many events it finds) or pick a Google calendar. The link refreshes by itself.
20. Add your first **Areas**. Each one gets its own Google calendar named after it, or you can link a calendar you already have. You can change all of this later (Settings, or an Area's edit screen).
21. Open **Settings** (gear on iPhone, ⌘, on Mac) → **AI Sorting**, paste your **OpenRouter** key and tap Save Key. Notes you send to the Inbox are sorted with it. Without a key, notes simply wait.

## 8. Keeping it running

22. iPhone apps installed with a free account **expire after 7 days**. Reinstall from Xcode weekly. Your data survives (same bundle id keeps the local store) and is also synced to Google Drive's `appDataFolder`, so signing in again restores everything.
23. If Google signs you out, a "Google disconnected. Reconnect" bar appears. Tap Reconnect; no local data is lost.
24. **Update both devices together** after pulling a new version: older builds can't read newer sync files, and Cadence refuses to overwrite a sync file it can't read.

## Notes

- The OpenRouter key is entered at runtime and stored in the Keychain. It is never in the repo.
- If you add or rename files/targets, run `xcodegen generate` again; never hand-edit the `.pbxproj`.
- Debug builds understand `-CadenceDemo YES`, which runs the app on fake data (no Google, no Keychain). It's what the screenshots in `scripts/` use.
