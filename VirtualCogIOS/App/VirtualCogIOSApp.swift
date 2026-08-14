import SwiftUI

@main
struct VirtualCogIOSApp: App {
    @StateObject private var model = PhoneHeartRateModel()

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(model)
        }
    }
}
