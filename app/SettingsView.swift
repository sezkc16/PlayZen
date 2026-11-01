import SwiftUI

/// Settings. Every feature listed here is FREE in PlayZen —
/// the "FREE" badges are the point, not decoration.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var library: VideoLibrary

    @State private var showingClearConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    freeToggle("Volume Boost", systemImage: "speaker.wave.3.fill",
                               isOn: $settings.volumeBoostEnabled,
                               note: "Volume slider in the player, up to 200%.")
                    freeToggle("Dual Subtitles", systemImage: "captions.bubble",
                               isOn: $settings.dualSubtitlesEnabled,
                               note: "English + Hindi together in the player.")
                    freeToggle("Picture in Picture", systemImage: "pip.enter",
                               isOn: $settings.pipEnabled,
                               note: "Keep watching in a floating window.")
                    freeToggle("Auto-Resume", systemImage: "play.circle",
                               isOn: $settings.autoResumeEnabled,
                               note: "Reopen a video where you left off.")
                } header: {
                    Text("Playback — All FREE")
                }

                Section("Subtitle Size") {
                    Picker("Size", selection: $settings.subtitleSize) {
                        Text("Small").tag(0)
                        Text("Medium").tag(1)
                        Text("Large").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Dark Mode", isOn: $settings.darkModeEnabled)
                        .disabled(true)
                    Text("v1 me hamesha Dark Mode hai — ye design ka hissa hai. Light mode baad me aayega.")
                        .font(.caption)
                        .foregroundColor(.gray)
                } header: {
                    Text("Appearance")
                }

                Section {
                    Button("Clear Continue Watching", role: .destructive) {
                        showingClearConfirm = true
                    }
                } header: {
                    Text("Data")
                }

                Section("About") {
                    HStack {
                        Text("App")
                        Spacer()
                        Text("PlayZen")
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Text("Price")
                        Spacer()
                        Text("Free — no ads, no paywall")
                            .foregroundColor(.green)
                    }
                    Text("PlayZen ek original video player hai. MP4 / MOV / M4V v1 me fully supported hain. MKV support v2 me VLCKit se aayega, aur SMB / network folders bhi v2 me plan hain.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Settings")
            .alert("Clear Continue Watching?", isPresented: $showingClearConfirm) {
                Button("Clear", role: .destructive) {
                    library.clearContinueWatching()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saved playback positions delete ho jayenge. Videos delete nahi hongi.")
            }
        }
    }

    private func freeToggle(_ title: String, systemImage: String,
                            isOn: Binding<Bool>, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.orange)
                Toggle(title, isOn: isOn)
                Text("FREE")
                    .font(.caption2).fontWeight(.bold)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.green.opacity(0.25))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
            }
            Text(note)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}
