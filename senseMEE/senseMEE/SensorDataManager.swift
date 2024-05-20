import CoreMotion
import Foundation
import AVFoundation
import UIKit
import CoreLocation
import CoreML
import Combine 

class SensorDataManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var motionManager: CMMotionManager
    private var audioRecorder: AVAudioRecorder?
    private var collectionTimer: Timer?
    private var weatherTimer: Timer?
    @Published var sensorData: [String] = []
    @Published var isCollectingData = false
    @Published var predictedActivity: String = "Unknown"
    private var startTime: Date?
    private var weatherDescription: String = "Unknown"
    private let locationManager = CLLocationManager()
    private let weatherAPIKey = "f1a1cc54b829d4c066beafe570a227c2"
    
    // Properties for sliding window data
    private var accelData: [(x: Double, y: Double, z: Double, timestamp: Date)] = []
    private var gyroData: [(x: Double, y: Double, z: Double, timestamp: Date)] = []
    private let windowSize: TimeInterval = 5.0
    private var coreMLModel: playlists!
    
    override init() {
        motionManager = CMMotionManager()
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        super.init()
        setupAudioRecorder()
        setupLocationManager()
        startWeatherTimer()
        startDataCollectionLoop()
        loadCoreMLModel()
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
    
    func startDataCollectionLoop() {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion is not available")
            return
        }

        motionManager.startDeviceMotionUpdates()

        collectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
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
            print("Enough data collected, attempting to classify...")
            classifyData()
        } else {
            print("Not enough data collected yet")
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
            DispatchQueue.main.async { // Ensure UI updates are on the main thread
                self.predictedActivity = prediction.classLabel
                print("Predicted activity: \(prediction.classLabel)")
            }
        } catch {
            print("Failed to make a prediction: \(error)")
        }
    }
}

extension Array where Element == Double {
    var mean: Double {
        return isEmpty ? 0.0 : reduce(0.0, +) / Double(count)
    }

    var variance: Double {
        let meanValue = mean
        return isEmpty ? 0.0 : reduce(0.0) { $0 + ($1 - meanValue) * ($1 - meanValue) } / Double(count)
    }
}




//import CoreMotion
//import Foundation
//import AVFoundation
//import UIKit
//import CoreLocation
//
//class SensorDataManager: NSObject, ObservableObject, CLLocationManagerDelegate {
//    private var motionManager: CMMotionManager
//    private var audioRecorder: AVAudioRecorder?
//    private var collectionTimer: Timer?
//    private var weatherTimer: Timer?
//    @Published var sensorData: [String] = []
//    @Published var isCollectingData = false
//    private var startTime: Date?
//    private var weatherDescription: String = "Unknown"
//    private let locationManager = CLLocationManager()
//    private let weatherAPIKey = "f1a1cc54b829d4c066beafe570a227c2"
//
//    override init() {
//        motionManager = CMMotionManager()
//        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
//        super.init()
//        setupAudioRecorder()
//        setupLocationManager()
//        startWeatherTimer()
//        startDataCollectionLoop()
//    }
//
//    private func setupAudioRecorder() {
//        let audioSession = AVAudioSession.sharedInstance()
//        do {
//            try audioSession.setCategory(.record, mode: .default)
//            try audioSession.setActive(true)
//            
//            let settings: [String: Any] = [
//                AVFormatIDKey: kAudioFormatAppleLossless,
//                AVSampleRateKey: 44100.0,
//                AVNumberOfChannelsKey: 1,
//                AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
//            ]
//            
//            let url = URL(fileURLWithPath: "/dev/null")
//            audioRecorder = try? AVAudioRecorder(url: url, settings: settings)
//            audioRecorder?.isMeteringEnabled = true
//        } catch {
//            print("Failed to set up audio recorder: \(error)")
//        }
//    }
//
//    private func setupLocationManager() {
//        locationManager.delegate = self
//        locationManager.requestWhenInUseAuthorization()
//    }
//
//    private func startWeatherTimer() {
//        fetchWeatherData()
//        weatherTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
//            self?.fetchWeatherData()
//        }
//    }
//
//    private func startDataCollectionLoop() {
//        collectionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
//            self?.collectData()
//        }
//    }
//
//    private func fetchWeatherData() {
//        locationManager.startUpdatingLocation()
//    }
//
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        guard let location = locations.first else { return }
//        print("Location updated: \(location)")
//        locationManager.stopUpdatingLocation()
//
//        let urlString = "https://api.openweathermap.org/data/2.5/weather?lat=\(location.coordinate.latitude)&lon=\(location.coordinate.longitude)&appid=\(weatherAPIKey)"
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//
//        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
//            guard let self = self else { return }
//            if let error = error {
//                print("Error fetching weather data: \(error)")
//                return
//            }
//
//            guard let data = data else {
//                print("No data received")
//                return
//            }
//
//            do {
//                if let weatherResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let weatherArray = weatherResponse["weather"] as? [[String: Any]],
//                   let weather = weatherArray.first,
//                   let description = weather["main"] as? String {
//                    self.weatherDescription = description
//                    print("Weather description: \(description)")
//                } else {
//                    print("Failed to parse weather data")
//                }
//            } catch {
//                print("Failed to decode weather data: \(error)")
//            }
//        }
//
//        task.resume()
//    }
//
//    private func collectData() {
//        if !isCollectingData {
//            isCollectingData = true
//            sensorData.removeAll()
//            startTime = Date()
//            print("Collecting data...")
//
//            audioRecorder?.record()
//
//            if motionManager.isDeviceMotionAvailable {
//                motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
//                    guard let self = self, let motion = motion, error == nil else {
//                        print("Error receiving motion data: \(error!)")
//                        return
//                    }
//
//                    let accel = motion.userAcceleration
//                    let gyro = motion.rotationRate
//
//                    self.audioRecorder?.updateMeters()
//                    let audioLevel = pow(10, (self.audioRecorder?.averagePower(forChannel: 0) ?? -160.0) / 20)
//
//                    let dateFormatter = DateFormatter()
//                    dateFormatter.dateFormat = "HHmmss.SSS"
//                    let timestamp = dateFormatter.string(from: Date())
//
//                    let dataString = "\(timestamp),\(accel.x),\(accel.y),\(accel.z),\(gyro.x),\(gyro.y),\(gyro.z),\(audioLevel),\(self.weatherDescription)"
//                    self.sensorData.append(dataString)
//                    print("Data collected: \(dataString)")
//                }
//            }
//
//            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
//                self?.stopCollectingData()
//            }
//        }
//    }
//
//    private func stopCollectingData() {
//        print("Stopping data collection...")
//        isCollectingData = false
//        motionManager.stopDeviceMotionUpdates()
//        audioRecorder?.stop()
//        // Return the collected data for further processing
//        processData(sensorData)
//    }
//
//    private func processData(_ data: [String]) {
//        // Process the collected data here
//        // For now, just print the data
//        print("Processing collected data:")
//        for dataString in data {
//            print(dataString)
//        }
//    }
//}
//




