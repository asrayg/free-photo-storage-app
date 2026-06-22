# App Store Release CI

GitHub Actions builds, signs, and uploads **GitPhotos** to App Store Connect using
**cloud automatic signing** — the same approach as the `pippa-ios` repo.

- **Workflow:** [`.github/workflows/release.yml`](../.github/workflows/release.yml)
- **Export options:** [`ci/ExportOptions.plist`](../ci/ExportOptions.plist)
- **Triggers:**
  - Push a tag matching `v*` (e.g. `git tag v1.0.0 && git push origin v1.0.0`).
  - Manual **Run workflow** in the Actions tab.

No certificates or provisioning profiles are stored anywhere: `xcodebuild
-allowProvisioningUpdates` + the App Store Connect API key let Xcode create and
download whatever signing assets it needs at build time. The build is uploaded to
App Store Connect; promote/submit it for review from there.

## Required GitHub Secrets

Only three, all from one App Store Connect API key:

| Secret | What it is |
| --- | --- |
| `ASC_KEY_ID` | The API key ID (e.g. `AF3ZAPRD75`) |
| `ASC_ISSUER_ID` | The API issuer ID (shown at the top of the API keys page) |
| `ASC_API_KEY_P8` | The full `.p8` key text (PEM, including the BEGIN/END lines) |

Create the key at **App Store Connect → Users and Access → Integrations → App
Store Connect API** with the **App Manager** role. Same Apple team as `pippa-ios`
(`L6LUXM357X`), so the same key works for both apps.

## Notes

- **Runner / Xcode:** uses `macos-26` + Xcode 26 because Apple now requires the
  **iOS 26 SDK** for uploads. A verify step fails fast if the SDK is missing.
- **Build number** is set to the GitHub run number, so every upload is unique.
  `MARKETING_VERSION` (currently `1.0`) is bumped manually / via your `v*` tag.
- The shared scheme `GitPhotos.xcscheme` is committed (CI requires a shared
  scheme); don't delete it.
