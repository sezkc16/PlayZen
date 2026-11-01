import SwiftUI
import AVKit
import AVFoundation

/// The core player screen. All features here are FREE — there is no
/// paywall code anywhere in PlayZen.
/// NOTE on "Volume Boost": AVPlayer.volume caps at 1.0, so the slider
/// maps 0–100% to volume 0–1.0. Above 100% the player stays at full
/// volume and shows a "Boost" badge — true >100% loudness needs audio
/// processing (AVAudioUnit, planned v2) and is NOT faked silently.
struct PlayerView: View {
    let video: VideoItem

    @EnvironmentObject var library: VideoLibrary
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var showControls = true
    @State private var hideWorkItem: DispatchWorkItem?
    @State private var speed: Double = 1.0
    @State private var showSpeedSheet = false
    @State private var showChapters = false
    @State private var showSubtitleSettings = false
    @State private var volumeBoost: Double = 100
    @State private var subtitlesOn = true
    @State private var cues: [SubtitleCue] = []
    @State private var pipController: AVPictureInPictureController?
    @State private var pipLayer: AVPlayerLayer?
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?

    private let speedOptions: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3]

    private var currentCue: SubtitleCue? {
        cues.first { currentTime >= $0.start && currentTime <= $0.end }
    }

    private var englishLine: String? {
        guard subtitlesOn else { return nil }
        if let cue = currentCue { return cue.text }
        if cues.isEmpty { return SRTParser.sampleEnglishLine(for: currentTime) }
        return nil
    }

    private var hindiLine: String? {
        guard subtitlesOn, settings.dualSubtitlesEnabled else { return nil }
        if currentCue != nil {
            return SRTParser.sampleHindiLine(for: currentTime)
        }
        if cues.isEmpty { return SRTParser.sampleHindiLine(for: currentTime) }
        return nil
    }

    private var chapters: [(title: String, time: TimeInterval)] {
        guard duration > 0 else {
            return [("Intro", 0), ("Main", 0), ("Finale", 0)]
        }
        return [
            ("Intro", 0),
            ("Main", duration * 0.25),
            ("Midpoint", duration * 0.5),
            ("Finale", duration * 0.75),
        ]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture { toggleControls() }
            } else {
                ProgressView("Loading video…")
                    .tint(.white)
            }

            if let english = englishLine {
                VStack(spacing: 2) {
                    Spacer()
                    Text(english)
                        .font(.system(size: settings.subtitleFontSize, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 4, x: 0, y: 1)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    if let hindi = hindiLine {
                        Text(hindi)
                            .font(.system(size: settings.subtitleFontSize - 2, weight: .regular))
                            .foregroundColor(.yellow)
                            .shadow(color: .black, radius: 4, x: 0, y: 1)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, showControls ? 150 : 40)
            }

            if showControls {
                controlsOverlay
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { teardownPlayer() }
        .sheet(isPresented: $showSpeedSheet) { speedSheet }
        .sheet(isPresented: $showChapters) { chaptersSheet }
        .sheet(isPresented: $showSubtitleSettings) { subtitleSheet }
        .alert("PlayZen", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var controlsOverlay: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                Text(video.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.white)
                Spacer()
                Button { startPiP() } label: {
                    Image(systemName: "pip.enter")
                        .font(.title3)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .disabled(!settings.pipEnabled)
                .opacity(settings.pipEnabled ? 1 : 0.4)
            }
            .padding()

            Spacer()

            HStack(spacing: 48) {
                Button { skip(by: -10) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
                Button { togglePlay() } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                }
                Button { skip(by: 10) } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text(Format.time(currentTime))
                        .font(.caption).monospacedDigit()
                        .foregroundColor(.white)
                    Slider(
                        value: Binding(
                            get: { currentTime },
                            set: { seek(to: $0) }
                        ),
                        in: 0...(duration > 0 ? duration : 1)
                    )
                    .tint(.orange)
                    Text(Format.time(duration))
                        .font(.caption).monospacedDigit()
                        .foregroundColor(.white)
                }

                HStack(spacing: 16) {
                    Button { showSpeedSheet = true } label: {
                        Label("\(speedText)×", systemImage: "gauge.with.needle")
                    }
                    Button { showSubtitleSettings = true } label: {
                        Label("CC", systemImage: "captions.bubble")
                    }
                    Button { showChapters = true } label: {
                        Label("Chapters", systemImage: "list.bullet")
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.white)
                        Slider(value: $volumeBoost, in: 0...200, step: 5)
                            .frame(width: 90)
                            .tint(.orange)
                            .onChange(of: volumeBoost) { _, _ in applyVolume() }
                        Text("\(Int(volumeBoost))%")
                            .font(.caption).monospacedDigit()
                            .foregroundColor(.white)
                            .frame(width: 42, alignment: .leading)
                        if volumeBoost > 100 {
                            Text("BOOST")
                                .font(.caption2).fontWeight(.bold)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.orange)
                                .foregroundColor(.black)
                                .clipShape(Capsule())
                        }
                    }
                    Button { toggleFullscreen() } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundColor(.white)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.white)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    private var speedText: String {
        speed.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", speed)
            : String(format: "%.2g", speed)
    }

    private var speedSheet: some View {
        NavigationStack {
            List(speedOptions, id: \.self) { option in
                Button {
                    speed = option
                    applySpeed()
                    showSpeedSheet = false
                } label: {
                    HStack {
                        Text("\(option.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", option) : String(format: "%.2g", option))×")
                        Spacer()
                        Text("FREE")
                            .font(.caption2).fontWeight(.bold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.25))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                        if option == speed {
                            Image(systemName: "checkmark").foregroundColor(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Playback Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSpeedSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var chaptersSheet: some View {
        NavigationStack {
            List(chapters, id: \.title) { chapter in
                Button {
                    seek(to: chapter.time)
                    showChapters = false
                } label: {
                    HStack {
                        Text(chapter.title)
                        Spacer()
                        Text(Format.time(chapter.time))
                            .font(.caption).foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showChapters = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var subtitleSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Subtitles", isOn: $subtitlesOn)
                    Toggle("Dual Subtitles (English + Hindi)", isOn: $settings.dualSubtitlesEnabled)
                } header: {
                    Text("Subtitles — FREE")
                } footer: {
                    Text(cues.isEmpty
                         ? "No .srt file found. Sample English + Hindi lines are shown. Put a \"\(video.name).srt\" file next to the video in the Files tab to load real subtitles."
                         : "Loaded \(cues.count) cues from \"\(video.name).srt\".")
                }
                Section("Subtitle Size") {
                    Picker("Size", selection: $settings.subtitleSize) {
                        Text("Small").tag(0)
                        Text("Medium").tag(1)
                        Text("Large").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSubtitleSettings = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func setupPlayer() {
        guard let url = video.url else { return }
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.allowsExternalPlayback = true
        player = newPlayer

        cues = SRTParser.loadCues(for: video)

        let startAt = settings.autoResumeEnabled ? library.progress(for: video) : 0

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [self] time in
            currentTime = time.seconds
            if let itemDuration = newPlayer.currentItem?.duration.seconds,
               itemDuration.isFinite, itemDuration > 0 {
                duration = itemDuration
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [self] _ in
            isPlaying = false
            saveProgress()
            showControls = true
        }

        if startAt > 5 {
            newPlayer.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
            currentTime = startAt
        }
        newPlayer.play()
        isPlaying = true
        applySpeed()
        applyVolume()
        setupPiP()
        scheduleHide()
    }

    private func teardownPlayer() {
        saveProgress()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        hideWorkItem?.cancel()
        player?.pause()
        player = nil
        pipController = nil
        pipLayer = nil
    }

    private func saveProgress() {
        guard let player, duration > 0 else { return }
        library.saveProgress(for: video, position: currentTime, duration: duration)
        library.updateDuration(for: video, duration: duration)
    }

    private func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            showControls = true
            hideWorkItem?.cancel()
        } else {
            applySpeed()
            player.play()
            isPlaying = true
            scheduleHide()
        }
    }

    private func toggleControls() {
        showControls.toggle()
        if showControls { scheduleHide() }
        else { hideWorkItem?.cancel() }
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem {
            if isPlaying { showControls = false }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func seek(to time: TimeInterval) {
        guard let player else { return }
        currentTime = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }

    private func skip(by seconds: TimeInterval) {
        guard duration > 0 else { return }
        seek(to: min(max(currentTime + seconds, 0), duration))
        scheduleHide()
    }

    private func applySpeed() {
        guard let player else { return }
        player.defaultRate = Float(speed)
        if isPlaying { player.rate = Float(speed) }
    }

    private func applyVolume() {
        guard let player else { return }
        player.volume = Float(min(volumeBoost, 100)) / 100
    }

    private func toggleFullscreen() {
        let current = UIDevice.current.orientation
        let target: UIInterfaceOrientation =
            (current.isLandscape ? .portrait : .landscapeRight)
        UIDevice.current.setValue(target.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()
    }

    private func setupPiP() {
        guard let player, settings.pipEnabled,
              AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let layer = AVPlayerLayer(player: player)
        pipLayer = layer
        let controller = AVPictureInPictureController(playerLayer: layer)
        pipController = controller
    }

    private func startPiP() {
        guard settings.pipEnabled else { return }
        guard let controller = pipController else {
            alertMessage = "Picture in Picture is not available on this device or for this video."
            showingAlert = true
            return
        }
        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        } else {
            alertMessage = "Picture in Picture abhi start nahi ho raha. Video ko pehle play karo, phir dobara try karo."
            showingAlert = true
        }
    }
}
