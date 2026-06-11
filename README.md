# GitPhotos

A Google-Photos-style iOS app that uses **your own GitHub account as free photo storage**.

## Features

- **Auto-sync from Photos** — turn it on once in Settings and GitPhotos backs up your whole library,
  then watches for new shots and uploads them automatically while the app is open. Photos already
  uploaded are tracked by their `PHAsset` id so nothing is ever uploaded twice.
- **Edit photos** — a Google-Photos-style editor (open a photo → slider icon). Adjust
  brightness/contrast/saturation/exposure, apply filter presets (Vivid, Mono, Noir, Fade, Chrome,
  Instant, Process), crop to common aspect ratios, and rotate. Saving overwrites the photo's blobs
  in place. Built on Core Image.
- **Remove photos** — delete a single photo from its viewer, or tap **Select** (or long-press a
  thumbnail) to multi-select and remove a batch at once. Removal deletes the blobs from GitHub and
  updates the index.
- **Multiple storage accounts** — start with one GitHub account; add more in Settings → Storage
  accounts. New photos are placed on whichever account has the most room, spreading a large library
  across several accounts. The first (primary) account holds the index and can't be removed.

## How it works

- **Index repo** — on first sign-in the app creates a private repo `gitphotos-index` containing
  `manifest.json`, the source of truth for every photo (which shard it lives in, file shas,
  dimensions, capture dates) and a running byte count per shard.
- **Storage shards** — photos live in private repos `gitphotos-store-001`, `-002`, … Each shard
  holds `photos/<id>.<ext>` (original) and `thumbs/<id>.jpg` (~400 px grid thumbnail).
- **Automatic sharding** — GitHub repos top out at 5 GB, so the app caps each shard at **4.5 GB**.
  When the next upload wouldn't fit, it creates the next shard repo automatically via the API.
  100 GB of photos ≈ 23 repos, no manual work.
- All transfers go through the GitHub Contents API (base64 PUT / raw GET). Per-file limit is
  100 MB, which is plenty for photos.
- Thumbnails and full-res images are cached on-device (memory + disk), so the grid stays fast
  and you only pay the network cost once per image.

## Signing in

Two options:

### Sign in with GitHub (OAuth device flow — recommended)

No token copying: tap the button, the app shows a short code, GitHub opens in the browser,
you type the code, done. Your username is detected automatically.

One-time setup (GitHub requires an app registration to issue OAuth tokens):

1. Go to <https://github.com/settings/applications/new>
2. Name it anything (e.g. "GitPhotos"); homepage/callback URL can be anything
   (e.g. `http://127.0.0.1`) — the device flow never uses the callback.
3. Check **Enable Device Flow** and register.
4. Copy the **Client ID** into `Config.githubClientID` in `GitPhotos/App/Config.swift`.

No client secret goes in the app — the device flow only needs the public client ID.

### Personal access token (fallback)

While `Config.githubClientID` is empty, the sign-in screen asks for a classic personal
access token with the `repo` scope instead, and links to the token creation page.

Either way, credentials are stored only in the iOS Keychain.

## Building

Requires Xcode 15+. Open `GitPhotos.xcodeproj`, pick a simulator or your phone, hit Run.

CLI build:

```sh
xcodebuild -project GitPhotos.xcodeproj -scheme GitPhotos \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
```

(`project.yml` is included for XcodeGen, but the checked-in `.xcodeproj` works as-is.)

## Source layout

```
GitPhotos/
  App/GitPhotosApp.swift        app entry, auth state
  Models/Models.swift           Photo, StoreRepo, Manifest
  Services/GitHubClient.swift   thin GitHub REST client
  Services/PhotoStore.swift     manifest sync, auto-sharding, upload/delete
  Services/ImageCache.swift     memory + disk image cache
  Services/ImageUtil.swift      EXIF inspection, thumbnail generation
  Models/Account.swift          GitHub account + multi-account Keychain storage
  Services/Keychain.swift       token storage
  Services/PhotoLibrarySync.swift  auto-sync: watches the photo library, uploads new photos
  Views/                        sign-in, library grid, photo viewer, settings
  Views/PhotoEditorView.swift   Core Image editor (adjust / filters / crop / rotate)
  Views/TokenHelpView.swift     "how to get a token" modal
  Assets.xcassets               app icon + logo
```

## Auto-sync notes & limits

- The first sync uploads your entire library, which can be slow and is bounded by GitHub's
  authenticated REST limit (~5,000 requests/hour ≈ ~1,500 photos/hour, since each photo is a
  couple of API writes). It resumes where it left off on the next launch.
- Sync runs while the app is in the foreground. True background uploads would need a
  `BGProcessingTask`; that's a reasonable next addition.
- Photos only (the Contents API caps a single file at 100 MB).

## Notes & limits

- Photos only for now (no video). The Contents API hard-fails above 100 MB per file.
- The manifest is updated once per upload batch with optimistic-concurrency retry, so two
  devices uploading at once won't clobber each other.
- "Storage shards" in Settings shows per-repo usage against the 4.5 GB cap.
