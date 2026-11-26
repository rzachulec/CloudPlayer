import NukeUI
import SwiftUI

/// Milestone 1 native root view:
/// - Signed out → DisposableSignInView (the only place WebKit ever exists).
/// - Signed in → 100% pure SwiftUI native shell (WebKit is torn down and deallocated).
struct NativeRootView: View {
    @Bindable var app: AppController
    var onSignOut: () -> Void

    var body: some View {
        switch app.sessionStore.state {
        case .unknown:
            Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea()
                .frame(minWidth: DisposableSignInView.minWidth, minHeight: DisposableSignInView.minHeight)
        case .signedOut:
            DisposableSignInView { session in
                app.handleAuthenticated(session)
            }
        case .signedIn:
            Milestone1SignedInView(app: app, onSignOut: onSignOut)
        }
    }
}

/// Temporary Milestone 1 verification shell showing live `/me` data fetched via pure-Swift `SoundCloudAPI`
/// and Nuke-cached avatar loading with zero WebKit processes.
private struct Milestone1SignedInView: View {
    @Bindable var app: AppController
    var onSignOut: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if let user = app.currentUser {
                LazyImage(url: user.avatarURL(size: .large)) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Circle().fill(.quaternary)
                            .overlay(Image(systemName: "person.fill").font(.title).foregroundStyle(.secondary))
                    }
                }
                .frame(width: 88, height: 88)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))

                VStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.system(size: 22, weight: .bold))
                    Text("@\(user.permalink ?? user.username) · ID \(user.id)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 24) {
                    statPill("Likes", value: user.likesCount)
                    statPill("Following", value: user.followingsCount)
                    statPill("Followers", value: user.followersCount)
                    statPill("Tracks", value: user.trackCount)
                }
                .padding(.top, 4)

                Label("Connected via pure Swift api-v2 · WebKit destroyed", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .modifier(BadgeGlass())
            } else if app.isValidatingSession {
                ProgressView("Verifying SoundCloud session…")
                    .controlSize(.regular)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(app.lastError ?? "Could not load your SoundCloud profile.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Button("Retry /me") {
                        Task { await app.validateSession() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let cid = app.sessionStore.session?.clientID, !cid.isEmpty {
                Text("client_id: \(cid.prefix(8))…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Button("Refresh /me") {
                    Task { await app.validateSession() }
                }
                .disabled(app.isValidatingSession)

                Button("Sign Out…", role: .destructive, action: onSignOut)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
    }

    @ViewBuilder
    private func statPill(_ title: String, value: Int?) -> some View {
        VStack(spacing: 2) {
            Text(value.map { "\($0)" } ?? "–")
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

private struct BadgeGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}
