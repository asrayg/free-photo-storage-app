import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Bindable var store: PhotoStore

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("GitHub user", value: store.client.username)
                LabeledContent("Photos", value: "\(store.manifest.photos.count)")
                LabeledContent("Total storage", value: Self.byteFormatter.string(fromByteCount: store.totalBytes))
            }

            Section {
                Toggle("Auto-sync from Photos", isOn: Binding(
                    get: { store.sync.enabled },
                    set: { store.sync.enabled = $0 }))
                if store.sync.access == .denied {
                    Text("Photo access is off. Enable it in iOS Settings → Privacy → Photos.")
                        .font(.footnote).foregroundStyle(.red)
                } else if store.sync.isSyncing {
                    HStack { ProgressView(); Text("Syncing…").foregroundStyle(.secondary) }
                }
            } header: {
                Text("Auto-sync")
            } footer: {
                Text("When on, new photos you take are uploaded to GitHub automatically. The first time, your whole library is backed up — this can take a while and uses GitHub's hourly API limit (~1,500 photos/hour).")
            }

            Section {
                NavigationLink {
                    PongView()
                } label: {
                    Label("Photon Pong", systemImage: "gamecontroller")
                }
            } header: {
                Text("Arcade")
            }

            Section {
                ForEach(store.manifest.repos, id: \.name) { repo in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(repo.name).font(.subheadline.monospaced())
                            Spacer()
                            Text(Self.byteFormatter.string(fromByteCount: repo.bytes))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        ProgressView(value: Double(repo.bytes), total: Double(PhotoStore.repoByteCap))
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Storage shards")
            } footer: {
                Text("Each shard is a private GitHub repo capped at 4.5 GB. A new one is created automatically when the current one fills up.")
            }

            Section {
                Button("Clear local image cache") {
                    Task { await ImageCache.shared.clearAll() }
                }
                Button("Sign out", role: .destructive) {
                    appState.signOut()
                }
            }
        }
        .navigationTitle("Settings")
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()
}
