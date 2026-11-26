import AppKit
import SwiftUI

/// Native Apple Music–style floating mini player backed by `AudioEngine`.
struct NativeMiniPlayerView: View {
    @Bindable var app: AppController
    var onExpand: () -> Void

    static let width: CGFloat = 340
    static let cornerRadius: CGFloat = 16

    var body: some View {
        let audio = app.audio
        let track = audio.currentTrack
        VStack(spacing: 0) {
            header(audio: audio, track: track)
                .padding(.bottom, 14)
            NativeMiniScrubber(audio: audio)
                .padding(.bottom, 8)
            controls(audio)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(width: Self.width)
        .background(NativeDraggableMaterial())
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func header(audio: AudioEngine, track: SCTrack?) -> some View {
        let liked = track.map { app.library.isLiked($0.id) } ?? false
        return HStack(alignment: .center, spacing: 12) {
            CachedArtwork(url: track?.resolvedArtworkURL(size: .medium), size: 52, cornerRadius: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(track?.title ?? "Not Playing")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(track?.artistName ?? "Pick something in the main window")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                IconButton(symbol: "pip.exit", size: 11, help: "Open Main Window (⇧⌘M)", action: onExpand)
                    .foregroundStyle(.secondary)
                IconButton(
                    symbol: liked ? "heart.fill" : "heart",
                    size: 12,
                    active: liked,
                    help: liked ? "Unlike" : "Like"
                ) { app.toggleLikeCurrentTrack() }
                    .disabled(!audio.hasTrack)
            }
        }
    }

    private func controls(_ audio: AudioEngine) -> some View {
        HStack(spacing: 0) {
            IconButton(symbol: "shuffle", size: 14, active: audio.queue.shuffle, help: "Shuffle") {
                audio.toggleShuffle()
            }
            Spacer()
            HStack(spacing: 26) {
                IconButton(symbol: "backward.fill", size: 20, help: "Previous") { audio.previous() }
                IconButton(
                    symbol: audio.isPlaying ? "pause.fill" : "play.fill",
                    size: 28,
                    help: audio.isPlaying ? "Pause" : "Play"
                ) { audio.togglePlayPause() }
                IconButton(symbol: "forward.fill", size: 20, help: "Next") { audio.next() }
            }
            Spacer()
            IconButton(
                symbol: audio.queue.repeatMode == .one ? "repeat.1" : "repeat",
                size: 14,
                active: audio.queue.repeatMode != .none,
                help: "Repeat: \(audio.queue.repeatMode.rawValue)"
            ) { audio.cycleRepeat() }
        }
        .disabled(!audio.hasTrack)
    }
}

private struct NativeMiniScrubber: View {
    @Bindable var audio: AudioEngine
    @State private var scrub: Double?
    @State private var hovering = false

    var body: some View {
        let enabled = audio.hasTrack && audio.duration > 0
        let fraction = min(max(scrub ?? (audio.duration > 0 ? audio.position / audio.duration : 0), 0), 1)
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.14))
                    Capsule().fill(.primary.opacity(scrub != nil || hovering ? 0.75 : 0.5))
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 6 : 0))
                }
                .frame(height: scrub != nil || hovering ? 7 : 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { hovering = $0 && enabled }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard enabled else { return }
                            scrub = min(max(v.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { v in
                            guard enabled else { return }
                            audio.seek(fraction: min(max(v.location.x / geo.size.width, 0), 1))
                            scrub = nil
                        }
                )
                .animation(.easeOut(duration: 0.12), value: hovering)
            }
            .frame(height: 12)

            HStack {
                Text(formatTime(fraction * audio.duration))
                Spacer()
                Text("−" + formatTime(max(audio.duration - fraction * audio.duration, 0)))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .opacity(enabled ? 1 : 0.5)
    }
}

private final class NativeDraggableEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

private struct NativeDraggableMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NativeDraggableEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
