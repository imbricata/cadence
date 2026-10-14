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
13. Do the same for **CadenceWidgets** (the widget extension).
14. For the **CadenceMac** target, select your Personal Team.
15. Keep the bundle identifiers as-is (`com.theocoronges.cadence`, `com.theocoronges.cadence.widgets`, `com.theocoronges.cadence.mac`). They must match the Google OAuth clients, and a free Personal Team can only register a few App IDs per week, so don't change them. If Xcode says an ID is taken, change the prefix once everywhere (project.yml + the Google clients) and run `xcodegen generate` again.

## 6. Run

16. Build & run the **CadenceiOS** scheme on your iPhone (plug in, select it as the destination).
17. Build & run the **CadenceMac** scheme on your Mac.

## 7. First launch / on-boarding

18. In the app, open **Settings** → tap **Connect Google Calendar** and approve the scopes.
19. Still in Settings, pick your college calendar as the **Classes calendar**.
20. Open **Areas** → **+** to create your areas. Each new area creates its own Google calendar named after it. Renaming or recoloring an area also updates that calendar. (Linking an *existing* calendar to an area is not built yet.)
21. Open **Settings** → enter your **OpenRouter** API key (from https://openrouter.ai/keys) and optionally set the model + monthly cap.

## 8. Keeping it running

22. iPhone apps installed with a free account **expire after 7 days**. Reinstall from Xcode weekly. Your data survives (same bundle id keeps the local store) and is additionally synced to Google Drive's `appDataFolder`, so re-signing in restores everything.
23. If a device signs itself out, just tap **Reconnect Google** — no local data is lost.

## Notes

- The OpenRouter key is entered at runtime (Settings) and stored in the Keychain. It is never in the repo.
- If you ever re-add or rename files/targets, run `xcodegen generate` again — never hand-edit the `.pbxproj`.