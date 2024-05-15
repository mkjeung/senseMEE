import CoreMotion
import Foundation
import AVFoundation
import UIKit
import CoreLocation

class SensorDataManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, CLLocationManagerDelegate {
    private var motionManager: CMMotionManager
    private var audioRecorder: AVAudioRecorder?
    private var captureSession: AVCaptureSession?
    private var collectionTimer: Timer?
    @Published var sensorData: [String] = []
    private var startTime: Date?
    private var currentLightLevel: Float = 0.0
    private var weatherDescription: String = "Unknown"
    private let apiKey = "4020668aec0e4380ab9162124241505" // Your WeatherAPI.com API key
    private let locationManager = CLLocationManager()

    override init() {
        motionManager = CMMotionManager()
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        super.init()
        setupAudioRecorder()
        setupLightSensor()
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

    private func setupLightSensor() {
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        
        captureSession.beginConfiguration()
        
        guard let videoDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        if captureSession.canAddInput(videoDeviceInput) {
            captureSession.addInput(videoDeviceInput)
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        captureSession.commitConfiguration()
        captureSession.startRunning()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        fetchWeatherData(for: "Chicago")
        locationManager.stopUpdatingLocation()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let count = width * height
        
        var luminanceTotal: Float = 0
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let pixel = buffer[y * width + x]
                    luminanceTotal += Float(pixel)
                }
            }
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        let averageLuminance = luminanceTotal / Float(count)
        currentLightLevel = averageLuminance
    }

    func startCollectingData() {
        sensorData.removeAll()
        startTime = Date()
        locationManager.startUpdatingLocation()
    }

    private func fetchWeatherData(for city: String) {
        let apiUrl = "http://api.weatherapi.com/v1/current.json?key=\(apiKey)&q=\(city)"
        
        guard let url = URL(string: apiUrl) else {
            print("Invalid URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] (data, response, error) in
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
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    if let current = json["current"] as? [String: Any], let condition = current["condition"] as? [String: Any], let text = condition["text"] as? String {
                        self.weatherDescription = text
                        self.startSensors()
                    }
                }
            } catch {
                print("Error decoding JSON: \(error)")
                self.startSensors()
            }
        }.resume()
    }

    private func startSensors() {
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
                
                let dataString = "\(Date()),\(accel.x),\(accel.y),\(accel.z),\(gyro.x),\(gyro.y),\(gyro.z),\(audioLevel),\(self.currentLightLevel),\(self.weatherDescription)"
                self.sensorData.append(dataString)
            }
        }

        // Start timer to stop collecting data after 10 seconds
        collectionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            self?.stopCollectingData()
        }
    }

    func stopCollectingData() {
        motionManager.stopDeviceMotionUpdates()
        audioRecorder?.stop()
        collectionTimer?.invalidate()
        collectionTimer = nil
        captureSession?.stopRunning()
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
        let csvText = "Timestamp,AccelX,AccelY,AccelZ,GyroX,GyroY,GyroZ,AudioLevel,LightLevel,Weather\n" + sensorData.joined(separator: "\n")

        do {
            try csvText.write(to: fileName, atomically: true, encoding: .utf8)
            print("Data successfully saved to \(fileName)")
        } catch {
            print("Failed to save data: \(error)")
        }
    }
}

