import SwiftUI

/// Small building blocks shared by the main window's player bar and the mini player.

struct Artwork: View {
    let url: URL?
    let size: CGFloat
    var cornerRadius: CGFloat = 4

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(.quaternary)
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 13
    var active = false
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: size + 10, height: size + 10)
                .contentShape(Rectangle())
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Previous / play-pause / next, optionally flanked by shuffle and repeat.
struct TransportControls: View {
    @ObservedObject var player: WebPlayer
    var showModes = true
    var playSize: CGFloat = 22

    var body: some View {
        let s = player.state
        HStack(spacing: 18) {
            if showModes {
                IconButton(symbol: "shuffle", size: 12, active: s.shuffle, help: "Shuffle") { player.toggleShuffle() }
            }
            IconButton(symbol: "backward.fill", size: 14, help: "Previous") { player.previous() }
            IconButton(symbol: s.isPlaying ? "pause.fill" : "play.fill", size: playSize, help: s.isPlaying ? "Pause" : "Play") { player.playPause() }
            IconButton(symbol: "forward.fill", size: 14, help: "Next") { player.next() }
            if showModes {
                IconButton(symbol: s.repeatMode == .one ? "repeat.1" : "repeat", size: 12, active: s.repeatMode != .none,
                           help: "Repeat: \(s.repeatMode.rawValue)") { player.cycleRepeat() }
            }
        }
        .disabled(!s.hasTrack)
    }
}

/// Elapsed time, scrubber, duration.
struct ProgressRow: View {
    @ObservedObject var player: WebPlayer
    @State private var scrub: Double?   // 0...1 while dragging

    var body: some View {
        let s = player.state
        let fraction = scrub ?? (s.duration > 0 ? s.position / s.duration : 0)
        HStack(spacing: 8) {
            Text(formatTime(fraction * s.duration)).frame(minWidth: 34, alignment: .trailing)
            Slider(value: Binding(get: { fraction }, set: { scrub = $0 }), in: 0...1) { editing in
                if !editing, let f = scrub {
                    player.seek(fraction: f)
                    // Hold the scrubbed position briefly so the bar doesn't jump back.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { scrub = nil }
                }
            }
            .controlSize(.mini)
            .frame(minWidth: 60)   // don't let the slider's intrinsic width overflow narrow bars
            Text(formatTime(s.duration)).frame(minWidth: 34, alignment: .leading)
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(.secondary)
        .disabled(!s.hasTrack || s.duration <= 0)
    }
}

func formatTime(_ t: Double) -> String {
    guard t.isFinite, t > 0 else { return "0:00" }
    let total = Int(t.rounded())
    return total >= 3600
        ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        : String(format: "%d:%02d", total / 60, total % 60)
}
