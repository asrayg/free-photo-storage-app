import Foundation
import UIKit

/// Two-level (memory + disk) cache for downloaded images, keyed by photo id + variant.
actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL

    init() {
        memory.countLimit = 500
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent(key)
    }

    func image(for key: String) -> UIImage? {
        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }
        guard let data = try? Data(contentsOf: fileURL(key)),
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    func store(_ data: Data, for key: String) -> UIImage? {
        try? data.write(to: fileURL(key))
        guard let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    func remove(_ key: String) {
        memory.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: fileURL(key))
    }

    func clearAll() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
