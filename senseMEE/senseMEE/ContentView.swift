import SwiftUI

struct ContentView: View {
    @ObservedObject var sensorDataManager = SensorDataManager()

    var body: some View {
        VStack(spacing: 20) {
            Button("Start Collecting Data") {
                sensorDataManager.startCollectingData()
            }
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)

            Button("Stop Collecting Data") {
                sensorDataManager.stopCollectingData()
            }
            .padding()
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
}

