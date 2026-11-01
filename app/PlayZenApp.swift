import SwiftUI

/// PlayZen v1.0.0 — free video player, no ads, no paywall.
/// Pure SwiftUI + AVFoundation. No Python, no third-party SDKs in v1.
@main
struct PlayZenApp: App {
    @StateObject private var library = VideoLibrary()
    @StateObject private var settings = SettingsStore()
    @StateObject private var playlists = PlaylistStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(playlists)
                // v1 is dark-only by design (matches the approved UI design).
                .preferredColorScheme(.dark)
        }
    }
}
