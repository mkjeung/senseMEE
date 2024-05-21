import SwiftUI
import SpotifyiOS


class SpotifyManager: NSObject, ObservableObject, SPTSessionManagerDelegate {
    @Published var accessToken: String?
    
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
    
    func fetchAndQueueSong() {
        guard let accessToken = accessToken else {
            print("Access token is nil")
            return
        }
        
        let playlistID = "60ksjrz5GOfN7J8Jn51hZh"
        let songIndex = 0 // Change this to the index of the song you want
        
        let playlistURL = URL(string: "https://api.spotify.com/v1/playlists/\(playlistID)/tracks")!
        var request = URLRequest(url: playlistURL)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                print("Error fetching playlist: \(error)")
                return
            }
            
            guard let data = data else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let items = json["items"] as? [[String: Any]],
                   let track = items[songIndex]["track"] as? [String: Any],
                   let uri = track["uri"] as? String {
                    
                    self.addToQueue(uri: uri)
                }
            } catch {
                print("Error parsing JSON: \(error)")
            }
        }.resume()
    }
    
    func addToQueue(uri: String) {
        guard let accessToken = accessToken else {
            print("Access token is nil")
            return
        }
        
        let queueURL = URL(string: "https://api.spotify.com/v1/me/player/queue?uri=\(uri)")!
        var request = URLRequest(url: queueURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                print("Error adding to queue: \(error)")
                return
            }
            
            print("Song added to queue")
        }.resume()
    }
}

