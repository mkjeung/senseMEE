import SwiftUI
import SpotifyiOS

class SpotifyManager: NSObject, ObservableObject, SPTSessionManagerDelegate {
    @Published var accessToken: String? {
        didSet {
            if let token = accessToken {
                // Save the access token to UserDefaults
                UserDefaults.standard.set(token, forKey: "SpotifyAccessToken")
            }
        }
    }
    
    let SpotifyClientID = "7bf1838791914338a4969de74c01b388"
    let SpotifyRedirectURL = URL(string: "senseMEE://callback")!
    
    lazy var sessionManager: SPTSessionManager = {
        let configuration = SPTConfiguration(clientID: SpotifyClientID, redirectURL: SpotifyRedirectURL)
        return SPTSessionManager(configuration: configuration, delegate: self)
    }()
    
    func authenticate() {
        let scope: SPTScope = [.playlistReadPrivate, .userReadPlaybackState, .userModifyPlaybackState]
        sessionManager.initiateSession(with: scope, options: .default)
    }
    
    func handleURL(_ url: URL) {
        sessionManager.application(UIApplication.shared, open: url, options: [:])
    }
    
    func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        print("Spotify session initiated")
        DispatchQueue.main.async {
            self.accessToken = session.accessToken
        }
    }
    
    func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        print("Failed to initiate Spotify session: \(error.localizedDescription)")
    }
    
    func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        print("Spotify session renewed")
    }
}

