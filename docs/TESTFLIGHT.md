# TestFlight: getting the phone controller app into friends' hands

The goal: friends install the **Aurora Play phone controller** (iOS scheme
`GameLabController`) on their iPhones via TestFlight. The Apple TV board app
(`GameLabTV`) stays on your TV; friends only need the iPhone app.

There are two ways to ship a build:

1. **Automatic (already wired up):** pushing Swift changes to `main` runs the
   "iOS + tvOS → TestFlight" GitHub Actions workflow, which signs and uploads
   both apps. See `ios/SETUP.md` for the one-time GitHub Secrets setup.
2. **Manual from your Mac:** `cd ios && bundle exec fastlane beta` — this doc
   covers that path, plus everything Apple-side you must do once.

> This doc was written without access to macOS or Xcode: the `beta` lane is
> **untested**. Expect the first run to surface a small signing or tooling
> issue; the Troubleshooting section lists the likely ones.

---

## (a) Prerequisites — one-time, on Apple's sites

You need a paid **Apple Developer Program** membership ($99/year). Then:

1. **Register the bundle ID.** Developer Portal → Certificates, IDs &
   Profiles → Identifiers → `+` → App IDs → App. Create
   `com.gamelab.controller` (platform: iOS). If you already use a different
   reverse-domain prefix, change the IDs in `ios/project.yml`
   (`PRODUCT_BUNDLE_IDENTIFIER`), `ios/fastlane/Appfile`, and the `beta` lane
   to match — they must agree everywhere.
2. **Create the App Store Connect record.** App Store Connect → My Apps → `+`
   → New App → iOS, bundle ID `com.gamelab.controller`. Note your **Team ID**
   (top-right of developer.apple.com → Account Membership).
3. **Apple Distribution certificate.** In Xcode: Settings → Accounts → Manage
   Certificates → `+` → Apple Distribution. Then export it from Keychain
   Access as a `.p12` (with a password) — you will need it in (c).
4. **App Store provisioning profile.** Developer Portal → Profiles → `+` →
   **App Store Connect** → your iOS App ID → your Distribution cert →
   name it e.g. `GameLab Controller AppStore`. Download the
   `.mobileprovision` — you will need it in (c).
5. **App Store Connect API key** (so fastlane can upload without your Apple ID
   password). App Store Connect → Users & Access → Integrations → App Store
   Connect API → `+` → name it (e.g. `fastlane-local`) → role **App Manager**.
   Download the `.p8` (one-time download) and note the **Key ID** and
   **Issuer ID**.

## (b) Fastlane setup — one-time, on your Mac

```bash
cd ios
brew install xcodegen          # one-time; regenerates GameLab.xcodeproj
bundle install                 # one-time; installs fastlane from Gemfile
```

The `beta` lane itself runs `xcodegen generate` before building, so you do
not have to remember to regenerate the project.

## (c) Required environment variables

The lane reads **everything secret from the environment** — nothing is
committed. Export these in your shell (or put them in `~/.zshrc`;
never in the repo):

```bash
# App Store Connect API key (from prerequisite 5)
export ASC_KEY_ID="XXXXXXXXXX"          # Key ID
export ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # Issuer ID
export ASC_PRIVATE_KEY="$(cat ~/private_keys/AuthKey_XXXXXXXXXX.p8)"  # .p8 content

# Signing (from prerequisites 3–4)
export IOS_PROVISION_PROFILE_NAME="GameLab Controller AppStore"  # exact profile name
export DEVELOPMENT_TEAM="XXXXXXXXXX"    # your 10-char Team ID (used by xcodebuild)

# Appfile placeholders — you can leave Appfile as-is; these override it:
export APPLE_ID="you@example.com"
export TEAM_ID="$DEVELOPMENT_TEAM"
```

`IOS_PROVISION_PROFILE_NAME` is interpolated into the generated project via
`PROVISIONING_PROFILE_SPECIFIER: "$(IOS_PROVISION_PROFILE_NAME)"` in
`ios/project.yml` and into the lane's export options; the names must match
exactly what you created in the portal.

Optional:

```bash
export BUILD_NUMBER="123"               # default: git commit count, else timestamp
export CHANGELOG="Snake visuals + new rules screen"
export TESTFLIGHT_GROUP="Friends"       # external tester group (default "Friends")
export DISTRIBUTE_EXTERNAL="true"       # also submit to the external group;
                                        # triggers Apple's Beta App Review
```

## (d) The one command

```bash
cd ios && bundle exec fastlane beta
```

What it does, in order:

1. `xcodegen generate` — regenerates `GameLab.xcodeproj` from `project.yml`.
2. `increment_build_number` — sets the build number (App Store Connect rejects
   re-uploading an already-used build number, so this must be unique per
   upload).
3. `build_app` (gym) — builds the `GameLabController` scheme in **Release**
   with `export_method: "app-store"`, which is the export method Apple
   requires for TestFlight uploads. Manual signing uses your Distribution
   cert and the profile named in `IOS_PROVISION_PROFILE_NAME`.
4. `upload_to_testflight` (pilot) — uploads `build/ios/GameLabController.ipa`
   to App Store Connect using the API key. By default it goes to **internal**
   testers only. With `DISTRIBUTE_EXTERNAL=true` it also adds the build to
   your external group and submits it to **Beta App Review** (the lane then
   waits for Apple's build processing instead of skipping it).

Apple takes ~10–60 minutes to process a build before testers can install it.

## (e) External tester group — adding friends by email

Internal testing is limited to App Store Connect users on your team (up to
100). Friends go in an **external** group (up to 10,000 testers):

1. App Store Connect → My Apps → Aurora Play → TestFlight tab → **External
   Testing** sidebar → `+` to add a group → name it `Friends` (or set
   `TESTFLIGHT_GROUP` to whatever you name it).
2. Inside the group: Testers → `+` → **Add new testers** → paste your friends'
   **Apple ID email addresses** → Add.
3. Builds → select the build → Submit for Review → answer the export
   compliance question (the app declares `ITSAppUsesNonExemptEncryption:
   false`, so answer "No" to using exempt encryption) and provide any
   requested beta review info.
4. **Beta App Review:** every build added to an external group must pass
   Apple's Beta App Review before external testers can install it — usually
   under 24 hours for a first review, faster for updates. Internal testers
   are NOT subject to this; they can install as soon as processing finishes.

## (f) Friends: from the QR / landing page to TestFlight

1. Once the build is approved for external testing, open the `Friends` group
   in App Store Connect → enable the **public link** (Share → Enable Public
   Link). Copy the `https://testflight.apple.com/join/XXXXXX` URL.
2. Put that URL behind the **join QR code / landing page** (the web
   workstream's deliverable) so a friend's flow is:
   TV lobby shows QR → phone camera opens landing page → taps
   "Install the controller app" → opens the TestFlight public link.
3. On their iPhone, the friend taps the link → installs the **TestFlight**
   app from the App Store if needed → taps Accept/Install → Aurora Play
   appears. TestFlight auto-updates the app when you ship new builds.
4. The app's `auroraplay://join/<CODE>` deep link (registered in
   `project.yml`) lets the landing page pre-fill the room code after install
   — no manual code entry.

---

## Signing model (what the lane assumes)

- **Manual signing, no match.** There is no `Matchfile`; the repo does not
  use fastlane match. Your Distribution certificate lives in your Mac's
  login keychain, and the App Store provisioning profile is downloaded via
  Xcode (Settings → Accounts → Download Manual Profiles) or placed in
  `~/Library/MobileDevice/Provisioning Profiles/`. The lane passes
  `CODE_SIGN_STYLE=Manual` through the generated project's Release config.
- Debug builds (local development) still use **Automatic** signing with an
  Apple Development identity — unchanged by this lane.
- `development_team` is not set inside the lane; `DEVELOPMENT_TEAM` is read
  from the environment by Xcode at build time.

## project.yml build-configuration notes

- Release uses `CODE_SIGN_IDENTITY: "Apple Distribution"` and the profile
  specifier from `$(IOS_PROVISION_PROFILE_NAME)` — both required for an
  app-store export. No project restructuring was needed.
- `CFBundleShortVersionString` is pinned to `"1.0"`; bump it manually in
  `project.yml` when you want a user-visible version change (the lane only
  bumps the build number).
- `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` requires an `AppIcon`
  asset catalog in `ios/GameLabController` — verify this exists before your
  first upload, since a missing app icon fails App Store validation.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `xcodegen: command not found` | `brew install xcodegen` (step b) |
| "No signing certificate 'Apple Distribution' found" | Create/export the cert in Xcode (prerequisite 3); make sure the login keychain is unlocked |
| "No profile for 'com.gamelab.controller' matching '…'" | Profile name in `IOS_PROVISION_PROFILE_NAME` must match exactly; re-download profiles in Xcode |
| "Invalid build number" / upload rejected | Build number already used on App Store Connect — the lane bumps it, but if you upload the same archive twice it still fails; re-run the lane |
| `invalid_grant` from the API key | Key revoked or wrong Issuer ID — regenerate in App Store Connect |
| pilot hangs on "waiting for processing" | Normal — Apple processing takes 10–60 min; `DISTRIBUTE_EXTERNAL=true` waits for it |
| External testers see "not available" | Build still in Beta App Review or processing — internal testers can install meanwhile |
| Lane fails referencing `GameLab.xcworkspace` | Update the Fastfile — all lanes now use `GameLab.xcodeproj` (fixed 2026-10-02; XcodeGen generates no workspace) |

## Could not verify (no macOS/Xcode on this machine)

- The `beta` lane has **never been run** — syntax, `sh("xcodegen generate")`
  behavior inside fastlane, and the export/upload flow are untested.
- Whether `increment_build_number` works against the XcodeGen-generated
  project (it edits `CURRENT_PROJECT_VERSION` in `project.pbxproj`; the
  generated target sets it to `1`, so it should).
- The AppIcon asset catalog presence under `ios/GameLabController`.
- pilot's `distribute_external` + `groups` behavior for this app record
  (creates the group if missing; standard behavior, not verified here).
