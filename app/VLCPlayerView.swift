import SwiftUI
import MobileVLCKit

// MARK: - VLC player (MKV) — v1.1.0
//
// AVPlayer cannot play MKV, so MKV files use VLCMediaPlayer
// (MobileVLCKit 3.7.3 via CocoaPods). MP4 / MOV / M4V keep using
// the AVPlayer PlayerView.
//
// API notes (checked against the VLCKit headers):
//   VLCMediaPlayer: play(), pause(), stop(), .rate (Float),
//     .time (VLCTime, ms — set to seek), .isPlaying,
//     .state (VLCMediaPlayerState: .playing/.paused/.ended/.error),
//     .drawable (the UIView), .media (VLCMedia),
//     .audio.volume (Int, libvlc scale 0-200 — >100 is a REAL boost),
//     .videoSubTitlesNames / .currentVideoSubTitleIndex,
//     .addPlaybackSlave(_:type:enforce:) for a sidecar .srt.
//   VLCMedia(url:) / VLCMedia(url:) opens a local file.
//   VLCTime(int:) builds a time in milliseconds; .intValue reads it.
//   VLCMedia.length is a VLCTime (ms) once the media is parsed.
//
// Honest limits of this player in v2:
//   - PiP is NOT available (VLCKit 3.7 has no AVPictureInPictureController
//     path) — the PiP button is hidden, not faked.
//   - Chapters are time-based (same as PlayerView), not MKV chapter markers.
//   - Dual subtitles are NOT here — one VLC subtitle track at a time
//     (embedded track, or the sidecar .srt next to the video).

final class VLCPlayerController: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let videoView = UIView()
    private(set) var player = VLCMediaPlayer()

    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying = false
    @Published var ended = false
    @Published var subtitleTrackNames: [String] = []
    @Published var subtitleTrackIndexes: [Int32] = []

    private var timer: Timer?
    private var startAt: TimeInterval = 0
    private var didSeekToStart = false
    private var srtURL: URL?

    override init() {
        super.init()
        player.delegate = self
    }

    func setup(url: URL, startAt: TimeInterval, rate: Float, volumeBoost: Double) {
        self.startAt = startAt
        // Sidecar subtitle: same name as the video, .srt extension.
        let srt = url.deletingPathExtension().appendingPathExtension("srt")
        if FileManager.default.fileExists(atPath: srt.path) { srtURL = srt }

        player.drawable = videoView
        player.media = VLCMedia(url: url)
        player.play()
        player.rate = rate
        applyVolume(volumeBoost)
        isPlaying = true

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let ms = player.time?.intValue ?? 0
        currentTime = TimeInterval(ms) / 1000

        let lengthMs = player.media?.length?.intValue ?? 0
        if lengthMs > 0 {
            duration = TimeInterval(lengthMs) / 1000
        } else if let remainingMs = player.remainingTime?.intValue, remainingMs > 0 {
            duration = currentTime + TimeInterval(remainingMs) / 1000
        }

        isPlaying = player.isPlaying
        if player.state == .ended {
            ended = true
            isPlaying = false
        }

        // Resume where the user left off, once playback has started.
        if !didSeekToStart, startAt > 5, currentTime > 0.5 {
            player.time = VLCTime(int: Int32(startAt * 1000))
            didSeekToStart = true
        }

        // Attach the sidecar .srt once, after playback starts.
        if let srt = srtURL {
            _ = player.addPlaybackSlave(srt, type: .subtitle, enforce: true)
            srtURL = nil
        }

        // Embedded subtitle tracks appear once the media is parsed.
        if subtitleTrackNames.isEmpty,
           let names = player.videoSubTitlesNames as? [String], !names.isEmpty {
            subtitleTrackNames = names
            if let indexes = player.videoSubTitlesIndexes as? [NSNumber] {
                subtitleTrackIndexes = indexes.map { $0.int32Value }
            }
        }
    }

    func setPlaying(_ play: Bool) {
        if play {
            player.play()
        } else {
            player.pause()
        }
        isPlaying = play
    }

    func setRate(_ rate: Float) {
        player.rate = rate
        if isPlaying { player.play() } // rate only takes effect while playing
    }

    func seek(to seconds: TimeInterval) {
        let target = min(max(seconds, 0), duration > 0 ? duration : seconds)
        player.time = VLCTime(int: Int32(target * 1000))
        currentTime = target
    }

    func skip(by seconds: TimeInterval) { seek(to: currentTime + seconds) }

    /// libvlc volume is 0-200 (100 = nominal). Unlike AVPlayer, >100%
    /// here is a REAL boost, not just a badge.
    func applyVolume(_ boost: Double) {
        player.audio?.volume = Int32(boost)
    }

    /// -1 disables subtitles (libvlc convention).
    func setSubtitleTrack(index: Int32) {
        player.currentVideoSubTitleIndex = index
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player.stop()
    }

    // MARK: VLCMediaPlayerDelegate

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        if player.state == .ended {
            ended = true
            isPlaying = false
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        tick()
    }
}

// MARK: - UIView wrapper

struct VLCVideoView: UIViewRepresentable {
    let controller: VLCPlayerController

    func makeUIView(context: Context) -> UIView {
        controller.videoView.backgroundColor = .black
        return controller.videoView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        controller.player.drawable = uiView
    }
}

// MARK: - Player screen (same layout as PlayerView, VLC engine)

struct VLCPlayerView: View {
    let video: VideoItem

    @EnvironmentObject private var library: VideoLibrary
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var controller = VLCPlayerController()

    @State private var showControls = true
    @State private var showSpeedSheet = false
    @State private var showSubtitlesSheet = false
    @State private var showChaptersSheet = false
    @State private var subtitlesOn = true
    @State private var selectedSubtitleIndex: Int32 = 0
    @State private var didSetup = false

    private var startPosition: TimeInterval {
        guard settings.autoResume, video.lastPosition > 5,
              video.duration > 0, video.lastPosition < video.duration - 10
        else { return 0 }
        return video.lastPosition
    }

    private var durationBasedChapters: [(String, TimeInterval)] {
        let d = controller.duration
        guard d > 0 else { return [] }
        return [
            ("Intro", 0),
            ("Part 1", d * 0.25),
            ("Midpoint", d * 0.5),
            ("Part 2", d * 0.75),
            ("Finale", max(d - 60, d * 0.9)),
        ]
    }

    private func saveProgress() {
        guard controller.duration > 0, controller.currentTime > 0 else { return }
        library.saveProgress(for: video, position: controller.currentTime, duration: controller.duration)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VLCVideoView(controller: controller)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showControls.toggle() }
                }

            if showControls {
                controlsOverlay
            }

            if controller.duration == 0 {
                ProgressView("Loading MKV…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .onAppear {
            guard !didSetup, let url = video.url else { return }
            didSetup = true
            controller.setup(
                url: url,
                startAt: startPosition,
                rate: Float(settings.playbackSpeed),
                volumeBoost: settings.volumeBoost
            )
        }
        .onDisappear {
            saveProgress()
            controller.stop()
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
        .onChange(of: controller.ended) { _, ended in
            if ended {
                saveProgress()
                withAnimation { showControls = true }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showControls)
        .sheet(isPresented: $showSpeedSheet) { speedSheet }
        .sheet(isPresented: $showSubtitlesSheet) { subtitlesSheet }
        .sheet(isPresented: $showChaptersSheet) { chaptersSheet }
    }

    // MARK: - Controls

    private var controlsOverlay: some View {
        VStack {
            topBar
            Spacer()
            centerControls
            Spacer()
            bottomBar
        }
        .padding()
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.title2).foregroundStyle(.white)
                    .padding(8).background(.black.opacity(0.5)).clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(video.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 6) {
                    Text("VLC • MKV").font(.caption2).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange).foregroundStyle(.black).clipShape(Capsule())
                    if controller.isPlaying {
                        Text("Playing").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            Spacer()
            // NOTE: no PiP button here — PiP is AVPlayer-only in v2.
            // VLCKit 3.7 has no Picture-in-Picture path, so we hide it
            // instead of showing a fake one.
        }
    }

    private var centerControls: some View {
        HStack(spacing: 48) {
            Button { controller.skip(by: -10) } label: {
                Image(systemName: "gobackward.10")
                    .font(.largeTitle).foregroundStyle(.white)
            }
            Button {
                controller.setPlaying(!controller.isPlaying)
            } label: {
                Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64)).foregroundStyle(.white)
            }
            Button { controller.skip(by: 10) } label: {
                Image(systemName: "goforward.10")
                    .font(.largeTitle).foregroundStyle(.white)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(timeString(controller.currentTime))
                Slider(
                    value: Binding(
                        get: { controller.currentTime },
                        set: { controller.seek(to: $0) }
                    ),
                    in: 0...(controller.duration > 0 ? controller.duration : 1)
                )
                .tint(.orange)
                Text(timeString(controller.duration))
            }
            .font(.caption).foregroundStyle(.white)

            HStack(spacing: 16) {
                Button("\(settings.playbackSpeed, specifier: "%.2g")×") {
                    showSpeedSheet = true
                }
                .buttonStyle(.bordered).tint(.orange)

                Button { showSubtitlesSheet = true } label: {
                    Label("Subtitles", systemImage: "captions.bubble")
                }
                .buttonStyle(.bordered).tint(.orange)

                Button { showChaptersSheet = true } label: {
                    Label("Chapters", systemImage: "list.bullet")
                }
                .buttonStyle(.bordered).tint(.orange)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill").foregroundStyle(.white)
                    Slider(
                        value: Binding(
                            get: { settings.volumeBoost },
                            set: { newValue in
                                settings.volumeBoost = newValue
                                controller.applyVolume(newValue)
                            }
                        ),
                        in: 0...200
                    )
                    .frame(width: 90).tint(.orange)
                    Text("\(Int(settings.volumeBoost))%")
                        .font(.caption).foregroundStyle(.white)
                    if settings.volumeBoost > 100 {
                        Text("BOOST").font(.caption2).bold()
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.orange).foregroundStyle(.black).clipShape(Capsule())
                    }
                }

                Button {
                    let value = UIInterfaceOrientation.landscapeRight.rawValue
                    UIDevice.current.setValue(value, forKey: "orientation")
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundStyle(.white)
                }
            }
            .font(.subheadline)
        }
    }

    // MARK: - Sheets

    private var speedSheet: some View {
        NavigationStack {
            List {
                ForEach([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0], id: \.self) { speed in
                    Button {
                        settings.playbackSpeed = speed
                        controller.setRate(Float(speed))
                        showSpeedSheet = false
                    } label: {
                        HStack {
                            Text("\(speed, specifier: "%.2g")×")
                            if speed == settings.playbackSpeed {
                                Spacer()
                                Image(systemName: "checkmark").foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Playback Speed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSpeedSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var subtitlesSheet: some View {
