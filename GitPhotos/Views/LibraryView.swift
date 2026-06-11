import SwiftUI
import PhotosUI

enum AppTab { case photos, collections, search }

/// Root container: the current tab's screen with a floating Google-Photos-style
/// nav bar overlaid at the bottom.
@MainActor
struct RootView: View {
    @Bindable var store: PhotoStore
    @State private var tab: AppTab = .photos
    @State private var picked: [PhotosPickerItem] = []
    @State private var navHidden = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .photos: PhotosTabView(store: store, navHidden: $navHidden)
                case .collections: CollectionsView(store: store, navHidden: $navHidden)
                case .search: SearchView(store: store, navHidden: $navHidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !navHidden {
                FloatingNav(tab: $tab, picked: $picked)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: navHidden)
        .task {
            await store.bootstrap()
            await store.sync.start()
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await store.uploadPickedItems(items) }
        }
        .alert("Error", isPresented: .init(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

/// Floating pill (Photos · Collections · Add) plus a separate Search circle.
struct FloatingNav: View {
    @Binding var tab: AppTab
    @Binding var picked: [PhotosPickerItem]

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                pill(.photos, "photo.on.rectangle.angled", "Photos")
                pill(.collections, "square.stack", "Collections")
                PhotosPicker(selection: $picked, maxSelectionCount: 100, matching: .images) {
                    item("plus.circle.fill", "Add", active: false)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)

            Button { tab = .search } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 54, height: 54)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(tab == .search ? Color.accentColor : .white.opacity(0.08), lineWidth: tab == .search ? 2 : 1))
                    .foregroundStyle(tab == .search ? Color.accentColor : .primary)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            }
        }
        .padding(.bottom, 6)
    }

    private func pill(_ target: AppTab, _ icon: String, _ label: String) -> some View {
        Button { tab = target } label: {
            item(icon, label, active: tab == target)
        }
    }

    private func item(_ icon: String, _ label: String, active: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 20, weight: .medium))
            Text(label).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(active ? Color.accentColor : .secondary)
        .frame(width: 78, height: 46)
        .background(active ? Color.accentColor.opacity(0.14) : .clear, in: Capsule())
    }
}

// MARK: - Reusable timeline grid

/// The scrollable photo grid: day/section headers, pinch-to-change-density,
/// a right-edge fast-scroll date scrubber, and multi-select.
struct PhotoGrid: View {
    let store: PhotoStore
    let sections: [PhotoSection]
    @Binding var columns: Int
    var allowPinch: Bool = false
    var showScrubber: Bool = false
    @Binding var selecting: Bool
    @Binding var selection: Set<String>
    let onOpen: (Photo) -> Void

    @State private var scrubbing = false
    @State private var scrubLabel = ""
    @State private var scrubY: CGFloat = 0

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 3), count: columns)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                LazyVGrid(columns: gridColumns, spacing: 3) {
                                    ForEach(section.photos) { photo in
                                        cell(photo)
                                    }
                                }
                                .padding(.horizontal, 3)
                            } header: {
                                header(section)
                            }
                            .id(section.id)
                        }
                        Color.clear.frame(height: 96)   // clearance for the floating nav
                    }
                }
                .scrollIndicators(showScrubber ? .hidden : .automatic)
                .simultaneousGesture(allowPinch ? pinch : nil)
                .overlay(alignment: .topTrailing) {
                    if showScrubber && sections.count > 4 {
                        scrubber(height: geo.size.height, proxy: proxy)
                    }
                }
            }
        }
    }

    private func cell(_ photo: Photo) -> some View {
        ThumbnailCell(store: store, photo: photo, isSelected: selection.contains(photo.id), showSelection: selecting)
            .onTapGesture {
                if selecting { toggle(photo) } else { onOpen(photo) }
            }
            .onLongPressGesture(minimumDuration: 0.3) {
                if !selecting { selecting = true }
                toggle(photo)
            }
    }

    private func header(_ section: PhotoSection) -> some View {
        HStack {
            Text(section.title)
                .font(.title3.weight(.semibold))
            Spacer()
            if selecting {
                let allSelected = section.photos.allSatisfy { selection.contains($0.id) }
                Button {
                    if allSelected { section.photos.forEach { selection.remove($0.id) } }
                    else { section.photos.forEach { selection.insert($0.id) } }
                } label: {
                    Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(allSelected ? Color.accentColor : .secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private func toggle(_ photo: Photo) {
        if selection.contains(photo.id) { selection.remove(photo.id) }
        else { selection.insert(photo.id) }
    }

    private var pinch: some Gesture {
        MagnificationGesture()
            .onEnded { scale in
                if scale > 1.15 { columns = max(2, columns - 1) }
                else if scale < 0.85 { columns = min(6, columns + 1) }
            }
    }

    private func scrubber(height: CGFloat, proxy: ScrollViewProxy) -> some View {
        let usable = max(height - 140, 1)
        return ZStack(alignment: .topTrailing) {
            if scrubbing {
                Text(scrubLabel)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.thinMaterial, in: Capsule())
                    .shadow(radius: 4)
                    .offset(x: -46, y: scrubY + 70)
                    .fixedSize()
            }
            RoundedRectangle(cornerRadius: 6)
                .fill(scrubbing ? Color.accentColor : Color.secondary.opacity(0.45))
                .frame(width: 6, height: 44)
                .padding(.trailing, 5)
                .offset(y: scrubY + 70 - 22)
        }
        .frame(width: 60, height: height, alignment: .topTrailing)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let y = min(max(value.location.y - 70, 0), usable)
                    scrubY = y
                    scrubbing = true
                    let frac = y / usable
                    let idx = min(sections.count - 1, max(0, Int(frac * CGFloat(sections.count))))
                    scrubLabel = sections[idx].title
                    proxy.scrollTo(sections[idx].id, anchor: .top)
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.3)) { scrubbing = false }
                }
        )
    }
}

struct ThumbnailCell: View {
    let store: PhotoStore
    let photo: Photo
    var isSelected = false
    var showSelection = false
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(Color(.systemGray5))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
                if photo.favorite && !showSelection {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                            Spacer()
                        }
                    }
                    .padding(5)
                }
                if showSelection {
                    Color.black.opacity(isSelected ? 0.35 : 0)
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? Color.accentColor : .white)
                                .background(Circle().fill(.black.opacity(0.25)))
                                .padding(5)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(isSelected && showSelection ? 0.88 : 1)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .task(id: photo.id) {
            image = await store.thumbnail(for: photo)
        }
    }
}

/// A generic photo screen (Favorites, a month album, search results, Trash).
@MainActor
struct PhotoCollectionScreen: View {
    let store: PhotoStore
    let title: String
    let photos: [Photo]
    var isTrash = false
    @Binding var navHidden: Bool

    @State private var columns = 3
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var openID: String?

    private var sections: [PhotoSection] { store.dailySections(photos) }

    var body: some View {
        Group {
            if photos.isEmpty {
                ContentUnavailableView(
                    isTrash ? "Trash is empty" : "Nothing here yet",
                    systemImage: isTrash ? "trash" : "photo.on.rectangle.angled")
            } else {
                PhotoGrid(store: store, sections: sections, columns: $columns,
                          allowPinch: true, showScrubber: false,
                          selecting: $selecting, selection: $selection) { photo in
                    openID = photo.id
                }
            }
        }
        .navigationTitle(selecting ? "\(selection.count) selected" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !photos.isEmpty {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle(); selection = []
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting { actionBar }
        }
        .onChange(of: selecting) { _, v in navHidden = v }
        .onDisappear { navHidden = false }
        .fullScreenCover(item: Binding(get: { openID.map { IDBox(id: $0) } }, set: { openID = $0?.id })) { box in
            PhotoDetailView(store: store, photos: photos, initialID: box.id, mode: isTrash ? .trash : .normal)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 24) {
            if isTrash {
                action("Restore", "arrow.uturn.backward") {
                    let items = selthe; finishSelect(); Task { await store.restore(items) }
                }
                action("Delete", "trash", destructive: true) {
                    let items = selthe; finishSelect(); Task { await store.permanentlyDelete(items) }
                }
            } else {
                action("Favorite", "heart") {
                    let items = selthe; finishSelect()
                    Task { for p in items { await store.setFavorite(p, true) } }
                }
                action("Remove", "trash", destructive: true) {
                    let items = selthe; finishSelect(); Task { await store.trash(items) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var selthe: [Photo] { photos.filter { selection.contains($0.id) } }
    private func finishSelect() { selecting = false; selection = [] }

    private func action(_ label: String, _ icon: String, destructive: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(role: destructive ? .destructive : nil, action: run) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.caption)
            }
        }
        .disabled(selection.isEmpty)
    }
}

/// Lets an optional String id drive a fullScreenCover(item:).
struct IDBox: Identifiable { let id: String }
