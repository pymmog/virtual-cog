import SwiftUI

@main
struct VirtualCogApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Session") {
                if appModel.ble.useMocks {
                    Button("Start Demo Ride") {
                        appModel.startMockDemoRide()
                    }
                    .keyboardShortcut("d", modifiers: [.command])
                }

                Button("Start Ride") {
                    appModel.session.startRide()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!appModel.session.canStart)

                Button(appModel.session.isPaused ? "Resume" : "Pause") {
                    appModel.session.togglePause()
                }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(!appModel.session.isRiding)

                Button("End Ride") {
                    appModel.endRide(offerExport: true, switchToHistory: appModel.ble.useMocks)
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(!appModel.session.isRiding && !appModel.session.isPaused)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }
}
