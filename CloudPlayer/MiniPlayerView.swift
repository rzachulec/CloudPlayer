import AppKit
import SwiftUI

/// Apple Music–style mini player: artwork + title, a thick scrubber with elapsed / remaining
/// time, and shuffle · previous · play · next · repeat. Like and expand sit top-right.
struct MiniPlayerView: View {
    @ObservedObject var player: WebPlayer
    var onExpand: () -> Void

    static let width: CGFloat = 340

    var body: some View {
        let s = player.state
        VStack(spacing: 0) {
            header(s)
                .padding(.bottom, 14)
            Scrubber(player: player)
                .padding(.bottom, 8)
            controls(s)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(width: Self.width)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }

    static let cornerRadius: CGFloat = 16

    private func header(_ s: TrackState) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Artwork(url: s.artworkURL, size: 52, cornerRadius: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.hasTrack ? s.title : "Not Playing")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(s.hasTrack ? s.artist : "Pick something in the main window")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .contextMenu { if s.hasTrack { NowPlayingMenu(player: player, onNavigate: onExpand) } }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                IconButton(symbol: "pip.exit", size: 11, help: "Open Main Window (⇧⌘M)", action: onExpand)
                    .foregroundStyle(.secondary)
                IconButton(symbol: s.isLiked ? "heart.fill" : "heart", size: 12, active: s.isLiked,
                           help: s.isLiked ? "Unlike" : "Like") { player.toggleLike() }
                    .disabled(!s.hasTrack)
            }
        }
    }

    private func controls(_ s: TrackState) -> some View {
        HStack(spacing: 0) {
            IconButton(symbol: "shuffle", size: 14, active: s.shuffle, help: "Shuffle") { player.toggleShuffle() }
            Spacer()
            HStack(spacing: 26) {
                IconButton(symbol: "backward.fill", size: 20, help: "Previous") { player.previous() }
                IconButton(symbol: s.isPlaying ? "pause.fill" : "play.fill", size: 28,
                           help: s.isPlaying ? "Pause" : "Play") { player.playPause() }
                IconButton(symbol: "forward.fill", size: 20, help: "Next") { player.next() }
            }
            Spacer()
            IconButton(symbol: s.repeatMode == .one ? "repeat.1" : "repeat", size: 14, active: s.repeatMode != .none,
                       help: "Repeat: \(s.repeatMode.rawValue)") { player.cycleRepeat() }
        }
        .disabled(!s.hasTrack)
    }
}

/// Thick capsule progress bar with elapsed time on the left and remaining time on the right.
private struct Scrubber: View {
    @ObservedObject var player: WebPlayer
    @State private var scrub: Double?   // 0...1 while dragging
    @State private var hovering = false

    var body: some View {
        let s = player.state
        let fraction = min(max(scrub ?? (s.duration > 0 ? s.position / s.duration : 0), 0), 1)
        let enabled = s.hasTrack && s.duration > 0
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
                            let f = min(max(v.location.x / geo.size.width, 0), 1)
                            player.seek(fraction: f)
                            // Hold the scrubbed position briefly so the bar doesn't jump back.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { scrub = nil }
                        }
                )
                .animation(.easeOut(duration: 0.12), value: hovering)
            }
            .frame(height: 12)

            HStack {
                Text(formatTime(fraction * s.duration))
                Spacer()
                Text("−" + formatTime(max(s.duration - fraction * s.duration, 0)))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .opacity(enabled ? 1 : 0.5)
    }
}

/// Background material that also drags the (borderless) window when you grab empty space.
private final class DraggableEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = DraggableEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
