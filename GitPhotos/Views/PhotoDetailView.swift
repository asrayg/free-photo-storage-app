import SwiftUI

enum DetailMode { case normal, trash }

/// Full-screen photo viewer: swipe between photos, pinch-zoom, a Google-style
/// bottom action bar (share / edit / favorite / info / trash), and an info sheet.
@MainActor
struct PhotoDetailView: View {
    let store: PhotoStore
    let photos: [Photo]
    let initialID: String
    var mode: DetailMode = .normal

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String?
    @State private var chromeVisible = true
    @State private var showInfo = false
    @State private var editTarget: EditTarget?
    @State private var shareImage: UIImage?
    @State private var loadingAction = false
    @State private var confirmDelete = false

    private struct EditTarget: Identifiable { let id = UUID(); let image: UIImage }

    /// The live copy from the store (so favorite state stays current).
    private var current: Photo? {
        let id = currentID ?? initialID
        return store.manifest.photos.first { $0.id == id } ?? photos.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentID) {
                ForEach(photos) { photo in
                    ZoomableImageView(store: store, photo: photo) {
                        withAnimation { chromeVisible.toggle() }
                    }
                    .tag(Optional(photo.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if chromeVisible {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(!chromeVisible)
        .onAppear { currentID = initialID }
        .sheet(isPresented: $showInfo) {
            if let photo = current { PhotoInfoSheet(store: store, photo: photo) }
        }
        .fullScreenCover(item: $editTarget) { target in
            if let photo = current {
                PhotoEditorView(store: store, photo: photo, original: target.image)
            }
        }
        .confirmationDialog(
            mode == .trash ? "Delete permanently? This can't be undone." : "Move to Trash?",
            isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button(mode == .trash ? "Delete permanently" : "Move to Trash", role: .destructive) {
                guard let photo = current else { return }
                Task {
                    if mode == .trash { await store.permanentlyDelete(photo) }
                    else { await store.trash([photo]) }
                    dismiss()
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            }
            Spacer()
            VStack(spacing: 1) {
                Text(current.map { Self.dateLine.string(from: $0.createdAt) } ?? "")
                    .font(.subheadline.weight(.semibold))
                Text(current.map { Self.timeLine.string(from: $0.createdAt) } ?? "")
                    .font(.caption2).opacity(0.8)
            }
            Spacer()
            Button { showInfo = true } label: {
                Image(systemName: "info.circle").font(.title3)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            if mode == .trash {
                barButton("Restore", "arrow.uturn.backward") {
                    guard let photo = current else { return }
                    Task { await store.restore([photo]); dismiss() }
                }
                Spacer()
                barButton("Delete", "trash") { confirmDelete = true }
            } else {
                barButton("Share", "square.and.arrow.up") { share() }
                Spacer()
                barButton("Edit", "slider.horizontal.3") { edit() }
                Spacer()
                barButton(current?.favorite == true ? "Favorited" : "Favorite",
                          current?.favorite == true ? "heart.fill" : "heart") {
                    guard let photo = current else { return }
                    Task { await store.setFavorite(photo, !photo.favorite) }
                }
                Spacer()
                barButton("Delete", "trash") { confirmDelete = true }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .center) {
            if loadingAction { ProgressView().tint(.white) }
        }
    }

    private func barButton(_ label: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 21))
                Text(label).font(.caption2)
            }
        }
    }

    private func edit() {
        guard let photo = current else { return }
        loadingAction = true
        Task {
            if let image = await store.fullImage(for: photo) { editTarget = EditTarget(image: image) }
            loadingAction = false
        }
    }

    private func share() {
        guard let photo = current else { return }
        loadingAction = true
        Task {
            shareImage = await store.fullImage(for: photo)
            loadingAction = false
            if let image = shareImage {
                ShareSheet.present(image: image)
            }
        }
    }

    private static let dateLine: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d, yyyy"; return f
    }()
    private static let timeLine: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
}

/// Bottom info sheet: capture date, dimensions, file size, and GitHub location.
struct PhotoInfoSheet: View {
    let store: PhotoStore
    let photo: Photo

    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    info("Name", photo.filename)
                    info("Date", Self.full.string(from: photo.createdAt))
                    info("Dimensions", "\(photo.width) × \(photo.height)  ·  \(megapixels)")
                    info("Size", ByteCountFormatter.string(fromByteCount: photo.size, countStyle: .file))
                }
                Section("Stored in GitHub") {
                    info("Account", photo.owner ?? store.primary.login)
                    info("Repository", photo.repo)
                    info("Path", photo.path)
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var megapixels: String {
        String(format: "%.1f MP", Double(photo.width * photo.height) / 1_000_000)
    }

    private func info(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline).textSelection(.enabled)
        }
    }

    private static let full: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .short; return f
    }()
}

/// Presents the system share sheet for an image via the active window.
enum ShareSheet {
    static func present(image: UIImage) {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        var top = root
        while let presented = top.presentedViewController { top = presented }
        vc.popoverPresentationController?.sourceView = top.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 80, width: 0, height: 0)
        top.present(vc, animated: true)
    }
}

/// Full-res image with pinch-to-zoom and double-tap-to-zoom.
struct ZoomableImageView: View {
    let store: PhotoStore
    let photo: Photo
    var onSingleTap: () -> Void = {}

    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1
    @State private var steadyZoom: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(zoom)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in zoom = min(max(steadyZoom * value, 1), 5) }
                                .onEnded { _ in steadyZoom = zoom }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(duration: 0.3)) {
                                zoom = zoom > 1 ? 1 : 2.5
                                steadyZoom = zoom
                            }
                        }
                        .onTapGesture(count: 1) { onSingleTap() }
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        .task(id: photo.id) {
            if image == nil { image = await store.thumbnail(for: photo) }
            if let full = await store.fullImage(for: photo) { image = full }
        }
    }
}
