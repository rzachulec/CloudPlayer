import Foundation
import Observation
import OSLog

/// Central native application controller. Zero WebKit dependency.
@MainActor
@Observable
final class AppController {
    let sessionStore: SessionStore
    let api: SoundCloudAPI

    private(set) var currentUser: SCUser?
    private(set) var isValidatingSession = false
    private(set) var lastError: String?

    private let logger = Logger(subsystem: "local.cloudplayer", category: "AppController")

    init(sessionStore: SessionStore? = nil, api: SoundCloudAPI? = nil) {
        let store = sessionStore ?? SessionStore()
        self.sessionStore = store
        self.api = api ?? SoundCloudAPI()
    }

    func start() {
        sessionStore.bootstrap()
        let store = sessionStore
        Task {
            await api.setOnClientIDUpdated { newID in
                Task { @MainActor in
                    store.updateClientID(newID)
                }
            }
            await api.configure(session: store.session)
            if store.state == .signedIn {
                await validateSession()
            }
        }
    }

    func handleAuthenticated(_ session: SoundCloudSession) {
        lastError = nil
        sessionStore.save(session)
        Task {
            await api.configure(session: session)
            await validateSession()
        }
    }

    func validateSession() async {
        guard sessionStore.state == .signedIn else { return }
        isValidatingSession = true
        lastError = nil
        defer { isValidatingSession = false }

        do {
            let user = try await api.fetchCurrentUser()
            currentUser = user
            sessionStore.updateUser(user)
            logger.info("Authenticated as \(user.username, privacy: .public) (id: \(user.id))")
        } catch let err as SoundCloudAPIError where err == .unauthenticated {
            logger.warning("Stored SoundCloud session rejected (401); signing out")
            lastError = err.localizedDescription
            signOut()
        } catch {
            logger.error("Session validation failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        currentUser = nil
        lastError = nil
        sessionStore.signOut()
        Task {
            await api.configure(session: nil)
        }
    }
}
