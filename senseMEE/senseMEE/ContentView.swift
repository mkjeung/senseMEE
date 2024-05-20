import SwiftUI

struct ContentView: View {
    @ObservedObject var sensorDataManager = SensorDataManager()

    var body: some View {
        VStack {
            Text("Activity Prediction")
                .font(.largeTitle)
                .padding()
            
            Text(sensorDataManager.predictedActivity)
                .font(.title)
                .padding()
                .foregroundColor(.blue)
            
            Spacer()
        }
        .onAppear {
            sensorDataManager.startDataCollectionLoop() 
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}




//import SwiftUI
//
//struct ContentView: View {
//    @StateObject private var sensorDataManager = SensorDataManager()
//
//    var body: some View {
//        VStack {
//            Text("Time remaining: \(sensorDataManager.remainingTime) seconds")
//                .font(.title)
//                .padding()
//
//            Button(action: {
//                sensorDataManager.startCollectingData()
//            }) {
//                Text("Start Collecting Data")
//                    .padding()
//                    .background(Color.blue)
//                    .foregroundColor(.white)
//                    .cornerRadius(10)
//            }
//            .padding()
//            
//            if sensorDataManager.isCollectingData {
//                Text("Collecting data...")
//                    .foregroundColor(.red)
//            } else {
//                Text("Data collection stopped")
//                    .foregroundColor(.green)
//            }
//        }
//        .padding()
//    }
//}
//
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}

