# GitPhotos — App Store Connect Submission Guide

Everything to fill out in App Store Connect (ASC), with ready-to-paste copy and my
recommended answers. Anything in **CAPS/brackets** is a value only you can supply.

App facts pulled from the project:
- **App name:** GitPhotos
- **Bundle ID:** `com.gitphotos.gitphotos`
- **Version / Build:** 1.0 / 1
- **Min iOS:** 17.0
- **Team ID:** L6LUXM357X
- **Encryption:** `ITSAppUsesNonExemptEncryption = false` (already set → no export-compliance paperwork)
- **What it does:** Backs up your iPhone photo library to *your own* private GitHub
  repositories. Sign in with GitHub (OAuth device flow or a personal access token),
  browse/search/favorite photos, organize by month, edit (crop/rotate/filters),
  auto-sync new photos, multi-account storage. Token stored in Keychain. No developer backend.

---

## 1. Create the App record (My Apps → ➕ → New App)

| Field | Value |
|---|---|
| Platform | iOS |
| Name | **GitPhotos** |
| Primary Language | English (U.S.) |
| Bundle ID | com.gitphotos.gitphotos |
| SKU | `gitphotos-ios-001` (any unique internal string) |
| User Access | Full Access |

---

## 2. App Information (left sidebar → General → App Information)

- **Name:** GitPhotos
- **Subtitle (30 char max):** `Back up photos to GitHub`
- **Category — Primary:** Photo & Video
- **Category — Secondary:** Utilities
- **Content Rights:** "No, it does not contain, show, or access third-party content."
  (Users only access their own GitHub content.)
- **Age Rating:** complete questionnaire → answer **None** to every item → results in **4+**.
- **Privacy Policy URL:** *required* — see §8 below.

---

## 3. Pricing and Availability

- **Price:** Free (Tier 0)
- **Availability:** All countries/regions
- No pre-orders.

---

## 4. Version Metadata (the "1.0 Prepare for Submission" page)

### Promotional Text (170 char, editable anytime without a new build)
```
Your photos. Your GitHub. Your control. GitPhotos backs up your camera roll straight to your own private repositories — no middleman, no extra cloud account.
```

### Description (4000 char max) — paste as-is
```
GitPhotos backs up your iPhone photos to your own private GitHub repositories. There's no GitPhotos cloud, no separate subscription, and no company sitting between you and your pictures — your photos go directly from your phone to repos that you own and control.

WHY GITPHOTOS
• You already trust GitHub. Now use it for your photos.
• Private by default. Backups land in private repositories only you can see.
• No middleman. The app has no backend — nothing is routed through our servers, because there are no servers.
• Your storage, your rules. Bring your own account and use the space the way you want.

FEATURES
• Sign in with GitHub using a secure device-code flow, or paste a personal access token. Tokens are stored in the iOS Keychain.
• One-tap backup of any photo, or turn on Auto-sync to back up new photos automatically.
• Browse your library by day and month, search by date, and mark favorites.
• Built-in editor: crop to common aspect ratios, rotate, and apply quick filter presets before you back up.
• Multiple accounts: connect more than one GitHub account and see storage usage per repository.
• Clear, honest progress — see exactly how many photos have uploaded.

HOW IT WORKS
1. Sign in with your GitHub account.
2. Pick the photos to back up, or enable Auto-sync.
3. GitPhotos commits them to a private repository on your account.

GOOD TO KNOW
GitPhotos uses GitHub's standard API, which limits uploads to roughly 1,500 photos per hour. Large first-time backups continue across sessions. You stay in full control: revoke access any time from your GitHub settings, and delete a repo to delete those backups.

GitPhotos is not affiliated with or endorsed by GitHub, Inc.
```

### Keywords (100 char max, comma-separated, no spaces after commas)
```
github,photo backup,git,cloud,private repo,sync,gallery,camera roll,storage,developer,self host
```

### Support URL (required)
`https://github.com/asrayg/free-photo-storage-app` — or a simple support page / README. Must resolve.

### Marketing URL (optional)
Leave blank or point to a landing page / repo.

### What's New in This Version
Not required for the first 1.0 release. (For future updates, describe changes here.)

### Screenshots
- **Required size you already generated:** 1284 × 2778 (6.5" iPhone) — in `screenshots/appstore/`.
- Drag in 1–10 images. The first 1–3 are what most users see, so lead with your best.
- 6.5" screenshots auto-scale to the 6.7"/6.9" slot, so this one set is enough.
- No status-bar/personal-info concerns since these are simulator captures.

### App Preview (optional)
Skip for 1.0 unless you have a video.

---

## 5. Build

- Upload via Xcode (Product → Archive → Distribute) or your CI App Store pipeline.
- After processing (~15–60 min), select the build on the version page.
- **Export compliance:** because `ITSAppUsesNonExemptEncryption = false` is in Info.plist,
  ASC won't prompt for encryption docs. (Only HTTPS/standard crypto is used.)

---

## 6. App Review Information  ⚠️ MOST IMPORTANT — don't skip

GitPhotos **requires a GitHub login**, so the reviewer cannot test it without credentials.
Apple will reject it as "unable to sign in" if you leave this blank.

- **Sign-in required:** Yes.
- **Provide a demo account:** create a throwaway GitHub account for review, generate a
  **classic Personal Access Token with `repo` scope**, and put it in the notes (the app
  supports manual token entry). Use the username/password fields plus the notes box.

  - Demo username: **[throwaway github username]**
  - Demo password: **[password]**

- **Notes (paste and edit):**
```
GitPhotos backs up the device photo library to the user's own private GitHub repositories.

TO TEST:
1. Launch the app and tap "Use a personal access token instead."
2. Paste this GitHub personal access token (classic, scope: repo):
   [PASTE A VALID PAT HERE — repo scope]
3. Tap Sign in. You'll see the photo library.
4. Allow Photos access when prompted.
5. Select any photo and tap Add (or open Settings and enable Auto-sync) to back it up.
   The photo is committed to a private repo named "GitPhotos-Backup" on the account.

NOTES:
- There is no GitPhotos server; photos are sent directly to GitHub via the official API.
- NSPhotoLibraryUsageDescription is required because the app reads photos to back them up.
- Uploads are rate-limited by GitHub (~1,500/hour); a single photo is instant.
```
> Tip: regenerate/revoke that PAT after review is approved.

- **Contact info:** First name, last name, phone, and email Apple can reach you at.
- **Attachment:** none needed.

---

## 7. Age Rating questionnaire (answers)

Answer **None / No** to everything (no violence, no mature themes, no user-generated content
shared publicly, no unrestricted web, no gambling, etc.) → **4+**.

---

## 8. App Privacy (Data collection questionnaire) — left sidebar → App Privacy

This is a separate, mandatory section. Recommended answers for GitPhotos:

- **Privacy Policy URL:** required. Host a short policy (GitHub Pages / Gist / Notion works).
  Minimum it should say: GitPhotos has no backend; photos and tokens never reach the
  developer; photos are uploaded only to the user's own GitHub repos; the GitHub token is
  stored in the device Keychain; deleting the app / revoking the token / deleting the repo
  removes access. Link GitHub's own privacy policy as the third party.

- **Data collection:** Does your app collect data?
  - The **developer** collects **nothing** (no analytics, no server). If the app has no
    third-party SDKs that phone home, you can select **"Data Not Collected."**
  - ⚠️ Caveat: ASC's definition includes data sent off-device. Photos ARE sent to GitHub,
    but to the *user's own* account at their direction, and not to you. The standard reading
    is still "Data Not Collected" for the developer. If you prefer maximum caution, you may
    instead declare **Photos** under "Data Not Linked to You / App Functionality / Not used
    for tracking." Either is defensible; **Data Not Collected** is the simplest accurate answer
    given there's no backend or SDK. Pick one and be consistent with your privacy policy.

- **Tracking:** No. The app does not track users across apps/websites → no ATT prompt needed.

---

## 9. Version Release

- **Release option:** "Automatically release this version" (or "Manually release" if you want
  to push the button yourself after approval).
- **Phased Release:** optional; fine to leave on for a 1.0.

---

## Submission checklist

- [ ] App record created with bundle ID `com.gitphotos.gitphotos`
- [ ] Name, subtitle, categories set
- [ ] Description, keywords, promo text pasted
- [ ] Support URL resolves
- [ ] Privacy Policy URL live
- [ ] 6.5" screenshots (1284 × 2778) uploaded
- [ ] Build uploaded and selected
- [ ] App Privacy questionnaire completed
- [ ] Age rating completed (4+)
- [ ] **App Review notes + demo GitHub account/PAT provided** ← most common rejection cause
- [ ] Contact info filled
- [ ] Pricing = Free, availability set
- [ ] Submit for Review
```
```
