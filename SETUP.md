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
6. Create an OAuth client (APIs & Services → Credentials → Create credentials → OAuth client ID):
   - Application type: **Web application**.
   - Name: "Cadence".
   - Authorized redirect URI: exactly `cadence://oauth2redirect`
   - Leave "Client secret" blank — Cadence uses PKCE and does not use a secret.
7. Copy the resulting **Client ID**. On the consent screen, switch publishing status to **In production** (the two scopes used — `calendar` and `drive.appdata` — are non-sensitive, so this needs no Google review).

## 3. Secrets

8. In the repo root, copy the example file:
   ```
   cp Secrets.example.xcconfig Secrets.xcconfig
   ```
9. Paste the Client ID into **both** `GOOGLE_IOS_CLIENT_ID` and `GOOGLE_MAC_CLIENT_ID` in `Secrets.xcconfig`.

`Secrets.xcconfig` is git-ignored and never committed.

## 4. Generate and open

10. Run `xcodegen generate` in the repo root (this creates `Cadence.xcodeproj`).
11. Open `Cadence.xcodeproj`.

## 5. Signing (free Personal Team)

12. For the **CadenceiOS** target: Signing & Capabilities → check "Automatically manage signing", select your **Personal Team**.
13. Do the same for **CadenceWidgets** (the widget extension).
14. For the **CadenceMac** target, select your Personal Team.
15. Change the bundle identifiers if you prefer (defaults: `com.cadence.ios`, `com.cadence.ios.widgets`, `com.cadence.mac`) — but **fix them once** and never change them again, because a free Personal Team can only register a few App IDs per week.

## 6. Run

16. Build & run the **CadenceiOS** scheme on your iPhone (plug in, select it as the destination).
17. Build & run the **CadenceMac** scheme on your Mac.

## 7. First launch / on-boarding

18. In the app, open **Settings** → tap **Connect Google Calendar** and approve the scopes.
19. Still in Settings, pick your college calendar as the **Classes calendar**.
20. Open **Areas**, create your areas (each creates a linked Google calendar named after it) or link existing ones in Settings.
21. Open **Settings** → enter your **OpenRouter** API key (from https://openrouter.ai/keys) and optionally set the model + monthly cap.

## 8. Keeping it running

22. iPhone apps installed with a free account **expire after 7 days**. Reinstall from Xcode weekly. Your data survives (same bundle id keeps the local store) and is additionally synced to Google Drive's `appDataFolder`, so re-signing in restores everything.
23. If a device signs itself out, just tap **Reconnect Google** — no local data is lost.

## Notes

- The OpenRouter key is entered at runtime (Settings) and stored in the Keychain. It is never in the repo.
- If you ever re-add or rename files/targets, run `xcodegen generate` again — never hand-edit the `.pbxproj`.