import SwiftUI

@main
struct VirtualCogWatchApp: App {
    @StateObject private var model = WatchHeartRateModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
        }
    }
}
