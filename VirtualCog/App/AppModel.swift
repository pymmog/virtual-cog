import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let ble: BleManager
    let settings: RiderSettingsStore
    let session: SessionCoordinator
    let courses: CourseLibrary
    let history: WorkoutHistoryStore

    /// Shared tab selection so mock demo can jump Setup → Ride → History.
    @Published var selectedTab: AppTab = .setup
    /// FIT ready to share after ending a ride (cleared once presented).
    @Published var pendingFitShareURL: URL?

    private var cancellables = Set<AnyCancellable>()

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
        bindChildren()
        if useMocks {
            ble.bootstrapMocks()
        }
    }

    /// One-tap path for `--mock-ble`: pair mock devices, pick a course, start riding.
    func startMockDemoRide() {
        guard ble.useMocks else { return }
        ble.connectAllMocks()
        if courses.selected == nil {
            courses.selected = courses.courses.first
        }
        session.preferHub = settings.preferHubOverFtms
        selectedTab = .ride
        if session.isRiding || session.isPaused {
            session.endRide()
        }
        session.startRide()
    }

    func endMockDemoRide() {
        endRide(offerExport: true, switchToHistory: true)
    }

    /// Ends the current ride and optionally queues the FIT for Share.
    func endRide(offerExport: Bool = true, switchToHistory: Bool = false) {
        guard session.isRiding || session.isPaused else { return }
        session.endRide()
        if switchToHistory {
            selectedTab = .history
        }
        guard offerExport, let summary = history.items.first, let url = history.fitURL(for: summary) else {
            return
        }
        pendingFitShareURL = url
    }

    func shareFit(for summary: WorkoutSummary) {
        guard let url = history.fitURL(for: summary) else { return }
        FitExportUI.presentShareSheet(for: url)
    }

    func presentPendingFitShareIfNeeded() {
        guard let url = pendingFitShareURL else { return }
        pendingFitShareURL = nil
        FitExportUI.presentShareSheet(for: url)
    }

    private func bindChildren() {
        let relay = { [weak self] in
            self?.objectWillChange.send()
        }
        ble.objectWillChange.sink { _ in relay() }.store(in: &cancellables)
        session.objectWillChange.sink { _ in relay() }.store(in: &cancellables)
        courses.objectWillChange.sink { _ in relay() }.store(in: &cancellables)
        settings.objectWillChange.sink { _ in relay() }.store(in: &cancellables)
        history.objectWillChange.sink { _ in relay() }.store(in: &cancellables)
    }
}
