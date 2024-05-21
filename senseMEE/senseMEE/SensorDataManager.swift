import CoreMotion
import Foundation
import AVFoundation
import UIKit
import CoreLocation
import CoreML
import Combine

class SensorDataManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var motionManager: CMMotionManager
    private var collectionTimer: Timer?
    private var spotifyTimer: Timer?
    private var weatherTimer: Timer?
    @Published var sensorData: [String] = []
    @Published var isCollectingData = false
    @Published var predictedActivity: String = "Unknown"
    @Published var availableDevices: [SpotifyDevice] = []
    
    private var startTime: Date?
    private var weatherDescription: String = "Unknown"
    private let locationManager = CLLocationManager()
    private let weatherAPIKey = "f1a1cc54b829d4c066beafe570a227c2"
    private var curPlaylistId = "fill in"
    private var nextPlaylistId = "change"
    private var accessToken: String? {
        return UserDefaults.standard.string(forKey: "SpotifyAccessToken")
    }
    // Properties for sliding window data
    private var accelData: [(x: Double, y: Double, z: Double, timestamp: Date)] = []
    private var gyroData: [(x: Double, y: Double, z: Double, timestamp: Date)] = []
    private let windowSize: TimeInterval = 5.0
    private var coreMLModel: playlists!
    
    private var spotifyManager: SpotifyManager
    private var cancellables: Set<AnyCancellable> = []
    
    init(spotifyManager: SpotifyManager) {
        self.spotifyManager = spotifyManager
        self.motionManager = CMMotionManager()
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        super.init()
        setupLocationManager()
        startWeatherTimer()
        startDataCollectionLoop()
        loadCoreMLModel()
        observeSpotifyDevices()
    }
    
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
    }
    
    private func startWeatherTimer() {
        fetchWeatherData()
        weatherTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.fetchWeatherData()
        }
    }
    
    func startDataCollectionLoop() {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion is not available")
            return
        }

        motionManager.startDeviceMotionUpdates()

        collectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.collectData()
        }
        
        spotifyTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            if let playlistId = self?.curPlaylistId {
                if let tok = self?.accessToken {
                    self?.handleSpotify(accessToken: tok, playlistId: playlistId)
                }
            }
        }
    }
    
    private func fetchWeatherData() {
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        print("Location updated: \(location)")
        locationManager.stopUpdatingLocation()

        let urlString = "https://api.openweathermap.org/data/2.5/weather?lat=\(location.coordinate.latitude)&lon=\(location.coordinate.longitude)&appid=\(weatherAPIKey)"
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                print("Error fetching weather data: \(error)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            do {
                if let weatherResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let weatherArray = weatherResponse["weather"] as? [[String: Any]],
                   let weather = weatherArray.first,
                   let description = weather["main"] as? String {
                    self.weatherDescription = description
                    print("Weather description: \(description)")
                } else {
                    print("Failed to parse weather data")
                }
            } catch {
                print("Failed to decode weather data: \(error)")
            }
        }

        task.resume()
    }
    
    private func loadCoreMLModel() {
        do {
            coreMLModel = try playlists(configuration: MLModelConfiguration())
        } catch {
            print("Failed to load CoreML model: \(error)")
        }
    }
    
    private func collectData() {
        guard let motion = motionManager.deviceMotion else {
            print("No device motion data available")
            return
        }

        let accel = motion.userAcceleration
        let gyro = motion.rotationRate
        let timestamp = Date()

        accelData.append((x: accel.x, y: accel.y, z: accel.z, timestamp: timestamp))
        gyroData.append((x: gyro.x, y: gyro.y, z: gyro.z, timestamp: timestamp))

        accelData = accelData.filter { $0.timestamp > Date().addingTimeInterval(-windowSize) }
        gyroData = gyroData.filter { $0.timestamp > Date().addingTimeInterval(-windowSize) }

        // Check if we have enough data to classify
        if let start = accelData.first?.timestamp, Date().timeIntervalSince(start) >= windowSize {
            //print("Enough data collected, attempting to classify...")
            classifyData()
        } else {
            //print("Not enough data collected yet")
        }
    }
    
    // Spotify
    
    func getActiveDevice(accessToken: String, completion: @escaping (String?) -> Void) {
        let url = URL(string: "https://api.spotify.com/v1/me/player")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error getting active device: \(error.localizedDescription)")
                completion(nil)
                return
            }

            if let data = data {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let device = json["device"] as? [String: Any],
                       let deviceId = device["id"] as? String {
                        completion(deviceId)
                    } else {
                        completion(nil)
                    }
                } catch {
                    print("Error parsing JSON: \(error.localizedDescription)")
                    completion(nil)
                }
            }
        }

        task.resume()
    }
    
    func fetchPlaylistTracks(accessToken: String, playlistId: String, completion: @escaping ([String]?) -> Void) {
        var allTrackIds: [String] = []
        var urlString: String = "https://api.spotify.com/v1/playlists/\(playlistId)/tracks"
//        var nextURL: String? = "https://api.spotify.com/v1/playlists/\(playlistId)/tracks"
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Error fetching playlist tracks: \(String(describing: error))")
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    for item in items {
                        if let track = item["track"] as? [String: Any],
                           let trackId = track["id"] as? String {
                            allTrackIds.append(trackId)
                        }
                    }
                    completion(allTrackIds)
                } else {
                    completion(nil)
                }
            } catch {
                print("JSON error: \(error.localizedDescription)")
                completion(nil)
            }
        }
        task.resume()
    }

    func chooseRandomTrack(from tracks: [String]) -> String? {
        guard !tracks.isEmpty else { return nil }
        let randomIndex = Int.random(in: 0..<tracks.count)
        return tracks[randomIndex]
    }

    func getRandomTrackFromPlaylist(accessToken: String, playlistId: String, completion: @escaping (String?) -> Void) {
        
            fetchPlaylistTracks(accessToken: accessToken, playlistId: playlistId) { trackIds in
                guard let trackIds = trackIds else {
                    print("Failed to fetch track IDs")
                    completion(nil)
                    return
                }
                print("\(trackIds)")

                guard let randomTrackId = self.chooseRandomTrack(from: trackIds) else {
                    print("couldn't get random track")
                    completion(nil)
                    return
                }
                print("\(randomTrackId)")
                completion(randomTrackId)
            }
    }
    
    func addTrackToPlaybackQueue(accessToken: String, trackId: String, completion: @escaping (Bool) -> Void) {
        let queueUrl = "https://api.spotify.com/v1/me/player/queue?uri=spotify%3Atrack%3A\(trackId)"
//        let queueUrl = "https://api.spotify.com/v1/me/player/queue?uri=\(trackId)"
        print(queueUrl)
        
//        guard let url = URL(string: queueUrl) else {
//            completion(false)
//            return
//        }
//
//        var request = URLRequest(url: url)
//        request.httpMethod = "POST"
//        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
//
//        let task = URLSession.shared.dataTask(with: request) { data, response, error in
//            guard error == nil, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 else {
//                print("Error adding track to playback queue: \(String(describing: error))")
//                completion(false)
//                return
//            }
//
//            completion(true)
//        }
//
//        task.resume()
        guard let url = URL(string: queueUrl) else {
                print("Invalid URL")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Error adding track to playback queue: \(error.localizedDescription)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 204 {
                        print("Track added to playback queue successfully.")
                    } else {
                        print("Failed to add track to playback queue. Status code: \(httpResponse.statusCode)")
                        if let data = data, let errorResponse = String(data: data, encoding: .utf8) {
                            print("Error response: \(errorResponse)")
                        }
                    }
                }
            }

            task.resume()
    }
    
    func skipToNext(accessToken: String, completion: @escaping (Bool) -> Void) {
        let nextUrl = "https://api.spotify.com/v1/me/player/next"
        guard let url = URL(string: nextUrl) else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 else {
                print("Error adding track to playback queue: \(String(describing: error))")
                completion(false)
                return
            }
            
            completion(true)
        }
        
        task.resume()
        
    }
    
    func handleSpotify(accessToken: String, playlistId: String) {
        if self.nextPlaylistId != self.curPlaylistId {
            self.getRandomTrackFromPlaylist(accessToken: accessToken, playlistId: playlistId) { randomTrackId in
                if let randomTrackId = randomTrackId {
                    self.addTrackToPlaybackQueue(accessToken: accessToken, trackId: randomTrackId) { success in
                        if success {
                            print("Successfully added track to playback queue")
                        } else {
                            print("Failed to add track to playback queue")
                        }
                    }
                    self.skipToNext(accessToken: accessToken) { success in
                        if success {
                            print("Successfully skipped to next song")
                        } else {
                            print("Failed to skip to next song")
                        }
                    }
                    
                } else {
                    print("No tracks found in the playlist or an error occurred")
                }
            }
            self.curPlaylistId = self.nextPlaylistId
        }
    }

    

    private func classifyData() {
        let accelMeanX = accelData.map { $0.x }.mean
        let accelMeanY = accelData.map { $0.y }.mean
        let accelMeanZ = accelData.map { $0.z }.mean
        let gyroMeanX = gyroData.map { $0.x }.mean
        let gyroMeanY = gyroData.map { $0.y }.mean
        let gyroMeanZ = gyroData.map { $0.z }.mean

        let accelVarX = accelData.map { $0.x }.variance
        let accelVarY = accelData.map { $0.y }.variance
        let accelVarZ = accelData.map { $0.z }.variance
        let gyroVarX = gyroData.map { $0.x }.variance
        let gyroVarY = gyroData.map { $0.y }.variance
        let gyroVarZ = gyroData.map { $0.z }.variance
        
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH"
        let hourString = dateFormatter.string(from: Date())

        if let hour = Int(hourString) {
            //print(hour) // This will print the hour as an integer

            let modelInput = playlistsInput(
                mean_AccelX: accelMeanX,
                var_AccelX: accelVarX,
                mean_AccelY: accelMeanY,
                var_AccelY: accelVarY,
                mean_AccelZ: accelMeanZ,
                var_AccelZ: accelVarZ,
                mean_GyroX: gyroMeanX,
                var_GyroX: gyroVarX,
                mean_GyroY: gyroMeanY,
                var_GyroY: gyroVarY,
                mean_GyroZ: gyroMeanZ,
                var_GyroZ: gyroVarZ)

            do {
                let prediction = try coreMLModel.prediction(input: modelInput)
                
                let mode = determineMode(weather: weatherDescription, time: hour, activity: prediction.classLabel)
                
                DispatchQueue.main.async { // Ensure UI updates are on the main thread
                    self.predictedActivity = mode
                    var pid: String

                    switch mode {
                    case "Hype & Energizing":
                        pid = "6CKEggKfRsvHzxnvrAjRDg"
                    case "Emo Rock Music":
                        pid = "7wg3juMUK73gUJEEqqWc9Z"
                    case "Bright Happy Chill":
                        pid = "1xII5ZLXOb6Sys0kSWgB7R"
                    case "Calm and Mellow Chill":
                        pid = "1hNnTVPxdcjwb86RIiihnk"
                    case "Sleep mode":
                        pid = "4UpGbmuWWzD8KQZ8RlHUs7"
                    default:
                        pid = "7wg3juMUK73gUJEEqqWc9Z"
                    }

                    self.nextPlaylistId = pid
                    //print("Predicted activity: \(self.predictedActivity)")
                }
                //print("Predicted activity: \(self.predictedActivity)")
            } catch {
                print("Failed to make a prediction: \(error)")
            }
        } else {
            print("Failed to convert hour string to integer")
        }
    }
    
    func determineMode(weather: String, time: Int, activity: String) -> String {
        //print("Determining mode with weather: \(weather), time: \(time), activity: \(activity), micLevel: \(micLevel)")
        
        if activity == "running" {
            return "Hype & Energizing"
        } else if weather == "Rain" || weather == "Drizzle" || weather == "Thunderstorm"{
            return "Emo Rock Music"
        } else if activity == "walking" && time >= 19 {
            return "Emo Rock Music"
        } else if activity == "walking" && weather == "Clear" && time < 19 {
            return "Bright Happy Chill"
        } else if activity == "stationary" && time < 19 {
            return "Calm and Mellow Chill"
        } else if activity == "walking" && weather == "Clouds" && time < 19 {
            return "Calm and Mellow Chill"
        } else if activity == "stationary" && time >= 19 {
            return "Sleep mode"
        } else {
            return "Calm and Mellow Chill"
        }
    }
    private func observeSpotifyDevices() {
        spotifyManager.$availableDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.availableDevices = devices
            }
            .store(in: &cancellables)
    }
}

// Extensions should be placed outside the class definition
extension Array where Element == Double {
    var mean: Double {
        return isEmpty ? 0.0 : reduce(0.0, +) / Double(count)
    }

    var variance: Double {
        let meanValue = mean
        return isEmpty ? 0.0 : reduce(0.0) { $0 + ($1 - meanValue) * ($1 - meanValue) } / Double(count)
    }
}
