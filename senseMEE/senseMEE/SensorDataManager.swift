import CoreMotion
import Foundation
import AVFoundation
import UIKit
import CoreLocation

class SensorDataManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var motionManager: CMMotionManager
    private var audioRecorder: AVAudioRecorder?
    private var collectionTimer: Timer?
    private var countdownTimer: Timer?
    @Published var sensorData: [String] = []
    @Published var remainingTime: Int = 5
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

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        print("Location updated: \(location)")
        fetchWeatherData(for: location)
        locationManager.stopUpdatingLocation()
    }

    func startCollectingData() {
        guard !isCollectingData else { return }
        isCollectingData = true
        sensorData.removeAll()
        startTime = Date()
        remainingTime = 5
        print("Starting data collection...")
        locationManager.startUpdatingLocation()
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            self.remainingTime -= 1
            if self.remainingTime <= 0 {
                timer.invalidate()
            }
        }
    }

    private func fetchWeatherData(for location: CLLocation) {
        let urlString = "https://api.openweathermap.org/data/2.5/weather?lat=\(location.coordinate.latitude)&lon=\(location.coordinate.longitude)&appid=\(weatherAPIKey)"
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            startSensors()
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                print("Error fetching weather data: \(error)")
                self.startSensors()
                return
            }
            
            guard let data = data else {
                print("No data received")
                self.startSensors()
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
        self.startSensors()
    }

    private func startSensors() {
        audioRecorder?.record()
        print("Starting sensors...")

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

        // Start timer to stop collecting data after 5 seconds
        collectionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.stopCollectingData()
        }
        print("Timer started for 5 seconds")
    }

    @objc func stopCollectingData() {
        print("Stopping data collection...")
        isCollectingData = false
        motionManager.stopDeviceMotionUpdates()
        audioRecorder?.stop()
        collectionTimer?.invalidate()
        collectionTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        exportDataToCSV()
    }

    private func exportDataToCSV() {
        guard let startTime = startTime else {
            print("Error: Start time is not set")
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let formattedStartTime = dateFormatter.string(from: startTime)
        let fileName = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sensorData_\(formattedStartTime).csv")
        let csvText = "Timestamp,AccelX,AccelY,AccelZ,GyroX,GyroY,GyroZ,AudioLevel,Weather\n" + sensorData.joined(separator: "\n")

        do {
            try csvText.write(to: fileName, atomically: true, encoding: .utf8)
            print("Data successfully saved to \(fileName)")
        } catch {
            print("Failed to save data: \(error)")
        }
    }
}

