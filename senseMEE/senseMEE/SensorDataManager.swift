import CoreMotion
import Foundation

class SensorDataManager: ObservableObject {
    private var motionManager: CMMotionManager
    private var timer: Timer?
    @Published var sensorData: [String] = []

    init() {
        motionManager = CMMotionManager()
        motionManager.accelerometerUpdateInterval = 0.01
        motionManager.gyroUpdateInterval = 0.01
    }

    func startCollectingData() {
        if motionManager.isAccelerometerAvailable && motionManager.isGyroAvailable {
            motionManager.startAccelerometerUpdates()
            motionManager.startGyroUpdates()
            timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                self.fetchData()
            }
        }
    }

    private func fetchData() {
        if let accelData = motionManager.accelerometerData, let gyroData = motionManager.gyroData {
            let timestamp = Date().timeIntervalSince1970
            let dataString = "\(timestamp),\(accelData.acceleration.x),\(accelData.acceleration.y),\(accelData.acceleration.z),\(gyroData.rotationRate.x),\(gyroData.rotationRate.y),\(gyroData.rotationRate.z)"
            DispatchQueue.main.async {
                self.sensorData.append(dataString)
            }
        }
    }

    func stopCollectingData() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        timer?.invalidate()
        timer = nil
        exportDataToCSV()
    }

    private func exportDataToCSV() {
        let fileName = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("sensorData.csv")
        let csvText = "Timestamp,AccelX,AccelY,AccelZ,GyroX,GyroY,GyroZ\n" + sensorData.joined(separator: "\n")
        
        do {
            try csvText.write(to: fileName, atomically: true, encoding: .utf8)
            print("Data successfully saved to \(fileName)")
        } catch {
            print("Failed to save data: \(error)")
        }
    }
}

