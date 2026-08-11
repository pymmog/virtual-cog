import Foundation

@MainActor
final class TelemetryStore: ObservableObject {
    @Published private(set) var live = LiveTelemetry()
    private var powerSamples: [Int] = []
    private var movingStartedAt: Date?
    private var accumulatedMoving: TimeInterval = 0
    private var lastElevation: Double?

    func reset() {
        live = LiveTelemetry()
        powerSamples = []
        movingStartedAt = nil
        accumulatedMoving = 0
        lastElevation = nil
    }

    func applyTrainer(_ sample: LiveTelemetry, gear: GearModel, mode: TrainerMode, grade: Double, distance: Double) {
        var next = live
        next.powerWatts = sample.powerWatts
        next.cadenceRpm = sample.cadenceRpm
        next.speedKmh = sample.speedKmh
        next.hubVirtualSpeedKmh = sample.hubVirtualSpeedKmh
        next.ftmsWheelSpeedKmh = sample.ftmsWheelSpeedKmh
        if let hr = sample.heartRateBpm { next.heartRateBpm = hr }
        next.gradePercent = grade
        next.gearIndex = gear.gearIndex
        next.gearRatio = gear.ratio
        next.mode = mode
        next.distanceMeters = distance
        next.source = sample.source
        next.maxPower = max(next.maxPower, sample.powerWatts)
        powerSamples.append(sample.powerWatts)
        if powerSamples.count > 0 {
            next.averagePower = Double(powerSamples.reduce(0, +)) / Double(powerSamples.count)
        }
        live = next
    }

    func tickMoving(isMoving: Bool, elevation: Double, now: Date = Date()) {
        if isMoving {
            if movingStartedAt == nil { movingStartedAt = now }
        } else if let started = movingStartedAt {
            accumulatedMoving += now.timeIntervalSince(started)
            movingStartedAt = nil
        }
        var next = live
        var moving = accumulatedMoving
        if let started = movingStartedAt {
            moving += now.timeIntervalSince(started)
        }
        next.movingTimeSeconds = moving
        if let lastElevation {
            let gain = elevation - lastElevation
            if gain > 0 { next.elevationGainMeters += gain }
        }
        lastElevation = elevation
        live = next
    }

    /// Normalized Power / Intensity Factor / TSS-style estimates (simplified).
    func loadEstimate(ftp: Double) -> (np: Double, intensityFactor: Double, tss: Double) {
        guard powerSamples.count >= 30, ftp > 0 else { return (0, 0, 0) }
        // 30-second rolling average, raised to 4th power — classic NP approximation.
        var powered: [Double] = []
        var window: [Double] = []
        for p in powerSamples {
            window.append(Double(p))
            if window.count > 30 { window.removeFirst() }
            if window.count == 30 {
                let avg = window.reduce(0, +) / 30.0
                powered.append(pow(avg, 4))
            }
        }
        guard !powered.isEmpty else { return (0, 0, 0) }
        let np = pow(powered.reduce(0, +) / Double(powered.count), 0.25)
        let iff = np / ftp
        let hours = live.movingTimeSeconds / 3600.0
        let tss = (hours * np * iff) / ftp * 100.0
        return (np, iff, tss)
    }
}
