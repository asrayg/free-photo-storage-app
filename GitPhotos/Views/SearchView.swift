import SwiftUI

/// Search tab — text/date lookup over the library, with quick suggestions when
/// the field is empty (Google Photos-style).
@MainActor
struct SearchView: View {
    let store: PhotoStore
    @Binding var navHidden: Bool

    @State private var query = ""

    private var results: [Photo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        if q == "favorite" || q == "favorites" {
            return store.favoritePhotos
        }
        return store.libraryPhotos.filter { photo in
            photo.filename.lowercased().contains(q)
            || PhotoSearch.dateText(photo.createdAt).contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    suggestions
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    PhotoCollectionScreen(store: store, title: "Results", photos: results, navHidden: $navHidden)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search by name, month, or year")
    }

    private var suggestions: some View {
        List {
            Section("Suggestions") {
                NavigationLink {
                    PhotoCollectionScreen(store: store, title: "Favorites", photos: store.favoritePhotos, navHidden: $navHidden)
                } label: {
                    Label("Favorites", systemImage: "heart.fill")
                }
            }
            if !store.monthSections(store.libraryPhotos).isEmpty {
                Section("Browse by month") {
                    ForEach(store.monthSections(store.libraryPhotos)) { month in
                        Button { query = month.title } label: {
                            HStack {
                                Label(month.title, systemImage: "calendar")
                                Spacer()
                                Text("\(month.photos.count)").foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

enum PhotoSearch {
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy EEEE"; return f
    }()
    /// Lowercased searchable date string, e.g. "june 2025 monday".
    static func dateText(_ date: Date) -> String {
        formatter.string(from: date).lowercased()
    }
}
