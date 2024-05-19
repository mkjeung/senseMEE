import CoreMotion
import Foundation
import AVFoundation
import UIKit
import CoreLocation

class SensorDataManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var motionManager: CMMotionManager
    private var audioRecorder: AVAudioRecorder?
    private var collectionTimer: Timer?
    private var weatherTimer: Timer?
    @Published var sensorData: [String] = []
    @Published var isCollectingData = false
    private var startTime: Date?
    private var weatherDescription: String = "Unknown"
    private let locationManager = CLLocationManager()
    private let weatherAPIKey = "f1a1cc54b829d4c066beafe570a227c2"

    override init() {
        motionManager = CMMotionManager()
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        super.init()
        setupAudioRecorder()
        setupLocationManager()
        startWeatherTimer()
        startDataCollectionLoop()
    }

    private func setupAudioRecorder() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
            
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
            ]
            
            let url = URL(fileURLWithPath: "/dev/null")
            audioRecorder = try? AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
        } catch {
            print("Failed to set up audio recorder: \(error)")
        }
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

    private func startDataCollectionLoop() {
        collectionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.collectData()
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

    private func collectData() {
        if !isCollectingData {
            isCollectingData = true
            sensorData.removeAll()
            startTime = Date()
            print("Collecting data...")

            audioRecorder?.record()

            if motionManager.isDeviceMotionAvailable {
                motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
                    guard let self = self, let motion = motion, error == nil else {
                        print("Error receiving motion data: \(error!)")
                        return
                    }

                    let accel = motion.userAcceleration
                    let gyro = motion.rotationRate

                    self.audioRecorder?.updateMeters()
                    let audioLevel = pow(10, (self.audioRecorder?.averagePower(forChannel: 0) ?? -160.0) / 20)

                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "HHmmss.SSS"
                    let timestamp = dateFormatter.string(from: Date())

                    let dataString = "\(timestamp),\(accel.x),\(accel.y),\(accel.z),\(gyro.x),\(gyro.y),\(gyro.z),\(audioLevel),\(self.weatherDescription)"
                    self.sensorData.append(dataString)
                    print("Data collected: \(dataString)")
                }
            }

            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                self?.stopCollectingData()
            }
        }
    }

    private func stopCollectingData() {
        print("Stopping data collection...")
        isCollectingData = false
        motionManager.stopDeviceMotionUpdates()
        audioRecorder?.stop()
        // Return the collected data for further processing
        processData(sensorData)
    }

    private func processData(_ data: [String]) {
        // Process the collected data here
        // For now, just print the data
        print("Processing collected data:")
        for dataString in data {
            print(dataString)
        }
    }
}

