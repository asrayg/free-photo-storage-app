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
