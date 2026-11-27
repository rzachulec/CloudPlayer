import NukeUI
import SwiftUI

/// Full-window distraction-free Focus Mode showing only artwork, title, and artist over a blurred backdrop.
struct FocusModeView: View {
    @Bindable var app: AppController

    @State private var isHovering = false
    @State private var isCoverHovered = false

    private var track: SCTrack? { app.focusTrack ?? app.audio.currentTrack }

    var body: some View {
        ZStack {
            // Full-bleed blurred artwork backdrop
            backdrop

            if let track {
                GeometryReader { geo in
                    let artSize = min(max(min(geo.size.width * 0.50, geo.size.height * 0.56), 180), 500)
                    let dir = app.audio.lastTransitionDirection

                    ZStack {
                        VStack(spacing: 26) {
                            Button {
                                exit()
                            } label: {
                                CachedArtwork(
                                    url: track.resolvedArtworkURL(size: .large),
                                    size: artSize,
                                    cornerRadius: max(14, artSize * 0.045)
                                )
                                .shadow(color: .black.opacity(0.55), radius: 42, y: 18)
                                .scaleEffect(isCoverHovered ? 1.012 : 1.0)
                                .animation(.easeOut(duration: 0.18), value: isCoverHovered)
                            }
                            .buttonStyle(.plain)
                            .onHover { isCoverHovered = $0 }
                            .help("Exit Focus Mode (Esc)")

                            VStack(spacing: 6) {
                                Text(track.title)
                                    .font(.system(size: min(max(artSize * 0.075, 20), 32), weight: .bold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)

                                Text(track.artistName)
                                    .font(.system(size: min(max(artSize * 0.048, 14), 20), weight: .medium))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: max(artSize * 1.25, 360))
                        }
                        .id(track.id)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: dir == .next ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: dir == .next ? .leading : .trailing).combined(with: .opacity)
                            )
                        )
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.44), value: track.id)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
            }

            // Subtle exit button in top-right corner on hover
            VStack {
                HStack {
                    Spacer()
                    Button {
                        exit()
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 32, height: 32)
                    }
                    .liquidGlassButton()
                    .tint(.white)
                    .help("Exit Focus Mode (Esc)")
                    .opacity(isHovering ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: isHovering)
                }
                .padding(.top, 18)
                .padding(.trailing, 20)
                Spacer()
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            exit()
            return .handled
        }
    }

    private var backdrop: some View {
        ZStack {
            Color.black
            if let url = track?.resolvedArtworkURL(size: .large) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .id(url)
                .blur(radius: 72)
                .scaleEffect(1.35)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.5), value: url)
            }
            LinearGradient(
                colors: [.black.opacity(0.42), .black.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func exit() {
        withAnimation(.easeInOut(duration: 0.24)) {
            app.exitFocusMode()
        }
    }
}
