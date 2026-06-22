# App Store Release CI

GitHub Actions builds, signs, and submits **GitPhotos** to the App Store.

- **Workflow:** [`.github/workflows/release.yml`](../.github/workflows/release.yml)
- **Lanes:** [`fastlane/Fastfile`](../fastlane/Fastfile)
- **Triggers:**
  - Push a tag matching `v*` (e.g. `git tag v1.0.0 && git push origin v1.0.0`) → runs the `release` lane.
  - Manual **Run workflow** in the Actions tab → pick `release` (submit for review) or `beta` (TestFlight only).

The `release` lane builds a signed `app-store` IPA, uploads it, and **submits it for review**. App name, description, keywords, and screenshots are **not** in this repo — manage them in App Store Connect. The first version must have its metadata + at least one screenshot filled in there before an automated submission will pass.

## One-time setup: GitHub Secrets

Add these under **Settings → Secrets and variables → Actions**.

| Secret | What it is |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID |
| `ASC_KEY_CONTENT` | The `.p8` API key, **base64-encoded** |
| `BUILD_CERTIFICATE_BASE64` | Apple **Distribution** certificate as a `.p12`, base64-encoded |
| `P12_PASSWORD` | Password you set when exporting the `.p12` |
| `BUILD_PROVISION_PROFILE_BASE64` | **App Store** provisioning profile (`.mobileprovision`), base64-encoded |
| `KEYCHAIN_PASSWORD` | Any random string (used to lock the temp CI keychain) |

### 1. App Store Connect API key (`ASC_*`)

App Store Connect → **Users and Access → Integrations → App Store Connect API** → generate a key with the **App Manager** role. Download the `.p8` (you can only download it once).

```bash
# Key ID and Issuer ID are shown on that page.
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy   # → paste into ASC_KEY_CONTENT
```

### 2. Distribution certificate (`BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`)

In **Keychain Access**, find your **Apple Distribution** certificate (create one in the Developer portal if you don't have it), right-click → **Export** → save as `.p12`, set an export password (that's `P12_PASSWORD`).

```bash
base64 -i Distribution.p12 | pbcopy        # → paste into BUILD_CERTIFICATE_BASE64
```

### 3. App Store provisioning profile (`BUILD_PROVISION_PROFILE_BASE64`)

Developer portal → **Profiles** → create an **App Store** profile for `com.gitphotos.gitphotos`, tied to the distribution cert above. Download the `.mobileprovision`.

```bash
base64 -i GitPhotos_AppStore.mobileprovision | pbcopy   # → paste into BUILD_PROVISION_PROFILE_BASE64
```

> Tip: the easiest way to get a matching cert **and** profile is to Archive once in Xcode locally (Automatic signing), then export the distribution cert from Keychain and download the generated App Store profile from the portal.

### 4. Keychain password

```bash
openssl rand -base64 24 | pbcopy           # → paste into KEYCHAIN_PASSWORD
```

## Notes

- **Build number** is set to the GitHub run number, so every upload is unique. `MARKETING_VERSION` (the user-facing version, currently `1.0`) is bumped manually in the project / via your `v*` tag.
- **Runner / Xcode:** the job uses `macos-15` + `Xcode_16.2`. Bump these in the workflow as Xcode releases.
- **Test locally** before relying on CI: `bundle install` then `bundle exec fastlane beta` (TestFlight) with the `ASC_*` env vars set and a valid signing identity in your login keychain.
- The shared scheme `GitPhotos.xcscheme` is committed (CI requires a shared scheme); don't delete it.
