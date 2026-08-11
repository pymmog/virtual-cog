import Combine
import Foundation

@MainActor
final class RiderSettingsStore: ObservableObject {
    @Published var riderWeightKg: Double = 75.0
    @Published var bikeWeightKg: Double = 8.0
    @Published var preferHubOverFtms: Bool = true
    @Published var crrScaled: UInt32 = ZwiftSimDefaults.crr
    @Published var cwaScaled: UInt32 = ZwiftSimDefaults.cwa
    @Published var gearCalibrationOffset: Int = 0

    private static let defaultsKey = "virtualcog.riderSettings"

    struct Snapshot: Codable {
        var riderWeightKg: Double
        var bikeWeightKg: Double
        var preferHubOverFtms: Bool
        var crrScaled: UInt32
        var cwaScaled: UInt32
        var gearCalibrationOffset: Int
    }

    static func load() -> RiderSettingsStore {
        let store = RiderSettingsStore()
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return store }
        store.riderWeightKg = decoded.riderWeightKg
        store.bikeWeightKg = decoded.bikeWeightKg
        store.preferHubOverFtms = decoded.preferHubOverFtms
        store.crrScaled = decoded.crrScaled
        store.cwaScaled = decoded.cwaScaled
        store.gearCalibrationOffset = decoded.gearCalibrationOffset
        return store
    }

    func save() {
        let snap = Snapshot(
            riderWeightKg: riderWeightKg,
            bikeWeightKg: bikeWeightKg,
            preferHubOverFtms: preferHubOverFtms,
            crrScaled: crrScaled,
            cwaScaled: cwaScaled,
            gearCalibrationOffset: gearCalibrationOffset
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

enum ZwiftSimDefaults {
    /// CdA * 10000 ≈ 0.51
    static let cwa: UInt32 = 5100
    /// Crr * 100000 ≈ 0.004
    static let crr: UInt32 = 400
    static let wind: Int32 = 0
}
