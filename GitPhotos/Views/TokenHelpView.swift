import SwiftUI

/// Explains how to create a GitHub personal access token. Shown as a modal from
/// the login screen's info button and the "add storage account" flow.
struct TokenHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    step(1, "Open GitHub → Settings → Developer settings.")
                    step(2, "Choose Personal access tokens → Tokens (classic).")
                    step(3, "Generate new token (classic). Name it anything, e.g. \"GitPhotos\".")
                    step(4, "Under Select scopes, check the **repo** box (full control of private repositories).")
                    step(5, "Generate the token and copy it — GitHub shows it only once.")
                    step(6, "Paste it back in GitPhotos.")
                }
                Section {
                    Link(destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=GitPhotos")!) {
                        Label("Open the token page on GitHub", systemImage: "arrow.up.forward.square")
                    }
                } footer: {
                    Text("The link pre-selects the repo scope for you. Your token is stored only in this device's Keychain — GitPhotos never sends it anywhere except GitHub.")
                }
            }
            .navigationTitle("Getting a token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.tint))
            Text(.init(text))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}
