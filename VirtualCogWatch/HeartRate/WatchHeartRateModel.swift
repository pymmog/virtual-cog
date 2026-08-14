import Combine
import Foundation
import HealthKit
import WatchConnectivity

/// Starts an indoor cycling workout so watchOS delivers live heart rate, then pushes BPM to BLE.
@MainActor
final class WatchHeartRateModel: NSObject, ObservableObject {
    @Published var bpm: Int?
    @Published var isBroadcasting = false
    @Published var status = "Idle"
    @Published var detail = "Start broadcasting, then keep VirtualCog open on the Mac."
    @Published var subscriberCount = 0
    @Published var usingSimulatedHeartRate = false

    private let healthStore = HKHealthStore()
    private let peripheral = HeartRatePeripheral()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var simTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastHealthSampleAt: Date?

    override init() {
        super.init()
        peripheral.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncPeripheralState()
                }
            }
            .store(in: &cancellables)
        activatePhoneBridge()
    }

    var canBroadcast: Bool { HKHealthStore.isHealthDataAvailable() }

    func toggle() {
        if isBroadcasting {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard !isBroadcasting else { return }
        status = "Requesting Health access…"
        do {
            try await requestAuthorization()
        } catch {
            status = "Health access failed"
            detail = error.localizedDescription
            return
        }

        do {
            try startWorkout()
        } catch {
            status = "Workout failed"
            detail = error.localizedDescription
            return
        }

        peripheral.start()
        isBroadcasting = true
        usingSimulatedHeartRate = false
        status = "Broadcasting"
        detail = "Looking for VirtualCog on Mac…"
        startSimulatorFallbackIfNeeded()
        syncPeripheralState()
    }

    func stop() {
        simTimer?.invalidate()
        simTimer = nil
        peripheral.stop()
        if let session {
            session.end()
        }
        if let builder {
            builder.endCollection(withEnd: Date()) { _, _ in
                builder.finishWorkout { _, _ in }
            }
        }
        session = nil
        builder = nil
        isBroadcasting = false
        usingSimulatedHeartRate = false
        subscriberCount = 0
        status = "Idle"
        detail = "Start broadcasting, then keep VirtualCog open on the Mac."
        pushToPhone()
    }

    private func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(
                domain: "VirtualCogWatch",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Health data is not available on this device."]
            )
        }
        let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        try await healthStore.requestAuthorization(
            toShare: [HKObjectType.workoutType()],
            read: [heartRate]
        )
    }

    private func startWorkout() throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .indoor
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        let start = Date()
        session.startActivity(with: start)
        builder.beginCollection(withStart: start) { _, _ in }
    }

    private func apply(bpm: Int, simulated: Bool) {
        self.bpm = bpm
        usingSimulatedHeartRate = simulated
        if !simulated {
            lastHealthSampleAt = Date()
        }
        peripheral.update(bpm: bpm, contactDetected: !simulated)
        syncPeripheralState()
    }

    private func activatePhoneBridge() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func pushToPhone() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let payload = PhoneWatchPayload(
            bpm: bpm,
            status: status,
            detail: detail,
            isBroadcasting: isBroadcasting,
            macConnected: peripheral.isMacConnected,
            simulated: usingSimulatedHeartRate
        ).asContext()
        try? WCSession.default.updateApplicationContext(payload)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func syncPeripheralState() {
        subscriberCount = peripheral.subscriberCount
        if isBroadcasting {
            if let error = peripheral.lastError {
                status = "Bluetooth error"
                detail = error
            } else if peripheral.isMacConnected {
                status = "Paired with Mac"
                detail = usingSimulatedHeartRate
                    ? "Sending simulated BPM (no live Health sample yet)."
                    : "Streaming live heart rate over Bluetooth."
            } else if peripheral.isAdvertising {
                status = "Looking for Mac"
                detail = "Keep VirtualCog open on the Mac. Chest straps still pair from Setup."
            } else {
                status = "Starting Bluetooth…"
                detail = "Keep this app in the foreground."
            }
        }
        pushToPhone()
    }

    /// Watch Simulator (and some devices before the first optical sample) need a fallback BPM.
    private func startSimulatorFallbackIfNeeded() {
        simTimer?.invalidate()
        simTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isBroadcasting else { return }
                if let last = self.lastHealthSampleAt, Date().timeIntervalSince(last) < 4 {
                    return
                }
                let base = self.bpm ?? 110
                self.apply(bpm: max(80, base + Int.random(in: -1...1)), simulated: true)
            }
        }
    }
}

extension WatchHeartRateModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.pushToPhone()
        }
    }
}

extension WatchHeartRateModel: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.status = "Workout failed"
            self.detail = error.localizedDescription
        }
    }
}

extension WatchHeartRateModel: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType),
              let stats = workoutBuilder.statistics(for: hrType),
              let quantity = stats.mostRecentQuantity()
        else { return }
        let bpm = Int(quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        Task { @MainActor in
            self.apply(bpm: bpm, simulated: false)
        }
    }
}
