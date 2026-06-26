import SwiftUI
import SwiftData

/// Ordre de tri de la grille d'albums.
enum AlbumSortOrder: String, CaseIterable, Identifiable {
    case titre, artiste, annee, recent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .titre:   "Titre"
        case .artiste: "Artiste"
        case .annee:   "Année"
        case .recent:  "Ajouts récents"
        }
    }
    var systemImage: String {
        switch self {
        case .titre:   "textformat"
        case .artiste: "music.mic"
        case .annee:   "calendar"
        case .recent:  "clock"
        }
    }
    var descriptors: [SortDescriptor<Album>] {
        switch self {
        case .titre:   [SortDescriptor(\.title)]
        case .artiste: [SortDescriptor(\.artistNameSnapshot), SortDescriptor(\.title)]
        case .annee:   [SortDescriptor(\.year, order: .reverse), SortDescriptor(\.title)]
        case .recent:  [SortDescriptor(\.dateAdded, order: .reverse), SortDescriptor(\.title)]
        }
    }
}

/// Grille des albums (tri configurable). Mène au détail d'album (liste des morceaux).
struct AlbumsGridView: View {
    @Query private var albums: [Album]

    init(sort: AlbumSortOrder = .titre) {
        _albums = Query(sort: sort.descriptors)
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.l)]

    var body: some View {
        Group {
            if albums.isEmpty {
                LibraryEmptyState(title: "Aucun album", systemImage: "square.stack")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Spacing.xl) {
                        ForEach(albums) { album in
                            NavigationLink(value: album) {
                                AlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Spacing.l)
                }
            }
        }
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
    }
}

/// Détail d'un album : en-tête (pochette + métadonnées) puis liste ordonnée des morceaux.
struct AlbumDetailView: View {
    let album: Album
    @Environment(\.downloadManager) private var downloadManager
    @Environment(\.playerController) private var playerController
    @Environment(\.modelContext) private var context

    private var orderedTracks: [Track] {
        album.tracks.sorted {
            ($0.discNumber ?? 1, $0.trackNumber ?? 0, $0.title)
                < ($1.discNumber ?? 1, $1.trackNumber ?? 0, $1.title)
        }
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, Spacing.s)
            }
            Section {
                ForEach(Array(orderedTracks.enumerated()), id: \.element.id) { index, track in
                    TrackRowView(track: track, showsTrackNumber: true, showsMenu: true)
                        .contentShape(Rectangle())
                        .onTapGesture { playerController?.play(queue: orderedTracks, startAt: index) }
                        .trackContextMenu(track: track, context: context)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FavoriteButton(isFavorite: album.isFavorite, prominent: true) {
                    Favorites.toggle(album, context: context)
                }
            }
            if let downloadManager, album.server?.type != .local, !orderedTracks.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await downloadManager.enqueueAlbum(album) }
                    } label: {
                        Label("Télécharger l'album", systemImage: "arrow.down.circle")
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.l) {
            CoverArtView(path: album.coverArtRemotePath, server: album.server, seed: album.title)
                .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(album.title)
                    .font(Typo.displaySmall)
                    .foregroundStyle(Palette.texteIvoire)
                if let artist = album.artistNameSnapshot ?? album.artist?.name {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(metadataLine)
                    .font(Typo.technique)
                    .foregroundStyle(Palette.signalTeal)
                    .padding(.top, Spacing.xs)
                // Encodage d'origine (codec), sous les métadonnées : badge « FLAC », « ALAC », etc.
                if let encoding = encodingSummary {
                    Label(encoding, systemImage: "waveform")
                        .font(Typo.technique)
                        .foregroundStyle(Palette.fondNoir)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, 2)
                        .background(Palette.signalTeal, in: Capsule())
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var metadataLine: String {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        let count = album.tracks.count
        parts.append("\(count) titre\(count > 1 ? "s" : "")")
        let total = album.tracks.reduce(0) { $0 + $1.durationSeconds }
        if total > 0 { parts.append(total.asTrackDuration) }
        return parts.joined(separator: " · ")
    }

    /// Encodage(s) d'origine de l'album, dérivé du codec de chaque piste (`Track.format`).
    /// Renvoie « FLAC » pour un album homogène, « ALAC · FLAC · MP3 » s'il est hétérogène,
    /// `nil` si aucun format n'est connu.
    private var encodingSummary: String? {
        let distinct = Set(album.tracks.compactMap { track -> String? in
            guard let f = track.format?.trimmingCharacters(in: .whitespaces), !f.isEmpty else { return nil }
            return f.audioCodecLabel
        })
        guard !distinct.isEmpty else { return nil }
        return distinct.sorted().joined(separator: " · ")
    }
}

#Preview("Grille") {
    let container = SillonSchema.makeContainer(inMemory: true)
    PreviewData.populate(container.mainContext)
    return NavigationStack { AlbumsGridView() }
        .modelContainer(container)
}
