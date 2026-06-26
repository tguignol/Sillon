import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = AddServerViewModel()
    @State private var isPickingFolder = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Type de serveur") {
                    Picker("Type", selection: $viewModel.serverType) {
                        ForEach(ServerType.allCases) { type in
                            Label {
                                Text(type.displayName)
                            } icon: {
                                typeIcon(type)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                switch viewModel.serverType {
                case .jellyfin:
                    jellyfinSection
                case .subsonic:
                    subsonicSection
                case .local:
                    localSection
                }

                Section {
                    connectionTestRow
                } footer: {
                    Text("Le bouton Enregistrer ne s'active qu'après un test de connexion réussi.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Ajouter un serveur")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        viewModel.discardDraft()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        do {
                            try viewModel.save(in: modelContext)
                            dismiss()
                        } catch {
                            viewModel.connectionTest = .failure(error.localizedDescription)
                        }
                    }
                    .disabled(!viewModel.canSave || !viewModel.isConnectionVerified)
                }
            }
        }
    }

    /// Icône de type pour le sélecteur : logo Jellyfin / vinyle Navidrome (cf. `ServerMarks`), mais
    /// symbole SF pour les fichiers locaux (pas de logo de marque).
    @ViewBuilder private func typeIcon(_ type: ServerType) -> some View {
        switch type {
        case .jellyfin: JellyfinMark().frame(width: 22, height: 22)
        case .subsonic:  NavidromeMark().frame(width: 22, height: 22)
        case .local:    Image(systemName: type.systemImageName)
        }
    }

    @ViewBuilder private var jellyfinSection: some View {
        Section("Connexion Jellyfin") {
            TextField("Nom (affiché dans l'app)", text: $viewModel.name)
            TextField("Adresse du serveur (https://...)", text: $viewModel.baseURLString)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            TextField("Nom d'utilisateur", text: $viewModel.username)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            SecureField("Mot de passe", text: $viewModel.password)
        }
    }

    @ViewBuilder private var subsonicSection: some View {
        Section {
            TextField("Nom (affiché dans l'app)", text: $viewModel.name)
            TextField("Adresse du serveur (https://...)", text: $viewModel.baseURLString)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            TextField("Nom d'utilisateur", text: $viewModel.username)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            Picker("Authentification", selection: $viewModel.subsonicAuthMode) {
                ForEach(AddServerViewModel.SubsonicAuthMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch viewModel.subsonicAuthMode {
            case .password:
                SecureField("Mot de passe", text: $viewModel.password)
            case .tokenAndSalt:
                TextField("Jeton (token)", text: $viewModel.subsonicToken)
                TextField("Sel (salt)", text: $viewModel.subsonicSalt)
            }
        } header: {
            Text("Connexion Navidrome / Subsonic")
        } footer: {
            Text("Le mode \"Jeton + sel\" évite de stocker votre mot de passe : si votre serveur le permet, calculez vous-même le jeton (MD5 du mot de passe suivi du sel) et indiquez-le ici avec le sel choisi.")
        }
    }

    @ViewBuilder private var localSection: some View {
        Section {
            TextField("Nom (affiché dans l'app)", text: $viewModel.name)
            Button {
                isPickingFolder = true
            } label: {
                HStack {
                    Text(viewModel.localFolderDisplayName ?? "Choisir un dossier…")
                        .foregroundStyle(viewModel.localFolderDisplayName == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "folder.badge.plus")
                }
            }
            .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    viewModel.didPickLocalFolder(url)
                case .failure(let error):
                    viewModel.connectionTest = .failure(error.localizedDescription)
                }
            }
        } header: {
            Text("Dossier local")
        } footer: {
            Text("Le contenu de ce dossier sera analysé pour construire votre bibliothèque (artistes, albums, titres) à partir de son arborescence et des métadonnées des fichiers.")
        }
    }

    @ViewBuilder private var connectionTestRow: some View {
        Button {
            Task { await viewModel.testConnection() }
        } label: {
            HStack {
                Text(viewModel.serverType == .local ? "Vérifier l'accès au dossier" : "Tester la connexion")
                Spacer()
                if viewModel.isTesting { ProgressView() }
            }
        }
        .disabled(!viewModel.canSave || viewModel.isTesting)

        switch viewModel.connectionTest {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .idle, .testing:
            EmptyView()
        }
    }
}

#Preview {
    AddServerView()
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
