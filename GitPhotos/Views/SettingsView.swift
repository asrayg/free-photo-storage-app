import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Bindable var store: PhotoStore
    @State private var showAddAccount = false

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Primary GitHub user", value: store.primary.login)
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

            storageSection

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
        .sheet(isPresented: $showAddAccount) {
            AddAccountView(store: store)
        }
    }

    private var storageSection: some View {
        Section {
            ForEach(store.storageByAccount) { usage in
                DisclosureGroup {
                    if usage.repos.isEmpty {
                        Text("No photos stored here yet.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(usage.repos, id: \.name) { repo in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(repo.name).font(.caption.monospaced())
                                Spacer()
                                Text(Self.byteFormatter.string(fromByteCount: repo.bytes))
                                    .foregroundStyle(.secondary).font(.caption)
                            }
                            ProgressView(value: Double(repo.bytes), total: Double(PhotoStore.repoByteCap))
                        }
                        .padding(.vertical, 2)
                    }
                    if usage.account.login != store.primary.login {
                        Button("Remove this account", role: .destructive) {
                            store.removeStorageAccount(usage.account.login)
                        }
                        .font(.caption)
                    }
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(usage.account.login).font(.subheadline.weight(.medium))
                                if usage.account.login == store.primary.login {
                                    Text("PRIMARY").font(.caption2.bold())
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(.tint.opacity(0.2), in: Capsule())
                                }
                            }
                            Text(Self.byteFormatter.string(fromByteCount: usage.bytes))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Button {
                showAddAccount = true
            } label: {
                Label("Add storage account", systemImage: "plus.circle")
            }
        } header: {
            Text("Storage accounts")
        } footer: {
            Text("Photos are stored in private repos (each capped at 4.5 GB) and new repos are created automatically as you fill up. Add more GitHub accounts to spread your library across them — new photos go to whichever account has the most room. The primary account holds the index and can't be removed.")
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()
}

/// Sheet for adding an additional GitHub storage account by token.
@MainActor
struct AddAccountView: View {
    let store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showTokenHelp = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("ghp_…", text: $token)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    HStack {
                        Text("Token for the new account")
                        Spacer()
                        Button {
                            showTokenHelp = true
                        } label: {
                            Label("How to get a token", systemImage: "info.circle")
                                .font(.caption).textCase(nil)
                        }
                    }
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else {
                        Text("Sign in to a different GitHub account in your browser first, then generate a token there with the repo scope.")
                    }
                }

                Section {
                    Button {
                        add()
                    } label: {
                        if isWorking {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Add account").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(token.isEmpty || isWorking)
                }
            }
            .navigationTitle("Add storage account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showTokenHelp) { TokenHelpView() }
        }
    }

    private func add() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await store.addStorageAccount(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
