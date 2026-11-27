import SwiftUI

/// High-DPI interactive SoundCloud waveform drawn natively via SwiftUI `Canvas`.
struct WaveformView: View {
    let url: URL?
    let progress: Double       // 0...1 (0 if not currently playing)
    let isActive: Bool
    var height: CGFloat = 34
    var onSeek: ((Double) -> Void)?

    @State private var waveform: SCWaveform?
    @State private var hoverFraction: Double?
    @State private var dragFraction: Double?

    var body: some View {
        GeometryReader { geo in
            let barWidth: CGFloat = 2.5
            let spacing: CGFloat = 1.5
            let step = barWidth + spacing
            let barCount = max(Int(geo.size.width / step), 12)
            let bars = waveform?.normalizedBars(count: barCount) ?? Self.placeholderBars(count: barCount)
            let displayProgress = dragFraction ?? progress

            Canvas { ctx, size in
                let totalBars = bars.count
                guard totalBars > 0 else { return }
                let playedColor = Color.accentColor
                let hoverColor = Color.accentColor.opacity(0.42)
                let unplayedColor = Color.primary.opacity(waveform == nil ? 0.10 : (isActive ? 0.24 : 0.18))

                var allBarsPath = Path()
                for i in 0..<totalBars {
                    let amp = bars[i]
                    let h = max(3, CGFloat(amp) * size.height)
                    let x = CGFloat(i) * step
                    let y = size.height - h
                    allBarsPath.addRoundedRect(
                        in: CGRect(x: x, y: y, width: barWidth, height: h),
                        cornerSize: CGSize(width: 1.25, height: 1.25)
                    )
                }

                // Base unplayed bars
                ctx.fill(allBarsPath, with: .color(unplayedColor))

                // Hover preview fill (sub-pixel clipped)
                if let hf = hoverFraction, hf > 0 {
                    ctx.drawLayer { layer in
                        layer.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * CGFloat(hf), height: size.height)))
                        layer.fill(allBarsPath, with: .color(hoverColor))
                    }
                }

                // Active played fill (sub-pixel clipped for silky gradual fill)
                if isActive, displayProgress > 0 {
                    ctx.drawLayer { layer in
                        layer.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * CGFloat(displayProgress), height: size.height)))
                        layer.fill(allBarsPath, with: .color(playedColor))
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    hoverFraction = min(max(loc.x / max(geo.size.width, 1), 0), 1)
                case .ended:
                    hoverFraction = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard onSeek != nil else { return }
                        dragFraction = min(max(v.location.x / max(geo.size.width, 1), 0), 1)
                    }
                    .onEnded { v in
                        guard let onSeek else { return }
                        let f = min(max(v.location.x / max(geo.size.width, 1), 0), 1)
                        dragFraction = nil
                        onSeek(f)
                    }
            )
        }
        .frame(height: height)
        .task(id: url) {
            guard let url else { return }
            waveform = await WaveformCache.shared.waveform(for: url)
        }
    }

    /// Deterministic gentle wave silhouette while waveform JSON loads.
    private static func placeholderBars(count: Int) -> [Double] {
        (0..<count).map { i in
            let x = Double(i) / Double(max(count, 1))
            return 0.22 + 0.28 * abs(sin(x * .pi * 3.5 + 0.4))
        }
    }
}
