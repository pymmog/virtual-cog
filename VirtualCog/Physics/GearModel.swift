import Foundation

/// 24 linear virtual gears used by KICKR CORE 2 / Zwift Click path.
struct GearModel: Equatable {
    static let minGear = 1
    static let maxGear = 24
    static let baselineGear = 12

    /// GearRatioX10000 for gears 1…24.
    /// Linear progression covering a wide single-speed VS range.
    /// Mid gear (~12) sits near a typical 2.8 physical chainring/cog baseline.
    static let defaultRatiosX10000: [UInt32] = {
        let minR = 8000.0   // 0.80
        let maxR = 38000.0  // 3.80
        return (0..<24).map { i in
            let t = Double(i) / 23.0
            return UInt32((minR + (maxR - minR) * t).rounded())
        }
    }()

    private(set) var gearIndex: Int
    var calibrationOffset: Int
    var ratiosX10000: [UInt32]

    init(
        gearIndex: Int = GearModel.baselineGear,
        calibrationOffset: Int = 0,
        ratiosX10000: [UInt32] = GearModel.defaultRatiosX10000
    ) {
        precondition(ratiosX10000.count == 24)
        self.gearIndex = min(max(gearIndex, Self.minGear), Self.maxGear)
        self.calibrationOffset = calibrationOffset
        self.ratiosX10000 = ratiosX10000
    }

    var ratioX10000: UInt32 {
        let idx = gearIndex - 1
        let base = ratiosX10000[idx]
        let calibrated = Int(base) + calibrationOffset * 100
        return UInt32(max(1000, calibrated))
    }

    var ratio: Double { Double(ratioX10000) / 10_000.0 }

    @discardableResult
    mutating func shiftUp() -> Bool {
        guard gearIndex < Self.maxGear else { return false }
        gearIndex += 1
        return true
    }

    @discardableResult
    mutating func shiftDown() -> Bool {
        guard gearIndex > Self.minGear else { return false }
        gearIndex -= 1
        return true
    }

    mutating func setGear(_ value: Int) {
        gearIndex = min(max(value, Self.minGear), Self.maxGear)
    }

    mutating func lockBaseline() {
        gearIndex = Self.baselineGear
    }
}

/// Debounces Click plus/minus so held buttons don't repeat-spam gear changes.
struct ClickDebouncer {
    var minimumInterval: TimeInterval = 0.18
    private var lastPlusAt: Date?
    private var lastMinusAt: Date?
    private var plusWasDown = false
    private var minusWasDown = false

    init(minimumInterval: TimeInterval = 0.18) {
        self.minimumInterval = minimumInterval
    }

    enum Event: Equatable {
        case shiftUp
        case shiftDown
    }

    mutating func process(plusDown: Bool, minusDown: Bool, now: Date = Date()) -> [Event] {
        var events: [Event] = []
        if plusDown && !plusWasDown {
            if lastPlusAt == nil || now.timeIntervalSince(lastPlusAt!) >= minimumInterval {
                events.append(.shiftUp)
                lastPlusAt = now
            }
        }
        if minusDown && !minusWasDown {
            if lastMinusAt == nil || now.timeIntervalSince(lastMinusAt!) >= minimumInterval {
                events.append(.shiftDown)
                lastMinusAt = now
            }
        }
        plusWasDown = plusDown
        minusWasDown = minusDown
        return events
    }
}
