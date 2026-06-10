import Foundation
import SwiftUI
import PhotosUI
import Photos
import Observation

/// Orchestrates everything: the manifest in the index repo, automatic store-repo
/// sharding, uploads, deletes, and image fetching.
@MainActor
@Observable
final class PhotoStore {
    // GitHub's hard repo limit is 5 GB; shard well before that.
    static let repoByteCap: Int64 = 4_500_000_000
    static let indexRepo = "gitphotos-index"
    static let storeRepoPrefix = "gitphotos-store-"
    static let manifestPath = "manifest.json"

    struct UploadProgress {
        var total = 0
        var completed = 0
        var failed = 0
        var currentName = ""
        var isActive: Bool { total > 0 && completed + failed < total }
    }

    private(set) var manifest = Manifest.empty
    private var manifestSha: String?
    private(set) var isLoading = false
    private(set) var upload = UploadProgress()
    var errorMessage: String?

    let client: GitHubClient
    var sync: PhotoLibrarySync!

    init(client: GitHubClient) {
        self.client = client
        self.sync = PhotoLibrarySync(store: self)
    }

    /// PHAsset ids already in the library — used to skip photos we've synced before.
    var syncedLocalIDs: Set<String> {
        Set(manifest.photos.compactMap(\.localIdentifier))
    }

    var photosByMonth: [(month: String, photos: [Photo])] {
        let sorted = manifest.photos.sorted { $0.createdAt > $1.createdAt }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var groups: [(month: String, photos: [Photo])] = []
        for photo in sorted {
            let label = formatter.string(from: photo.createdAt)
            if groups.last?.month == label {
                groups[groups.count - 1].photos.append(photo)
            } else {
                groups.append((month: label, photos: [photo]))
            }
        }
        return groups
    }

    var totalBytes: Int64 { manifest.repos.reduce(0) { $0 + $1.bytes } }

    // MARK: - Bootstrap

    /// Creates the index repo on first run and loads the manifest.
    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if try await !client.repoExists(Self.indexRepo) {
                try await client.createPrivateRepo(Self.indexRepo, description: "GitPhotos index — do not edit by hand")
                let data = try JSONEncoder.manifest.encode(Manifest.empty)
                manifestSha = try await client.putContent(
                    repo: Self.indexRepo, path: Self.manifestPath,
                    data: data, message: "Initialize manifest")
                manifest = .empty
            } else {
                try await loadManifest()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadManifest() async throws {
        do {
            let meta = try await client.contentMeta(repo: Self.indexRepo, path: Self.manifestPath)
            manifestSha = meta.sha
            // The contents API inlines base64 content only for files <= 1 MB;
            // bigger manifests need a separate raw fetch.
            let data: Data
            if let content = meta.content, let decoded = Data(base64Encoded: content, options: .ignoreUnknownCharacters), !decoded.isEmpty {
                data = decoded
            } else {
                data = try await client.rawContent(repo: Self.indexRepo, path: Self.manifestPath)
            }
            manifest = try JSONDecoder.manifest.decode(Manifest.self, from: data)
        } catch GitHubError.notFound {
            // Index repo exists but manifest.json doesn't yet (e.g. interrupted first run).
            let data = try JSONEncoder.manifest.encode(Manifest.empty)
            manifestSha = try await client.putContent(
                repo: Self.indexRepo, path: Self.manifestPath,
                data: data, message: "Initialize manifest")
            manifest = .empty
        }
    }

    /// Writes the manifest back. On a sha conflict, reloads and lets `merge`
    /// reapply this change on top of the fresh copy.
    private func saveManifest(message: String, merge: (inout Manifest) -> Void) async throws {
        var attempts = 0
        while true {
            attempts += 1
            do {
                let data = try JSONEncoder.manifest.encode(manifest)
                manifestSha = try await client.putContent(
                    repo: Self.indexRepo, path: Self.manifestPath,
                    data: data, message: message, sha: manifestSha)
                return
            } catch GitHubError.conflict where attempts < 4 {
                try await loadManifest()
                merge(&manifest)
            }
        }
    }

    // MARK: - Sharding

    /// Returns the store repo to upload `bytes` into, creating the next
    /// `gitphotos-store-NNN` repo automatically when the current one is full.
    private func repoForUpload(bytes: Int64) async throws -> String {
        if let last = manifest.repos.last, last.bytes + bytes <= Self.repoByteCap {
            return last.name
        }
        let next = manifest.repos.count + 1
        let name = Self.storeRepoPrefix + String(format: "%03d", next)
        if try await !client.repoExists(name) {
            try await client.createPrivateRepo(name, description: "GitPhotos storage shard \(next)")
        }
        manifest.repos.append(StoreRepo(name: name, bytes: 0))
        return name
    }

    private func addBytes(_ bytes: Int64, to repoName: String, in m: inout Manifest) {
        if let i = m.repos.firstIndex(where: { $0.name == repoName }) {
            m.repos[i].bytes = max(0, m.repos[i].bytes + bytes)
        } else if bytes > 0 {
            m.repos.append(StoreRepo(name: repoName, bytes: bytes))
        }
    }

    // MARK: - Upload

    /// Uploads one image's bytes into the right shard and appends it to the
    /// in-memory manifest. Shared by manual picks and auto-sync.
    private func ingest(data: Data, localIdentifier: String?, fallbackDate: Date?) async throws -> Photo? {
        guard let info = ImageUtil.inspect(data),
              let thumbData = ImageUtil.makeThumbnail(from: data) else { return nil }
        let id = UUID().uuidString.lowercased()
        let cost = Int64(data.count + thumbData.count)
        let repoName = try await repoForUpload(bytes: cost)
        let path = "photos/\(id).\(info.fileExtension)"
        let thumbPath = "thumbs/\(id).jpg"

        let sha = try await client.putContent(repo: repoName, path: path, data: data, message: "Add \(id)")
        let thumbSha = try await client.putContent(repo: repoName, path: thumbPath, data: thumbData, message: "Add thumb \(id)")

        let photo = Photo(
            id: id,
            filename: "IMG_\(id.prefix(8)).\(info.fileExtension)",
            repo: repoName, path: path, thumbPath: thumbPath,
            size: Int64(data.count), sha: sha, thumbSha: thumbSha,
            width: info.width, height: info.height,
            createdAt: info.captureDate ?? fallbackDate ?? Date(),
            uploadedAt: Date(), localIdentifier: localIdentifier)

        manifest.photos.append(photo)
        addBytes(cost, to: repoName, in: &manifest)
        _ = await ImageCache.shared.store(thumbData, for: "\(id)-thumb")
        _ = await ImageCache.shared.store(data, for: "\(id)-full")
        return photo
    }

    /// Commits a batch of freshly ingested photos to the manifest in the index repo.
    private func persist(_ added: [Photo], verb: String) async {
        guard !added.isEmpty else { return }
        do {
            try await saveManifest(message: "\(verb) \(added.count) photo(s)") { m in
                for photo in added where !m.photos.contains(where: { $0.id == photo.id }) {
                    m.photos.append(photo)
                    self.addBytes(photo.size, to: photo.repo, in: &m)
                }
            }
        } catch {
            errorMessage = "Photos uploaded but the index update failed: \(error.localizedDescription)"
        }
    }

    func uploadPickedItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        upload = UploadProgress(total: items.count)
        var added: [Photo] = []
        for (index, item) in items.enumerated() {
            upload.currentName = "Photo \(index + 1) of \(items.count)"
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let photo = try await ingest(data: data, localIdentifier: nil, fallbackDate: nil) else {
                    upload.failed += 1
                    continue
                }
                added.append(photo)
                upload.completed += 1
            } catch {
                upload.failed += 1
                errorMessage = error.localizedDescription
            }
        }
        await persist(added, verb: "Add")
        upload = UploadProgress()
    }

    /// Auto-sync entry point: uploads photo-library assets we haven't seen before.
    func uploadAssets(_ assets: [PHAsset]) async {
        guard !assets.isEmpty else { return }
        upload = UploadProgress(total: assets.count)
        var added: [Photo] = []
        for (index, asset) in assets.enumerated() {
            upload.currentName = "Syncing \(index + 1) of \(assets.count)"
            guard let data = await Self.assetData(asset) else {
                upload.failed += 1
                continue
            }
            do {
                if let photo = try await ingest(data: data, localIdentifier: asset.localIdentifier, fallbackDate: asset.creationDate) {
                    added.append(photo)
                    upload.completed += 1
                } else {
                    upload.failed += 1
                }
            } catch {
                upload.failed += 1
                errorMessage = error.localizedDescription
            }
        }
        await persist(added, verb: "Sync")
        upload = UploadProgress()
    }

    /// Reads the original file bytes for a photo-library asset.
    private static func assetData(_ asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true    // pull from iCloud if needed
            options.deliveryMode = .highQualityFormat
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    // MARK: - Delete

    func delete(_ photo: Photo) async {
        do {
            try await client.deleteContent(repo: photo.repo, path: photo.path, sha: photo.sha, message: "Delete \(photo.id)")
            try? await client.deleteContent(repo: photo.repo, path: photo.thumbPath, sha: photo.thumbSha, message: "Delete thumb \(photo.id)")
            manifest.photos.removeAll { $0.id == photo.id }
            addBytes(-photo.size, to: photo.repo, in: &manifest)
            try await saveManifest(message: "Delete \(photo.id)") { m in
                m.photos.removeAll { $0.id == photo.id }
                self.addBytes(-photo.size, to: photo.repo, in: &m)
            }
            await ImageCache.shared.remove("\(photo.id)-thumb")
            await ImageCache.shared.remove("\(photo.id)-full")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Fetching

    func thumbnail(for photo: Photo) async -> UIImage? {
        await fetch(photo: photo, path: photo.thumbPath, cacheKey: "\(photo.id)-thumb")
    }

    func fullImage(for photo: Photo) async -> UIImage? {
        await fetch(photo: photo, path: photo.path, cacheKey: "\(photo.id)-full")
    }

    private func fetch(photo: Photo, path: String, cacheKey: String) async -> UIImage? {
        if let cached = await ImageCache.shared.image(for: cacheKey) {
            return cached
        }
        guard let data = try? await client.rawContent(repo: photo.repo, path: path) else { return nil }
        return await ImageCache.shared.store(data, for: cacheKey)
    }
}
