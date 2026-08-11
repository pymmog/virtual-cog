import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let ble: BleManager
    let settings: RiderSettingsStore
    let session: SessionCoordinator
    let courses: CourseLibrary
    let history: WorkoutHistoryStore

    init(useMocks: Bool = ProcessInfo.processInfo.arguments.contains("--mock-ble")) {
        let settings = RiderSettingsStore.load()
        let ble = BleManager(useMocks: useMocks)
        let courses = CourseLibrary()
        let history = WorkoutHistoryStore()
        self.settings = settings
        self.ble = ble
        self.courses = courses
        self.history = history
        self.session = SessionCoordinator(
            ble: ble,
            settings: settings,
            courses: courses,
            history: history
        )
    }
}
