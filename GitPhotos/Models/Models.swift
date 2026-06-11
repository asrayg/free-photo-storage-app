import Foundation

/// One photo tracked in the manifest. The actual bytes live in a store repo.
struct Photo: Codable, Identifiable, Hashable {
    var id: String                // UUID string, also used in file paths
    var filename: String          // display name
    var repo: String              // store repo name, e.g. "gitphotos-store-001"
    var owner: String?            // GitHub account login that holds this repo (nil = primary)
    var path: String              // "photos/<id>.<ext>"
    var thumbPath: String         // "thumbs/<id>.jpg"
    var size: Int64               // bytes of the full-res file
    var sha: String               // git blob sha of the full-res file (needed to delete)
    var thumbSha: String          // git blob sha of the thumbnail
    var width: Int
    var height: Int
    var createdAt: Date           // EXIF capture date when available, else upload time
    var uploadedAt: Date
    var localIdentifier: String?  // PHAsset id, set for auto-synced photos so we never re-upload
    var favorite: Bool = false
    var trashed: Bool = false
    var trashedAt: Date?

    init(id: String, filename: String, repo: String, owner: String?, path: String, thumbPath: String,
         size: Int64, sha: String, thumbSha: String, width: Int, height: Int, createdAt: Date,
         uploadedAt: Date, localIdentifier: String? = nil, favorite: Bool = false,
         trashed: Bool = false, trashedAt: Date? = nil) {
        self.id = id; self.filename = filename; self.repo = repo; self.owner = owner
        self.path = path; self.thumbPath = thumbPath; self.size = size; self.sha = sha
        self.thumbSha = thumbSha; self.width = width; self.height = height
        self.createdAt = createdAt; self.uploadedAt = uploadedAt; self.localIdentifier = localIdentifier
        self.favorite = favorite; self.trashed = trashed; self.trashedAt = trashedAt
    }

    // Custom decode so older manifests (without the newer fields) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        filename = try c.decode(String.self, forKey: .filename)
        repo = try c.decode(String.self, forKey: .repo)
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        path = try c.decode(String.self, forKey: .path)
        thumbPath = try c.decode(String.self, forKey: .thumbPath)
        size = try c.decode(Int64.self, forKey: .size)
        sha = try c.decode(String.self, forKey: .sha)
        thumbSha = try c.decode(String.self, forKey: .thumbSha)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        uploadedAt = try c.decode(Date.self, forKey: .uploadedAt)
        localIdentifier = try c.decodeIfPresent(String.self, forKey: .localIdentifier)
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        trashed = try c.decodeIfPresent(Bool.self, forKey: .trashed) ?? false
        trashedAt = try c.decodeIfPresent(Date.self, forKey: .trashedAt)
    }
}

/// A titled run of photos (a day, a month) used by the timeline grid.
struct PhotoSection: Identifiable {
    let id: Int
    let title: String
    var photos: [Photo]
}

/// Byte accounting for one store repo so we know when to shard.
struct StoreRepo: Codable, Hashable {
    var owner: String?            // GitHub account login (nil = primary)
    var name: String
    var bytes: Int64
}

/// manifest.json in the index repo — the single source of truth.
struct Manifest: Codable {
    var version: Int = 1
    var repos: [StoreRepo] = []
    var photos: [Photo] = []

    static let empty = Manifest()
}

extension JSONEncoder {
    static let manifest: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let manifest: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
