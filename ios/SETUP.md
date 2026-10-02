# GameLab iOS + tvOS — Setup & Deployment Guide

**Goal:** iPhone = controller, Apple TV = game board. Both installed via TestFlight.

---

## How the pipeline works

```
git push → GitHub Actions (macos-15 runner)
              ├─ XcodeGen generates GameLab.xcodeproj
              ├─ Signs with your Apple Distribution cert
              ├─ Archives + exports GameLabController.ipa  (iOS)
              ├─ Archives + exports GameLabTV.ipa          (tvOS)
              └─ Uploads both to TestFlight
                    ├─ Install GameLab on iPhone via TestFlight app
                    └─ Install GameLab TV on Apple TV via TestFlight app
```

---

## Prerequisites

| Requirement | Where to get it |
|---|---|
| Apple Developer Program membership | developer.apple.com ($99/year) |
| Mac with Xcode 16+ | Required to run locally |
| XcodeGen (local only) | `brew install xcodegen` |

---

## Step 1 — Register your apps in Apple Developer Portal

1. Go to **developer.apple.com → Certificates, IDs & Profiles → Identifiers**
2. Click **+** → App IDs → App
3. Create two App IDs:
   - Bundle ID: `com.gamelab.controller` — Platform: iOS
   - Bundle ID: `com.gamelab.tv` — Platform: tvOS
4. **Change the bundle IDs** in `ios/project.yml` and `ios/fastlane/Appfile`
   to match whatever you registered (use your own reverse-domain prefix)

---

## Step 2 — Create App Store Connect records

1. Go to **appstoreconnect.apple.com → My Apps → +**
2. Create two new apps:
   - **GameLab** — iOS, bundle ID `com.gamelab.controller`
   - **GameLab TV** — tvOS, bundle ID `com.gamelab.tv`
3. Note your **Team ID** (shown top-right in developer.apple.com → Account)

---

## Step 3 — Get your Apple Distribution certificate

> Skip if you already have one in Keychain Access.

1. In Xcode: **Settings → Accounts → Manage Certificates → + → Apple Distribution**
2. In Keychain Access: find **Apple Distribution: Your Name (XXXXXXXXXX)**
3. Right-click → Export → save as `dist.p12`, set a password
4. Base64-encode it:
   ```bash
   base64 -i dist.p12 | pbcopy   # copies to clipboard
   ```
5. Save the base64 string and the password — you'll need them in Step 5

---

## Step 4 — Create provisioning profiles

### iOS (App Store distribution)
1. developer.apple.com → Profiles → **+**
2. Type: **App Store Connect** → Continue
3. App ID: your iOS bundle ID → Continue
4. Certificate: your Apple Distribution cert → Continue
5. Name: `GameLab Controller AppStore` → Generate → Download
6. Base64-encode it:
   ```bash
   base64 -i GameLab_Controller_AppStore.mobileprovision | pbcopy
   ```

### tvOS (App Store distribution)
1. Same steps, App ID: your tvOS bundle ID
2. Name: `GameLab TV AppStore` → Generate → Download
3. Base64-encode:
   ```bash
   base64 -i GameLab_TV_AppStore.mobileprovision | pbcopy
   ```

---

## Step 5 — Create App Store Connect API key

This lets GitHub Actions upload without your Apple ID password.

1. appstoreconnect.apple.com → **Users & Access → Integrations → App Store Connect API**
2. Click **+** → Name: `GitHub Actions` → Role: **App Manager**
3. Download the `.p8` file (you can only download once — save it!)
4. Note the **Key ID** and **Issuer ID** shown on that page
5. Read the `.p8` file content (it's text starting with `-----BEGIN PRIVATE KEY-----`)

---

## Step 6 — Add GitHub Secrets

Go to your GitHub repo → **Settings → Secrets and variables → Actions → New repository secret**

Add these 9 secrets:

| Secret name | Value |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Base64 of your `dist.p12` (from Step 3) |
| `P12_PASSWORD` | Password you set when exporting the .p12 |
| `KEYCHAIN_PASSWORD` | Any random string (e.g. `openssl rand -hex 20`) |
| `IOS_PROVISION_PROFILE_BASE64` | Base64 of iOS `.mobileprovision` (from Step 4) |
| `IOS_PROVISION_PROFILE_NAME` | Exact profile name, e.g. `GameLab Controller AppStore` |
| `TVOS_PROVISION_PROFILE_BASE64` | Base64 of tvOS `.mobileprovision` (from Step 4) |
| `TVOS_PROVISION_PROFILE_NAME` | Exact profile name, e.g. `GameLab TV AppStore` |
| `ASC_KEY_ID` | Key ID from Step 5 (e.g. `ABC1234DEF`) |
| `ASC_ISSUER_ID` | Issuer ID from Step 5 (UUID format) |
| `ASC_PRIVATE_KEY` | Full content of the `.p8` file (paste as-is, including `-----BEGIN/END-----`) |
| `DEVELOPMENT_TEAM` | Your 10-character Team ID (e.g. `ABCD123456`) |

---

## Step 7 — Configure your server URL

Edit `ios/Shared/Constants.swift`:
```swift
static let serverURL = URL(string: "https://your-deployed-server.com")!
//                                   ↑ change to your Flask server's public URL
```

For local testing on the same WiFi network:
```swift
static let serverURL = URL(string: "http://192.168.1.X:5000")!
//                                   ↑ your Mac's LAN IP
```

---

## Step 8 — Push to trigger the build

```bash
git push origin main
```

GitHub Actions will:
1. Generate the Xcode project (no `.xcodeproj` committed — it's clean)
2. Sign with your certificate
3. Upload to TestFlight (processing takes ~10 min on Apple's side)

Then on your devices:

**iPhone:** Install **TestFlight** app → open the invite link or use your Apple ID
**Apple TV:** Install **TestFlight** on Apple TV (App Store) → same invite link

---

## Running locally (fastest for development)

```bash
cd ios
brew install xcodegen               # one-time
xcodegen generate                   # creates GameLab.xcodeproj
open GameLab.xcworkspace            # open in Xcode
```

Then in Xcode:
- Select **GameLabController** scheme + your iPhone as destination → ▶ Run
- Select **GameLabTV** scheme + your Apple TV as destination → ▶ Run

For Apple TV wireless debugging:
1. Apple TV: **Settings → Remotes and Devices → Remote App and Devices**
2. Xcode: **Window → Devices and Simulators** → it should appear on the same WiFi

---

## Build stamp — knowing which commit is on your devices

Every build stamps the git commit it came from into the app, so you can
tell at a glance whether your Apple TV / iPhone is really running the
latest code:

- **Apple TV:** the game-selection sidebar shows "Build ced5a5d · Oct 2, 2026" under the connection dot.
- **iPhone:** the join screen shows the same line at the bottom.

How it works: `ios/build-stamp.sh` (run automatically as an XcodeGen
pre-build script phase — see `preBuildScripts` in `ios/project.yml`)
writes the current git short SHA and UTC commit date into
`ios/Shared/Resources/BuildStamp.json`, which XcodeGen bundles into both
apps as a resource. `ios/Shared/BuildStamp.swift` reads it and exposes
`BuildStamp.displayString`; when the file is absent (an older build) it
degrades gracefully to "dev build".

Notes:

- The JSON is generated at build time — don't commit it; it's listed in `.gitignore`.
- If you build from Xcode the phase runs on every build, so the stamp is
  always fresh. To refresh it manually: `cd ios && ./build-stamp.sh`.
- If git is unavailable the script still exits 0 and the stamp reads
  "dev build", so it never breaks a build.

---

## Trigger a manual deploy

Without pushing code, go to:
**GitHub → Actions → "iOS + tvOS → TestFlight" → Run workflow**
Choose `both`, `ios`, or `tvos`.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "No signing certificate found" | Re-export .p12 and re-encode; check Team ID secret |
| "Profile doesn't match bundle ID" | Make sure profile name in secret matches exactly |
| "invalid_grant" on upload | API key may be expired; create a new one in Step 5 |
| Apple TV not appearing in Xcode | Must be on same WiFi; try USB-C cable instead |
| Build fails on SPM resolve | Check XcodeGen version: `brew upgrade xcodegen` |
| Server URL unreachable on device | Use your Mac's LAN IP, not `localhost` |
