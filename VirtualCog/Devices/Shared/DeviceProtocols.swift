import Foundation

enum TrainerMode: String, Codable, CaseIterable, Identifiable {
    case sim
    case erg
    case level

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sim: return "SIM"
        case .erg: return "ERG"
        case .level: return "Level"
        }
    }
}

enum ConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case connected
    case ready
    case reconnecting
    case disconnected
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .scanning: return "Scanning"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .ready: return "Ready"
        case .reconnecting: return "Reconnecting…"
        case .disconnected: return "Disconnected"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }
}

struct LiveTelemetry: Equatable {
    var powerWatts: Int = 0
    var cadenceRpm: Double = 0
    var speedKmh: Double = 0
    var hubVirtualSpeedKmh: Double?
    var ftmsWheelSpeedKmh: Double?
    var heartRateBpm: Int?
    var heartRateSource: HeartRateSource = .none
    var gradePercent: Double = 0
    var gearIndex: Int = GearModel.baselineGear
    var gearRatio: Double = 0
    var mode: TrainerMode = .sim
    var distanceMeters: Double = 0
    var elevationGainMeters: Double = 0
    var movingTimeSeconds: TimeInterval = 0
    var averagePower: Double = 0
    var maxPower: Int = 0
    var clickBatteryPercent: Int?
    var trainerRSSI: Int?
    var clickRSSI: Int?
    var source: TelemetrySource = .none
}

enum TelemetrySource: String, Equatable {
    case none
    case ftms
    case hub
    case mock
}

enum HeartRateSource: String, Equatable {
    case none
    case trainerBridge
    case heartRateMonitor

    var title: String {
        switch self {
        case .none: return "No HR"
        case .trainerBridge: return "Trainer"
        case .heartRateMonitor: return "Watch / HRM"
        }
    }
}

@MainActor
protocol TrainerControlling: AnyObject {
    var connectionState: ConnectionState { get }
    var lastTelemetry: LiveTelemetry { get }

    func setSimulation(gradePercent: Double, wind: Int32, cwa: UInt32, crr: UInt32)
    func setGearRatioX10000(_ ratio: UInt32)
    func setWeights(riderKg: Double, bikeKg: Double)
    func setTargetPower(_ watts: UInt16)
    func requestControl()
}

@MainActor
protocol ShifterControlling: AnyObject {
    var connectionState: ConnectionState { get }
    var onShift: ((ClickDebouncer.Event) -> Void)? { get set }
    var batteryPercent: Int? { get }
}
