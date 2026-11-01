import Foundation
import Combine

// MARK: - VideoItem

/// One video file in the app's Documents folder.
/// `id` is the file name on purpose: it is stable across rescans,
/// so playlists and saved progress keep working after a refresh.
struct VideoItem: Identifiable, Codable, Equatable {
    var id: String { fileName }
    var fileName: String
    var duration: TimeInterval = 0
    var fileSize: Int64 = 0
    var lastPlayed: Date?
    var lastPosition: TimeInterval = 0

    var name: String {
        (fileName as NSString).deletingPathExtension
    }

    var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    /// A sample entry shown when the Library is empty. It has no file,
    /// so tapping it must show an Import prompt — never fake playback.
    var isSample: Bool { fileName.hasPrefix("sample:") }

    /// v1 truth: AVPlayer plays MP4 / MOV / M4V. MKV is listed in the
    /// Library but needs VLCKit (planned for v2) and will show an honest
    /// "MKV not supported in v1" alert instead of a black screen.
    var playableInV1: Bool {
        ["mp4", "mov", "m4v"].contains(fileExtension)
    }

    var url: URL? {
        guard !isSample else { return nil }
        return VideoLibrary.documentsDirectory.appendingPathComponent(fileName)
    }

    static func == (lhs: VideoItem, rhs: VideoItem) -> Bool {
        lhs.fileName == rhs.fileName
    }
}

// MARK: - VideoLibrary

final class VideoLibrary: ObservableObject {
    @Published private(set) var videos: [VideoItem] = []
    @Published private(set) var continueWatching: [VideoItem] = []

    static let documentsDirectory: URL =
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

    private let progressKey = "tojiplay.progress"
    private let favoritesKey = "tojiplay.favorites"
    private let supportedExtensions = ["mp4", "mov", "m4v", "mkv"]

    init() { refresh() }

    func refresh() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(
            at: Self.documentsDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles])) ?? []

        var items: [VideoItem] = []
        for url in files where supportedExtensions.contains(url.pathExtension.lowercased()) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            var item = VideoItem(fileName: url.lastPathComponent, fileSize: Int64(size))
            item.lastPosition = savedProgress()[url.lastPathComponent] ?? 0
            item.lastPlayed = item.lastPosition > 0 ? Date() : nil
            items.append(item)
        }
        items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if items.isEmpty {
            videos = sampleVideos()
            continueWatching = []
        } else {
            videos = items
            continueWatching = items
                .filter { $0.lastPosition > 5 }
                .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
                .prefix(10)
                .map { $0 }
        }
    }

    private func sampleVideos() -> [VideoItem] {
        [
            VideoItem(fileName: "sample:Big Buck Bunny", duration: 596, fileSize: 0),
            VideoItem(fileName: "sample:Sample Short Clip", duration: 120, fileSize: 0),
            VideoItem(fileName: "sample:Toji Highlights", duration: 240, fileSize: 0),
        ]
    }

    private func savedProgress() -> [String: TimeInterval] {
        UserDefaults.standard.dictionary(forKey: progressKey) as? [String: TimeInterval] ?? [:]
    }

    func saveProgress(for video: VideoItem, position: TimeInterval, duration: TimeInterval) {
        guard !video.isSample, position > 0 else { return }
        var progress = savedProgress()
        progress[video.fileName] = position
        UserDefaults.standard.set(progress, forKey: progressKey)
        updateDuration(for: video, duration: duration)
        if let index = videos.firstIndex(of: video) {
            videos[index].lastPosition = position
            videos[index].lastPlayed = Date()
            refreshContinueWatching()
        }
    }

    func progress(for video: VideoItem) -> TimeInterval {
        savedProgress()[video.fileName] ?? 0
    }

    func updateDuration(for video: VideoItem, duration: TimeInterval) {
        guard duration > 0, let index = videos.firstIndex(of: video) else { return }
        videos[index].duration = duration
    }

    func isFavorite(_ video: VideoItem) -> Bool {
        (UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []).contains(video.fileName)
    }

    func toggleFavorite(_ video: VideoItem) {
        var favs = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        if let i = favs.firstIndex(of: video.fileName) { favs.remove(at: i) }
        else { favs.append(video.fileName) }
        UserDefaults.standard.set(favs, forKey: favoritesKey)
        objectWillChange.send()
    }

    func clearContinueWatching() {
        UserDefaults.standard.removeObject(forKey: progressKey)
        refresh()
    }

    private func refreshContinueWatching() {
        continueWatching = videos
            .filter { $0.lastPosition > 5 }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
            .prefix(10)
            .map { $0 }
    }

    @discardableResult
    func importFile(from tempURL: URL) -> Bool {
        let fm = FileManager.default
        var dest = Self.documentsDirectory.appendingPathComponent(tempURL.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            let base = (tempURL.lastPathComponent as NSString).deletingPathExtension
            let ext = tempURL.pathExtension
            dest = Self.documentsDirectory.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        do {
            try fm.copyItem(at: tempURL, to: dest)
            refresh()
            return true
        } catch {
            print("PlayZen import failed: \(error)")
            return false
        }
    }

    @discardableResult
    func delete(_ video: VideoItem) -> Bool {
        guard let url = video.url else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            var progress = savedProgress()
            progress.removeValue(forKey: video.fileName)
            UserDefaults.standard.set(progress, forKey: progressKey)
            refresh()
            return true
        } catch {
            print("PlayZen delete failed: \(error)")
            return false
        }
    }

    @discardableResult
    func rename(_ video: VideoItem, to newName: String) -> Bool {
        guard let url = video.url else { return false }
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        let dest = Self.documentsDirectory
            .appendingPathComponent(clean)
            .appendingPathExtension(video.fileExtension)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            refresh()
            return true
        } catch {
            print("PlayZen rename failed: \(error)")
            return false
        }
    }
}

// MARK: - Playlists

struct Playlist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var videoFileNames: [String]
}

final class PlaylistStore: ObservableObject {
    @Published private(set) var playlists: [Playlist] = []
    private let key = "tojiplay.playlists"

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data)
        else { playlists = []; return }
        playlists = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func create(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        playlists.append(Playlist(id: UUID(), name: clean, videoFileNames: []))
        save()
    }

    func rename(_ playlist: Playlist, to newName: String) {
        guard let i = playlists.firstIndex(of: playlist) else { return }
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        playlists[i].name = clean
        save()
    }

    func delete(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        save()
    }

    func addVideo(_ video: VideoItem, to playlist: Playlist) {
        guard let i = playlists.firstIndex(of: playlist),
              !playlists[i].videoFileNames.contains(video.fileName) else { return }
        playlists[i].videoFileNames.append(video.fileName)
        save()
    }

    func removeVideo(_ video: VideoItem, from playlist: Playlist) {
        guard let i = playlists.firstIndex(of: playlist) else { return }
        playlists[i].videoFileNames.removeAll { $0 == video.fileName }
        save()
    }

    func videos(for playlist: Playlist, in library: VideoLibrary) -> [VideoItem] {
        playlist.videoFileNames.compactMap { name in
            library.videos.first { $0.fileName == name }
        }
    }
}

// MARK: - Settings

final class SettingsStore: ObservableObject {
    @Published var volumeBoostEnabled: Bool {
        didSet { UserDefaults.standard.set(volumeBoostEnabled, forKey: "tojiplay.volumeBoost") }
    }
    @Published var dualSubtitlesEnabled: Bool {
        didSet { UserDefaults.standard.set(dualSubtitlesEnabled, forKey: "tojiplay.dualSubtitles") }
    }
    @Published var pipEnabled: Bool {
        didSet { UserDefaults.standard.set(pipEnabled, forKey: "tojiplay.pipEnabled") }
    }
    @Published var autoResumeEnabled: Bool {
        didSet { UserDefaults.standard.set(autoResumeEnabled, forKey: "tojiplay.autoResume") }
    }
    @Published var darkModeEnabled: Bool {
        didSet { UserDefaults.standard.set(darkModeEnabled, forKey: "tojiplay.darkMode") }
    }
    @Published var subtitleSize: Int {
        didSet { UserDefaults.standard.set(subtitleSize, forKey: "tojiplay.subtitleSize") }
    }

    init() {
        let d = UserDefaults.standard
        volumeBoostEnabled = d.object(forKey: "tojiplay.volumeBoost") as? Bool ?? true
        dualSubtitlesEnabled = d.object(forKey: "tojiplay.dualSubtitles") as? Bool ?? true
        pipEnabled = d.object(forKey: "tojiplay.pipEnabled") as? Bool ?? true
        autoResumeEnabled = d.object(forKey: "tojiplay.autoResume") as? Bool ?? true
        darkModeEnabled = d.object(forKey: "tojiplay.darkMode") as? Bool ?? true
        subtitleSize = d.object(forKey: "tojiplay.subtitleSize") as? Int ?? 1
    }

    var subtitleFontSize: CGFloat {
        switch subtitleSize { case 0: return 14; case 2: return 24; default: return 18 }
    }
}

// MARK: - Subtitles (SRT)

struct SubtitleCue: Identifiable {
    let id = UUID()
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

enum SRTParser {
    static func loadCues(for video: VideoItem) -> [SubtitleCue] {
        let srtURL = VideoLibrary.documentsDirectory
            .appendingPathComponent(video.name)
            .appendingPathExtension("srt")
        guard let content = try? String(contentsOf: srtURL, encoding: .utf8) else { return [] }
        return parse(content)
    }

    static func parse(_ content: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard lines.count >= 2 else { continue }
            let timeLine = lines[1]
            let parts = timeLine.components(separatedBy: " --> ")
            guard parts.count == 2,
                  let start = timecode(parts[0]),
                  let end = timecode(parts[1]) else { continue }
            let text = lines.dropFirst(2).joined(separator: "\n")
            cues.append(SubtitleCue(start: start, end: end, text: text))
        }
        return cues.sorted { $0.start < $1.start }
    }

    static func timecode(_ s: String) -> TimeInterval? {
        let clean = s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        let parts = clean.components(separatedBy: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let sec = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + sec
    }

    static func sampleHindiLine(for time: TimeInterval) -> String {
        let lines = [
            "नमस्ते, PlayZen में आपका स्वागत है",
            "यह वीडियो मुफ्त में चल रहा है",
            "गति, वॉल्यूम और सबटाइटल — सब फ्री हैं",
            "आगे बढ़ने के लिए स्क्रीन पर टैप करें",
            "धन्यवाद, वीडियो देखने के लिए",
        ]
        let index = Int(time / 8) % lines.count
        return lines[index]
    }

    static func sampleEnglishLine(for time: TimeInterval) -> String {
        let lines = [
            "Welcome to PlayZen",
            "This video is playing for free",
            "Speed, volume and subtitles — all free",
            "Tap the screen for controls",
            "Thanks for watching",
        ]
        let index = Int(time / 8) % lines.count
        return lines[index]
    }
}

// MARK: - Formatting helpers

enum Format {
    static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func fileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1000) }
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1000)
    }
}
