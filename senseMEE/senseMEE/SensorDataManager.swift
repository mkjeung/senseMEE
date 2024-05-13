import CoreMotion
import Foundation

class SensorDataManager: ObservableObject {
    private var motionManager: CMMotionManager
    private var collectionTimer: Timer?
    @Published var sensorData: [String] = []
    private var startTime: Date?

    init() {
        motionManager = CMMotionManager()
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
    }

    func startCollectingData() {
        sensorData.removeAll()
        startTime = Date()

        if motionManager.isDeviceMotionAvailable {
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
                guard let motion = motion, error == nil else {
                    print("Error receiving motion data: \(error!)")
                    return
                }

                let accel = motion.userAcceleration
                let gyro = motion.rotationRate

                let dataString = "\(Date()),\(accel.x),\(accel.y),\(accel.z),\(gyro.x),\(gyro.y),\(gyro.z)"
                self?.sensorData.append(dataString)
            }
        }

        // Start timer to stop collecting data after 10 seconds
        collectionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            self?.stopCollectingData()
        }
    }

    func stopCollectingData() {
        motionManager.stopDeviceMotionUpdates()
        collectionTimer?.invalidate()
        collectionTimer = nil
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
        let csvText = "Timestamp,AccelX,AccelY,AccelZ,GyroX,GyroY,GyroZ\n" + sensorData.joined(separator: "\n")

        do {
            try csvText.write(to: fileName, atomically: true, encoding: .utf8)
            print("Data successfully saved to \(fileName)")
        } catch {
            print("Failed to save data: \(error)")
        }
    }
}

