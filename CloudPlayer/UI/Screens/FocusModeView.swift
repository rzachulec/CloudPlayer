import NukeUI
import SwiftUI

/// Full-window distraction-free Focus Mode showing only artwork, title, and artist over a blurred backdrop.
/// - Launched from the Now Playing cover: scales the cover cleanly in and out (`0.72 ↔ 1.0`).
/// - Launched from the media controls pill: pure opacity fade in and out.
struct FocusModeView: View {
    @Bindable var app: AppController
    var cornerRadius: CGFloat = 16

    @State private var isHovering = false
    @State private var isCoverHovered = false
    @State private var expanded = false

    private var track: SCTrack? { app.focusTrack ?? app.audio.currentTrack }
    private var zoomCover: Bool { app.focusZoomAnimation }

    var body: some View {
        ZStack {
            // Pre-rasterized blurred artwork backdrop (single Metal texture for 120fps transitions)
            FocusBackdrop(url: track?.resolvedArtworkURL(size: .small))
                .opacity(expanded ? 1 : 0)

            if let track {
                GeometryReader { geo in
                    let artSize = min(max(min(geo.size.width * 0.50, geo.size.height * 0.56), 180), 500)
                    let dir = app.audio.lastTransitionDirection

                    ZStack {
                        VStack(spacing: 24) {
                            Button {
                                app.exitFocusMode()
                            } label: {
                                CachedArtwork(
                                    url: track.resolvedArtworkURL(size: .large),
                                    size: artSize,
                                    cornerRadius: max(14, artSize * 0.045)
                                )
                                .shadow(color: .black.opacity(0.5), radius: 34, y: 16)
                                .scaleEffect(isCoverHovered && expanded ? 1.012 : 1.0)
                                .animation(.easeOut(duration: 0.18), value: isCoverHovered)
                            }
                            .buttonStyle(.plain)
                            .onHover { isCoverHovered = $0 }
                            .help("Exit Focus Mode (Esc)")
                            .scaleEffect(zoomCover ? (expanded ? 1.0 : 0.72) : 1.0)
                            .opacity(expanded ? 1 : 0)

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
                            .opacity(expanded ? 1 : 0)
                            .offset(y: (zoomCover && !expanded) ? 10 : 0)
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
                    .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.42), value: track.id)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
            }

            // Subtle exit button in top-right corner on hover
            VStack {
                HStack {
                    Spacer()
                    Button {
                        app.exitFocusMode()
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 32, height: 32)
                    }
                    .liquidGlassButton()
                    .tint(.white)
                    .help("Exit Focus Mode (Esc)")
                    .opacity(isHovering && expanded ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: isHovering)
                }
                .padding(.top, 18)
                .padding(.trailing, 20)
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onAppear {
            animate(to: true)
        }
        .onChange(of: app.isFocusVisible) { _, visible in
            animate(to: visible)
        }
    }

    private func animate(to visible: Bool) {
        if zoomCover {
            withAnimation(visible
                ? .spring(response: 0.34, dampingFraction: 0.86)
                : .easeInOut(duration: 0.22)
            ) {
                expanded = visible
            }
        } else {
            withAnimation(visible ? .easeOut(duration: 0.22) : .easeIn(duration: 0.18)) {
                expanded = visible
            }
        }
    }
}

/// Equatable, Metal-rasterized backdrop so GPU blur never recomputes during enter/exit or swipe animations.
private struct FocusBackdrop: View, Equatable {
    let url: URL?

    var body: some View {
        ZStack {
            Color.black
            if let url {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .id(url)
                .blur(radius: 44)
                .scaleEffect(1.3)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.45), value: url)
            }
            LinearGradient(
                colors: [.black.opacity(0.42), .black.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .drawingGroup(opaque: true)
        .ignoresSafeArea()
    }
}
