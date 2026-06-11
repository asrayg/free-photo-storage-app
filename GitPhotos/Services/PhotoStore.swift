import Foundation
import SwiftUI
import PhotosUI
import Photos
import Observation

enum StoreError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}

/// Orchestrates everything: the manifest in the index repo, automatic store-repo
/// sharding (across one or more GitHub accounts), uploads, edits, deletes, and
/// image fetching.
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

    private(set) var accounts: [Account]
    private var clients: [String: GitHubClient] = [:]
    var sync: PhotoLibrarySync!

    init(accounts: [Account]) {
        self.accounts = accounts
        rebuildClients()
        self.sync = PhotoLibrarySync(store: self)
    }

    // MARK: - Accounts

    /// The account that owns the index repo (source of truth).
    var primary: Account { accounts[0] }
    private var indexClient: GitHubClient { clients[primary.login]! }

    private func rebuildClients() {
        var dict: [String: GitHubClient] = [:]
        for account in accounts {
            dict[account.login] = GitHubClient(username: account.login, token: account.token)
        }
        clients = dict
    }

    private func client(for owner: String?) -> GitHubClient? {
        clients[owner ?? primary.login]
    }

    /// Adds another GitHub account that new photos can be stored on.
    func addStorageAccount(token: String) async throws {
        let login = try await GitHubClient.login(token: token)
        guard !accounts.contains(where: { $0.login.lowercased() == login.lowercased() }) else {
            throw StoreError.message("'\(login)' is already added.")
        }
        accounts.append(Account(login: login, token: token))
        Keychain.saveAccounts(accounts)
        rebuildClients()
    }

    /// Removes a non-primary storage account. Photos already stored there stay in
    /// the manifest but become unreachable until the account is re-added.
    func removeStorageAccount(_ login: String) {
        guard login != primary.login else { return }
        accounts.removeAll { $0.login == login }
        Keychain.saveAccounts(accounts)
        rebuildClients()
    }

    struct AccountUsage: Identifiable {
        let account: Account
        let bytes: Int64
        let repos: [StoreRepo]
        var id: String { account.login }
    }

    var storageByAccount: [AccountUsage] {
        accounts.map { account in
            let repos = manifest.repos.filter { ($0.owner ?? primary.login) == account.login }
            return AccountUsage(account: account, bytes: repos.reduce(0) { $0 + $1.bytes }, repos: repos)
        }
    }

    // MARK: - Derived state

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

    /// PHAsset ids already in the library — used to skip photos we've synced before.
    var syncedLocalIDs: Set<String> {
        Set(manifest.photos.compactMap(\.localIdentifier))
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if try await !indexClient.repoExists(Self.indexRepo) {
                try await indexClient.createPrivateRepo(Self.indexRepo, description: "GitPhotos index — do not edit by hand")
                let data = try JSONEncoder.manifest.encode(Manifest.empty)
                manifestSha = try await indexClient.putContent(
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
            let meta = try await indexClient.contentMeta(repo: Self.indexRepo, path: Self.manifestPath)
            manifestSha = meta.sha
            let data: Data
            if let content = meta.content, let decoded = Data(base64Encoded: content, options: .ignoreUnknownCharacters), !decoded.isEmpty {
                data = decoded
            } else {
                data = try await indexClient.rawContent(repo: Self.indexRepo, path: Self.manifestPath)
            }
            manifest = try JSONDecoder.manifest.decode(Manifest.self, from: data)
        } catch GitHubError.notFound {
            let data = try JSONEncoder.manifest.encode(Manifest.empty)
            manifestSha = try await indexClient.putContent(
                repo: Self.indexRepo, path: Self.manifestPath,
                data: data, message: "Initialize manifest")
            manifest = .empty
        }
    }

    private func saveManifest(message: String, merge: (inout Manifest) -> Void) async throws {
        var attempts = 0
        while true {
            attempts += 1
            do {
                let data = try JSONEncoder.manifest.encode(manifest)
                manifestSha = try await indexClient.putContent(
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

    /// Picks the (account, repo) for the next upload. New shards are placed on the
    /// storage account currently holding the least data, spreading photos across
    /// accounts; a new repo is created automatically when the chosen one fills up.
    private func repoForUpload(bytes: Int64) async throws -> (owner: String, name: String) {
        var usage: [String: Int64] = [:]
        for repo in manifest.repos { usage[repo.owner ?? primary.login, default: 0] += repo.bytes }
        let target = accounts.min { (usage[$0.login] ?? 0) < (usage[$1.login] ?? 0) }?.login ?? primary.login

        let targetRepos = manifest.repos.filter { ($0.owner ?? primary.login) == target }
        if let last = targetRepos.last, last.bytes + bytes <= Self.repoByteCap {
            return (target, last.name)
        }
        let n = targetRepos.count + 1
        let name = Self.storeRepoPrefix + String(format: "%03d", n)
        guard let c = clients[target] else { throw StoreError.message("Missing credentials for \(target).") }
        if try await !c.repoExists(name) {
            try await c.createPrivateRepo(name, description: "GitPhotos storage shard \(n)")
        }
        manifest.repos.append(StoreRepo(owner: target, name: name, bytes: 0))
        return (target, name)
    }

    private func addBytes(_ bytes: Int64, owner: String, name: String, in m: inout Manifest) {
        if let i = m.repos.firstIndex(where: { ($0.owner ?? primary.login) == owner && $0.name == name }) {
            m.repos[i].bytes = max(0, m.repos[i].bytes + bytes)
        } else if bytes > 0 {
            m.repos.append(StoreRepo(owner: owner, name: name, bytes: bytes))
        }
    }

    // MARK: - Upload

    private func ingest(data: Data, localIdentifier: String?, fallbackDate: Date?) async throws -> Photo? {
        guard let info = ImageUtil.inspect(data),
              let thumbData = ImageUtil.makeThumbnail(from: data) else { return nil }
        let id = UUID().uuidString.lowercased()
        let cost = Int64(data.count + thumbData.count)
        let (owner, repoName) = try await repoForUpload(bytes: cost)
        guard let c = clients[owner] else { throw StoreError.message("Missing credentials for \(owner).") }
        let path = "photos/\(id).\(info.fileExtension)"
        let thumbPath = "thumbs/\(id).jpg"

        let sha = try await c.putContent(repo: repoName, path: path, data: data, message: "Add \(id)")
        let thumbSha = try await c.putContent(repo: repoName, path: thumbPath, data: thumbData, message: "Add thumb \(id)")

        let photo = Photo(
            id: id,
            filename: "IMG_\(id.prefix(8)).\(info.fileExtension)",
            repo: repoName, owner: owner, path: path, thumbPath: thumbPath,
            size: Int64(data.count), sha: sha, thumbSha: thumbSha,
            width: info.width, height: info.height,
            createdAt: info.captureDate ?? fallbackDate ?? Date(),
            uploadedAt: Date(), localIdentifier: localIdentifier)

        manifest.photos.append(photo)
        addBytes(cost, owner: owner, name: repoName, in: &manifest)
        _ = await ImageCache.shared.store(thumbData, for: "\(id)-thumb")
        _ = await ImageCache.shared.store(data, for: "\(id)-full")
        return photo
    }

    private func persist(_ added: [Photo], verb: String) async {
        guard !added.isEmpty else { return }
        do {
            try await saveManifest(message: "\(verb) \(added.count) photo(s)") { m in
                for photo in added where !m.photos.contains(where: { $0.id == photo.id }) {
                    m.photos.append(photo)
                    self.addBytes(photo.size, owner: photo.owner ?? self.primary.login, name: photo.repo, in: &m)
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

    private static func assetData(_ asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    // MARK: - Edit

    /// Replaces a photo's bytes in place with an edited version (overwrites the
    /// original and thumbnail blobs, keeping the same id and paths).
    func replace(_ photo: Photo, withFullData data: Data) async {
        guard let c = client(for: photo.owner) else {
            errorMessage = "Missing credentials for \(photo.owner ?? primary.login)."
            return
        }
        guard let info = ImageUtil.inspect(data),
              let thumbData = ImageUtil.makeThumbnail(from: data) else {
            errorMessage = "Couldn't process the edited image."
            return
        }
        do {
            let newSha = try await c.putContent(repo: photo.repo, path: photo.path, data: data, message: "Edit \(photo.id)", sha: photo.sha)
            let newThumbSha = try await c.putContent(repo: photo.repo, path: photo.thumbPath, data: thumbData, message: "Edit thumb \(photo.id)", sha: photo.thumbSha)
            let delta = Int64(data.count) - photo.size

            if let i = manifest.photos.firstIndex(where: { $0.id == photo.id }) {
                manifest.photos[i].sha = newSha
                manifest.photos[i].thumbSha = newThumbSha
                manifest.photos[i].size = Int64(data.count)
                manifest.photos[i].width = info.width
                manifest.photos[i].height = info.height
                manifest.photos[i].uploadedAt = Date()
            }
            addBytes(delta, owner: photo.owner ?? primary.login, name: photo.repo, in: &manifest)
            _ = await ImageCache.shared.store(data, for: "\(photo.id)-full")
            _ = await ImageCache.shared.store(thumbData, for: "\(photo.id)-thumb")

            try await saveManifest(message: "Edit \(photo.id)") { m in
                if let i = m.photos.firstIndex(where: { $0.id == photo.id }) {
                    m.photos[i].sha = newSha
                    m.photos[i].thumbSha = newThumbSha
                    m.photos[i].size = Int64(data.count)
                    m.photos[i].width = info.width
                    m.photos[i].height = info.height
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete

    func delete(_ photo: Photo) async { await delete([photo]) }

    func delete(_ photos: [Photo]) async {
        guard !photos.isEmpty else { return }
        var removed: [Photo] = []
        for photo in photos {
            guard let c = client(for: photo.owner) else { continue }
            do {
                try await c.deleteContent(repo: photo.repo, path: photo.path, sha: photo.sha, message: "Delete \(photo.id)")
                try? await c.deleteContent(repo: photo.repo, path: photo.thumbPath, sha: photo.thumbSha, message: "Delete thumb \(photo.id)")
                removed.append(photo)
                manifest.photos.removeAll { $0.id == photo.id }
                addBytes(-photo.size, owner: photo.owner ?? primary.login, name: photo.repo, in: &manifest)
                await ImageCache.shared.remove("\(photo.id)-thumb")
                await ImageCache.shared.remove("\(photo.id)-full")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        guard !removed.isEmpty else { return }
        let ids = Set(removed.map(\.id))
        do {
            try await saveManifest(message: "Delete \(removed.count) photo(s)") { m in
                m.photos.removeAll { ids.contains($0.id) }
                for p in removed {
                    self.addBytes(-p.size, owner: p.owner ?? self.primary.login, name: p.repo, in: &m)
                }
            }
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
        guard let c = client(for: photo.owner),
              let data = try? await c.rawContent(repo: photo.repo, path: path) else { return nil }
        return await ImageCache.shared.store(data, for: cacheKey)
    }
}
