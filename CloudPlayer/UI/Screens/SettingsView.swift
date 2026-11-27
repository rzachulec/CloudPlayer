import AppKit
import Nuke
import NukeUI
import SwiftUI

/// Native macOS Settings screen (⌘,).
struct SettingsView: View {
    @Bindable var app: AppController
    var onSignOut: () -> Void

    @AppStorage("cp.followNowPlaying") private var followNowPlaying = true
    @AppStorage("cp.showToasts") private var showToasts = true
    @AppStorage("cp.viewMode.likes") private var likesViewMode: String = TrackListDisplayMode.compact.rawValue
    @State private var cacheSizeLabel = "Calculating…"
    @State private var isClearingCache = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.system(size: 24, weight: .bold))
                    Text("Playback, appearance, storage, and account")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Form {
                    Section("Playback") {
                        Toggle(
                            "Autoplay similar tracks when queue ends",
                            isOn: Binding(
                                get: { app.audio.queue.autoplayEnabled },
                                set: {
                                    app.audio.setAutoplayEnabled($0)
                                    UserDefaults.standard.set($0, forKey: "cp.autoplayEnabled")
                                }
                            )
                        )

                        Toggle("Follow Now Playing on Track Detail", isOn: $followNowPlaying)
                    }

                    Section("Interface") {
                        Toggle("Show sidebar toast notifications", isOn: $showToasts)

                        Picker("Default Likes layout", selection: $likesViewMode) {
                            ForEach(TrackListDisplayMode.allCases) { mode in
                                Text(mode.label).tag(mode.rawValue)
                            }
                        }
                    }

                    Section("Storage & Cache") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Local cache")
                                Text("Cached API feeds, waveforms, and artwork (\(cacheSizeLabel))")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Clear Cache") {
                                Task {
                                    isClearingCache = true
                                    await app.clearAllCaches()
                                    cacheSizeLabel = computeCacheSize()
                                    isClearingCache = false
                                }
                            }
                            .disabled(isClearingCache)
                        }
                    }

                    Section("Account") {
                        if let user = app.currentUser {
                            HStack(spacing: 12) {
                                LazyImage(url: user.avatarURL(size: .small)) { state in
                                    if let image = state.image {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Circle().fill(.quaternary)
                                    }
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName)
                                        .font(.system(size: 13.5, weight: .semibold))
                                    Text("@\(user.permalink ?? user.username) · ID \(user.id)")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("View Profile") {
                                    app.router.navigate(to: .user(user))
                                }
                            }
                        }

                        if let url = URL(string: "https://soundcloud.com/settings") {
                            HStack {
                                Text("SoundCloud Account Settings")
                                Spacer()
                                Button("Open in Browser") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sign Out")
                                Text("Clears your saved SoundCloud token and local cache.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Sign Out…", role: .destructive, action: onSignOut)
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 96)
            .frame(maxWidth: 740, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            cacheSizeLabel = computeCacheSize()
        }
    }

    private func computeCacheSize() -> String {
        let fm = FileManager.default
        let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudPlayer", isDirectory: true)
        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: cachesDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
