import SwiftUI

/// The "Collections" tab — Google Photos' Library equivalent: Favorites, Trash,
/// month albums, plus account/storage settings.
@MainActor
struct CollectionsView: View {
    let store: PhotoStore
    @Binding var navHidden: Bool

    private var months: [PhotoSection] { store.monthSections(store.libraryPhotos) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PhotoCollectionScreen(store: store, title: "Favorites", photos: store.favoritePhotos, navHidden: $navHidden)
                    } label: {
                        row("Favorites", "heart.fill", .pink, count: store.favoritePhotos.count)
                    }
                    NavigationLink {
                        PhotoCollectionScreen(store: store, title: "Trash", photos: store.trashedPhotos, isTrash: true, navHidden: $navHidden)
                    } label: {
                        row("Trash", "trash.fill", .gray, count: store.trashedPhotos.count)
                    }
                }

                if !months.isEmpty {
                    Section("Albums by month") {
                        ForEach(months) { month in
                            NavigationLink {
                                PhotoCollectionScreen(store: store, title: month.title, photos: month.photos, navHidden: $navHidden)
                            } label: {
                                MonthRow(store: store, month: month)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView(store: store)
                    } label: {
                        Label("Settings & storage", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Collections")
            .listStyle(.insetGrouped)
        }
    }

    private func row(_ title: String, _ icon: String, _ color: Color, count: Int) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color, in: RoundedRectangle(cornerRadius: 9))
            Text(title)
            Spacer()
            Text("\(count)").foregroundStyle(.secondary)
        }
    }
}

/// A month album row with a thumbnail of its most recent photo.
struct MonthRow: View {
    let store: PhotoStore
    let month: PhotoSection
    @State private var image: UIImage?

    var body: some View {
        HStack {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color(.systemGray5)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(month.title)
                Text("\(month.photos.count) photo\(month.photos.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: month.photos.first?.id) {
            if let first = month.photos.first {
                image = await store.thumbnail(for: first)
            }
        }
    }
}
