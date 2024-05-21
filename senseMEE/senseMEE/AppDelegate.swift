import UIKit
import SpotifyiOS

class AppDelegate: UIResponder, UIApplicationDelegate, SPTSessionManagerDelegate {
    var window: UIWindow?
    let SpotifyClientID = "7bf1838791914338a4969de74c01b388"
    let SpotifyRedirectURL = URL(string: "senseMEE://callback")!

    lazy var sessionManager: SPTSessionManager = {
        let configuration = SPTConfiguration(clientID: SpotifyClientID, redirectURL: SpotifyRedirectURL)
        return SPTSessionManager(configuration: configuration, delegate: self)
    }()

    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        sessionManager.application(application, open: url, options: options)
        return true
    }

    func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        print("Spotify session initiated")
    }

    func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        print("Failed to initiate Spotify session: \(error.localizedDescription)")
    }

    func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        print("Spotify session renewed")
    }
}

