import Foundation
import Photos
import Observation

/// Watches the device photo library and auto-uploads new photos. When enabled,
/// it does an initial pass over everything not yet in GitHub, then keeps in sync
/// via the system change observer while the app is open.
@MainActor
@Observable
final class PhotoLibrarySync: NSObject, PHPhotoLibraryChangeObserver {
    enum Access { case notDetermined, denied, authorized, limited }

    private(set) var access: Access = .notDetermined
    private(set) var isSyncing = false

    /// User toggle, persisted. Turning it on kicks off a sync immediately.
    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.key)
            if enabled { Task { await enable() } }
        }
    }

    private static let key = "autoSyncEnabled"
    private weak var store: PhotoStore?
    private var observing = false

    init(store: PhotoStore) {
        self.store = store
        self.enabled = UserDefaults.standard.bool(forKey: Self.key)
        super.init()
    }

    /// Called once the library appears. Resumes auto-sync if it was left on.
    func start() async {
        refreshAccess()
        if enabled { await enable() }
    }

    private func enable() async {
        await requestAccess()
        guard access == .authorized || access == .limited else { return }
        if !observing {
            PHPhotoLibrary.shared().register(self)
            observing = true
        }
        await syncNow()
    }

    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        apply(status)
    }

    private func refreshAccess() {
        apply(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private func apply(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized: access = .authorized
        case .limited: access = .limited
        case .denied, .restricted: access = .denied
        default: access = .notDetermined
        }
    }

    /// Finds library photos not yet uploaded and hands them to the store.
    func syncNow() async {
        guard enabled, let store,
              access == .authorized || access == .limited,
              !isSyncing, !store.upload.isActive else { return }
        isSyncing = true
        defer { isSyncing = false }

        let known = store.syncedLocalIDs
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)

        var pending: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            if !known.contains(asset.localIdentifier) {
                pending.append(asset)
            }
        }
        guard !pending.isEmpty else { return }
        await store.uploadAssets(pending)
    }

    // PHPhotoLibraryChangeObserver — fires when the user takes/imports a photo.
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in await self.syncNow() }
    }
}
