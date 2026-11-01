import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "play.rectangle.on.rectangle") }
            PlaylistsView()
                .tabItem { Label("Playlists", systemImage: "list.star") }
            FilesView()
                .tabItem { Label("Files", systemImage: "folder") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.orange)
    }
}

// MARK: - Library

private enum LibraryFilter: String, CaseIterable {
    case all = "All"
    case movies = "Movies"
    case shorts = "Shorts"
    case favorites = "Favorites"
}

struct LibraryView: View {
    @EnvironmentObject var library: VideoLibrary
    @EnvironmentObject var playlists: PlaylistStore

    @State private var searchText = ""
    @State private var filter: LibraryFilter = .all
    @State private var playingVideo: VideoItem?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var showingPicker = false
    @State private var renameVideo: VideoItem?
    @State private var renameText = ""
    @State private var videoToDelete: VideoItem?

    private var filteredVideos: [VideoItem] {
        var list = library.videos
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        switch filter {
        case .all: break
        case .movies: list = list.filter { $0.duration == 0 || $0.duration >= 300 }
        case .shorts: list = list.filter { $0.duration > 0 && $0.duration < 300 }
        case .favorites: list = list.filter { library.isFavorite($0) }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !library.continueWatching.isEmpty {
                        Text("Continue Watching")
                            .font(.headline)
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(library.continueWatching) { video in
                                    continueCard(video)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(LibraryFilter.allCases, id: \.self) { chip in
                                Button(chip.rawValue) { filter = chip }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(filter == chip ? Color.orange : Color.white.opacity(0.1))
                                    .foregroundColor(filter == chip ? .black : .white)
                                    .fontWeight(.semibold)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal)
                    }

                    LazyVStack(spacing: 0) {
                        ForEach(filteredVideos) { video in
                            videoRow(video)
                            Divider().background(Color.white.opacity(0.1))
                        }
                    }

                    if filteredVideos.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "film")
                                .font(.system(size: 44))
                                .foregroundColor(.gray)
                            Text("No videos here yet")
                                .font(.headline)
                            Text("Import a video from the Files app or tap Import below.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                            Button("Import Video") { showingPicker = true }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("PlayZen")
            .searchable(text: $searchText, prompt: "Search videos")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingPicker = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .sheet(item: $playingVideo) { video in
                PlayerView(video: video)
            }
            .sheet(isPresented: $showingPicker) {
                DocumentPicker(
                    onPick: { url in
                        showingPicker = false
                        if library.importFile(from: url) { library.refresh() }
                    },
                    onCancel: { showingPicker = false }
                )
            }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .alert("Rename Video", isPresented: Binding(
                get: { renameVideo != nil },
                set: { if !$0 { renameVideo = nil } }
            )) {
                TextField("New name", text: $renameText)
                Button("Rename") {
                    if let video = renameVideo {
                        _ = library.rename(video, to: renameText)
                    }
                    renameVideo = nil
                }
                Button("Cancel", role: .cancel) { renameVideo = nil }
            }
            .alert("Delete Video?", isPresented: Binding(
                get: { videoToDelete != nil },
                set: { if !$0 { videoToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let video = videoToDelete { _ = library.delete(video) }
                    videoToDelete = nil
                }
                Button("Cancel", role: .cancel) { videoToDelete = nil }
            } message: {
                Text("This removes the file from PlayZen. The original file in the Files app is not affected unless it was imported here.")
            }
            .onAppear { library.refresh() }
        }
    }

    private func continueCard(_ video: VideoItem) -> some View {
        Button { openVideo(video) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 160, height: 90)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                }
                Text(video.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .leading)
                if video.duration > 0 {
                    ProgressView(value: video.lastPosition, total: video.duration)
                        .tint(.orange)
                        .frame(width: 160)
                    Text("\(Format.time(video.lastPosition)) / \(Format.time(video.duration))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func videoRow(_ video: VideoItem) -> some View {
        Button { openVideo(video) } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 96, height: 56)
                    Image(systemName: video.isSample ? "sparkles" : "play.fill")
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if video.isSample {
                            Text("SAMPLE")
                                .font(.caption2).fontWeight(.bold)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.25))
                                .foregroundColor(.orange)
                                .clipShape(Capsule())
                        }
                        if video.duration > 0 {
                            Text(Format.time(video.duration))
                                .font(.caption).foregroundColor(.gray)
                        }
                        if video.fileSize != 0 {
                            Text(Format.fileSize(video.fileSize))
                                .font(.caption).foregroundColor(.gray)
                        }
                        if !video.playableInV1 && !video.isSample {
                            Text("MKV • v2")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(.yellow)
                        }
                    }
                    if video.lastPosition > 0 && video.duration > 0 {
                        ProgressView(value: video.lastPosition, total: video.duration)
                            .tint(.orange)
                    }
                }
                Spacer()
                Button {
                    library.toggleFavorite(video)
                } label: {
                    Image(systemName: library.isFavorite(video) ? "star.fill" : "star")
                        .foregroundColor(library.isFavorite(video) ? .yellow : .gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !video.isSample {
                Menu("Add to Playlist") {
                    ForEach(playlists.playlists) { playlist in
                        Button(playlist.name) { playlists.addVideo(video, to: playlist) }
                    }
                }
                Button("Rename") {
                    renameText = video.name
                    renameVideo = video
                }
                Button("Delete", role: .destructive) { videoToDelete = video }
            }
        }
    }

    private func openVideo(_ video: VideoItem) {
        if video.isSample {
            alertTitle = "Sample Video"
            alertMessage = "Ye sirf ek sample entry hai, isme koi real file nahi hai. Apni video import karo — Files tab > Import, ya Files app se video ko PlayZen folder me copy karo."
            showingAlert = true
            return
        }
        if !video.playableInV1 {
            alertTitle = "MKV Not Supported in v1"
            alertMessage = "MKV files AVPlayer se nahi chalte. MKV support v2 me VLCKit se aayega. MP4 / MOV / M4V v1 me fully supported hain."
            showingAlert = true
            return
        }
        playingVideo = video
    }
}

// MARK: - Playlists

struct PlaylistsView: View {
    @EnvironmentObject var library: VideoLibrary
    @EnvironmentObject var playlists: PlaylistStore

    @State private var showingCreate = false
    @State private var newName = ""
    @State private var renamePlaylist: Playlist?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                if playlists.playlists.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.star")
                            .font(.system(size: 44))
                            .foregroundColor(.gray)
                        Text("No playlists yet")
                            .font(.headline)
                        Text("Create a playlist, then add videos from the Library (long-press a video > Add to Playlist).")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                }
                ForEach(playlists.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .foregroundColor(.orange)
                            Text(playlist.name)
                            Spacer()
                            Text("\(playlist.videoFileNames.count) videos")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .swipeActions {
                        Button("Rename") {
                            renameText = playlist.name
                            renamePlaylist = playlist
                        }
                        .tint(.blue)
                        Button(role: .destructive) {
                            playlists.delete(playlist)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Playlist", isPresented: $showingCreate) {
                TextField("Playlist name", text: $newName)
                Button("Create") {
                    playlists.create(name: newName)
                    newName = ""
                }
                Button("Cancel", role: .cancel) { newName = "" }
            }
            .alert("Rename Playlist", isPresented: Binding(
                get: { renamePlaylist != nil },
                set: { if !$0 { renamePlaylist = nil } }
            )) {
                TextField("New name", text: $renameText)
                Button("Rename") {
                    if let p = renamePlaylist { playlists.rename(p, to: renameText) }
                    renamePlaylist = nil
                }
                Button("Cancel", role: .cancel) { renamePlaylist = nil }
            }
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var library: VideoLibrary
    @EnvironmentObject var playlists: PlaylistStore
    @State private var playingVideo: VideoItem?

    var body: some View {
        List {
            let items = playlists.videos(for: playlist, in: library)
            if items.isEmpty {
                Text("No videos in this playlist yet. Long-press a video in the Library > Add to Playlist.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.vertical, 24)
            }
            ForEach(items) { video in
                Button { playingVideo = video } label: {
                    HStack {
                        Image(systemName: "play.fill").foregroundColor(.orange)
                        Text(video.name).lineLimit(1)
                        Spacer()
                        if video.duration > 0 {
                            Text(Format.time(video.duration))
                                .font(.caption).foregroundColor(.gray)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        playlists.removeVideo(video, from: playlist)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(playlist.name)
        .fullScreenCover(item: $playingVideo) { video in
            PlayerView(video: video)
        }
    }
}

// MARK: - Files

struct FilesView: View {
    @EnvironmentObject var library: VideoLibrary

    @State private var files: [(name: String, size: Int64)] = []
    @State private var showingPicker = false
    @State private var renameFile: String?
    @State private var renameText = ""
    @State private var deleteFile: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Ye PlayZen ke Documents folder ki files hain. Files app > On My iPhone > PlayZen se bhi videos yahan copy kar sakte ho (UIFileSharingEnabled ON hai).")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Section("Files") {
                    if files.isEmpty {
                        Text("No files yet. Import a video to get started.")
                            .foregroundColor(.gray)
                    }
                    ForEach(files, id: \.name) { file in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.orange)
                            Text(file.name).lineLimit(1)
                            Spacer()
                            Text(Format.fileSize(file.size))
                                .font(.caption).foregroundColor(.gray)
                        }
                        .swipeActions {
                            Button("Rename") {
                                renameText = (file.name as NSString).deletingPathExtension
                                renameFile = file.name
                            }
                            .tint(.blue)
                            Button(role: .destructive) {
                                deleteFile = file.name
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            ShareLink(item: VideoLibrary.documentsDirectory.appendingPathComponent(file.name)) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Files")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import") { showingPicker = true }
                }
            }
            .sheet(isPresented: $showingPicker) {
                DocumentPicker(
                    onPick: { url in
                        showingPicker = false
                        _ = library.importFile(from: url)
                        loadFiles()
                    },
                    onCancel: { showingPicker = false }
                )
            }
            .alert("Rename File", isPresented: Binding(
                get: { renameFile != nil },
                set: { if !$0 { renameFile = nil } }
            )) {
                TextField("New name (without extension)", text: $renameText)
                Button("Rename") {
                    if let old = renameFile {
                        let ext = (old as NSString).pathExtension
                        let dest = VideoLibrary.documentsDirectory
                            .appendingPathComponent(renameText)
                            .appendingPathExtension(ext)
                        try? FileManager.default.moveItem(
                            at: VideoLibrary.documentsDirectory.appendingPathComponent(old),
                            to: dest)
                        library.refresh()
                        loadFiles()
                    }
                    renameFile = nil
                }
                Button("Cancel", role: .cancel) { renameFile = nil }
            }
            .alert("Delete File?", isPresented: Binding(
                get: { deleteFile != nil },
                set: { if !$0 { deleteFile = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let name = deleteFile {
                        try? FileManager.default.removeItem(
                            at: VideoLibrary.documentsDirectory.appendingPathComponent(name))
                        library.refresh()
                        loadFiles()
                    }
                    deleteFile = nil
                }
                Button("Cancel", role: .cancel) { deleteFile = nil }
            } message: {
                Text("This permanently deletes the file from PlayZen.")
            }
            .onAppear { loadFiles() }
        }
    }

    private func loadFiles() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: VideoLibrary.documentsDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles])) ?? []
        files = urls.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return (name: url.lastPathComponent, size: Int64(size))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
