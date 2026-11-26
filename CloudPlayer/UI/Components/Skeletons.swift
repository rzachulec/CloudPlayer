import SwiftUI

/// Subtle animated shimmer for skeleton placeholders so cold loads feel immediate and alive.
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.16), location: 0.5),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.7)
                    .offset(x: geo.size.width * phase)
                }
                .clipped()
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

struct TrackRowSkeleton: View {
    var waveformMode = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(width: waveformMode ? 64 : 44, height: waveformMode ? 64 : 44)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 210, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary.opacity(0.75))
                    .frame(width: 130, height: 10)
                if waveformMode {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary.opacity(0.6))
                        .frame(height: 26)
                }
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary.opacity(0.7))
                .frame(width: 34, height: 10)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, waveformMode ? 8 : 6)
        .shimmering()
    }
}

struct TileGridSkeleton: View {
    private let columns = [GridItem(.adaptive(minimum: 165, maximum: 220), spacing: 18)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(0..<15, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(height: 12)
                        .padding(.trailing, 24)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary.opacity(0.7))
                        .frame(width: 90, height: 10)
                }
                .shimmering()
            }
        }
    }
}
