import Foundation

/// App-side physics helpers. Trainer firmware owns SIM load when Hub params are set;
/// this module advances course distance and exposes grade for UI / incline writes.
enum PhysicsEngine {
    static func distanceDeltaMeters(speedKmh: Double, dt: TimeInterval) -> Double {
        max(0, speedKmh) / 3.6 * max(0, dt)
    }

    static func inclineX100(gradePercent: Double) -> Int32 {
        Int32((gradePercent * 100).rounded())
    }

    static func weightX100(kg: Double) -> UInt32 {
        UInt32((kg * 100).rounded())
    }
}
