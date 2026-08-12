import Combine
import Foundation

enum SessionPhase: Equatable {
    case idle
    case connected
    case riding
    case paused
    case ended
}

@MainActor
final class SessionCoordinator: ObservableObject {
    @Published private(set) var phase: SessionPhase = .idle
    @Published private(set) var gear = GearModel()
    @Published var mode: TrainerMode = .sim
    @Published var manualGradePercent: Double = 0
    @Published var ergTargetWatts: UInt16 = 200
    @Published private(set) var distanceMeters: Double = 0
    @Published var preferHub: Bool = true

    let telemetry = TelemetryStore()
    let recorder = WorkoutRecorder()

    private let ble: BleManager
    private let settings: RiderSettingsStore
    private let courses: CourseLibrary
    private let history: WorkoutHistoryStore
    private var tickTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastTick: Date?

    var canStart: Bool {
        (ble.kickrHub.connectionState == .ready || ble.kickrFtms.connectionState == .ready)
            && (phase == .idle || phase == .connected || phase == .ended)
    }

    var isRiding: Bool { phase == .riding }
    var isPaused: Bool { phase == .paused }

    init(ble: BleManager, settings: RiderSettingsStore, courses: CourseLibrary, history: WorkoutHistoryStore) {
        self.ble = ble
        self.settings = settings
        self.courses = courses
        self.history = history
        self.preferHub = settings.preferHubOverFtms
        self.gear.calibrationOffset = settings.gearCalibrationOffset

        ble.click.onShift = { [weak self] event in
            self?.handleShift(event)
        }

        telemetry.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        ble.heartRate.$lastBpm
            .receive(on: RunLoop.main)
            .sink { [weak self] bpm in
                guard let self else { return }
                self.telemetry.applyHeartRateMonitor(self.ble.heartRate.freshBpm ?? bpm)
            }
            .store(in: &cancellables)

        // Keep phase in sync with connections.
        Publishers.CombineLatest(ble.kickrHub.$connectionState, ble.kickrFtms.$connectionState)
            .receive(on: RunLoop.main)
            .sink { [weak self] hub, ftms in
                guard let self else { return }
                if self.phase == .idle || self.phase == .ended {
                    if hub == .ready || ftms == .ready {
                        self.phase = .connected
                    }
                }
            }
            .store(in: &cancellables)
    }

    func startRide() {
        guard canStart else { return }
        distanceMeters = 0
        telemetry.reset()
        recorder.begin(courseName: courses.selected?.name ?? "Free Ride")
        gear.lockBaseline()
        pushWeights()
        pushGear()
        if mode == .sim {
            pushSimulation(grade: currentGrade())
        } else {
            activeTrainer()?.setTargetPower(ergTargetWatts)
        }
        phase = .riding
        lastTick = Date()
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func togglePause() {
        if phase == .riding {
            phase = .paused
            lastTick = nil
        } else if phase == .paused {
            phase = .riding
            lastTick = Date()
        }
    }

    func endRide() {
        tickTimer?.invalidate()
        tickTimer = nil
        phase = .ended
        if let summary = recorder.finish(telemetry: telemetry.live) {
            history.add(summary)
        }
    }

    func setMode(_ newMode: TrainerMode) {
        mode = newMode
        guard phase == .riding || phase == .paused else { return }
        switch newMode {
        case .sim:
            pushSimulation(grade: currentGrade())
            pushGear()
        case .erg:
            activeTrainer()?.setTargetPower(ergTargetWatts)
        case .level:
            break
        }
    }

    func updateManualGrade(_ value: Double) {
        manualGradePercent = value
        if mode == .sim, courses.selected == nil || phase == .connected {
            pushSimulation(grade: value)
        }
    }

    func updateERG(_ watts: UInt16) {
        ergTargetWatts = watts
        if mode == .erg {
            activeTrainer()?.setTargetPower(watts)
        }
    }

    private func handleShift(_ event: ClickDebouncer.Event) {
        // Virtual shifting feel is SIM-only.
        guard mode == .sim else { return }
        switch event {
        case .shiftUp: _ = gear.shiftUp()
        case .shiftDown: _ = gear.shiftDown()
        }
        pushGear()
    }

    private func tick() {
        guard phase == .riding else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastTick ?? now)
        lastTick = now

        let sample = preferHub && ble.kickrHub.hubAvailable
            ? ble.kickrHub.lastTelemetry
            : ble.kickrFtms.lastTelemetry

        let speedMs = max(0, sample.speedKmh) / 3.6
        distanceMeters += speedMs * dt
        let grade = currentGrade()
        if mode == .sim {
            pushSimulation(grade: grade)
        }

        telemetry.applyTrainer(sample, gear: gear, mode: mode, grade: grade, distance: distanceMeters)
        telemetry.applyHeartRateMonitor(ble.heartRate.freshBpm)
        let elevation = courses.selected?.points.last(where: { $0.distanceMeters <= distanceMeters })?.elevationMeters ?? 0
        telemetry.tickMoving(isMoving: sample.cadenceRpm > 20 || speedMs > 0.5, elevation: elevation, now: now)
        telemetry.updateClickBattery(ble.click.batteryPercent)
        recorder.append(telemetry.live, at: now)
    }

    private func currentGrade() -> Double {
        if let course = courses.selected, phase == .riding || phase == .paused {
            return course.grade(atDistance: distanceMeters)
        }
        return manualGradePercent
    }

    private func pushSimulation(grade: Double) {
        activeTrainer()?.setSimulation(
            gradePercent: grade,
            wind: ZwiftSimDefaults.wind,
            cwa: settings.cwaScaled,
            crr: settings.crrScaled
        )
    }

    private func pushGear() {
        guard mode == .sim else { return }
        activeTrainer()?.setGearRatioX10000(gear.ratioX10000)
    }

    private func pushWeights() {
        activeTrainer()?.setWeights(riderKg: settings.riderWeightKg, bikeKg: settings.bikeWeightKg)
    }

    private func activeTrainer() -> TrainerControlling? {
        if preferHub, ble.kickrHub.hubAvailable || ble.kickrHub.connectionState == .ready {
            return ble.kickrHub
        }
        if ble.kickrFtms.connectionState == .ready {
            return ble.kickrFtms
        }
        if ble.kickrHub.connectionState == .ready {
            return ble.kickrHub
        }
        return nil
    }
}
