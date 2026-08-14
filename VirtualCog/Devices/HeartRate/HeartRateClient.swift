import CoreBluetooth
import Foundation

/// BLE Heart Rate Profile central (0x180D) for chest straps.
/// VirtualCog Watch BPM is applied via `HeartRateIngestPeripheral`.
@MainActor
final class HeartRateClient: NSObject, ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var lastBpm: Int?
    @Published private(set) var lastSampleAt: Date?
    @Published private(set) var deviceName: String?
    @Published private(set) var bodySensorLocation: String?

    private weak var manager: BleManager?
    private var peripheral: CBPeripheral?
    private var measurement: CBCharacteristic?
    private var mockTimer: Timer?
    private let staleAfter: TimeInterval = 8

    var hasFreshSample: Bool {
        guard lastBpm != nil, let lastSampleAt else { return false }
        return Date().timeIntervalSince(lastSampleAt) <= staleAfter
    }

    /// Latest BPM if the monitor notified recently.
    var freshBpm: Int? { hasFreshSample ? lastBpm : nil }

    func attach(manager: BleManager) {
        self.manager = manager
    }

    func willConnect(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        deviceName = peripheral.name
        connectionState = .connecting
    }

    func didConnect(_ peripheral: CBPeripheral) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        connectionState = .connected
        deviceName = peripheral.name ?? deviceName
        peripheral.discoverServices([
            CBUUID(string: HeartRateUUID.serviceCBUUIDString),
            CBUUID(string: String(format: "%04X", FTMSUUID.battery)),
            CBUUID(string: String(format: "%04X", FTMSUUID.deviceInformation))
        ])
    }

    func didFail(_ peripheral: CBPeripheral, message: String) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        connectionState = .failed(message)
    }

    func didDisconnect(_ peripheral: CBPeripheral) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        connectionState = .reconnecting
        measurement = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, let manager = self.manager, let p = self.peripheral else { return }
            manager.centralManager?.connect(p, options: nil)
        }
    }

    func disconnect() {
        mockTimer?.invalidate()
        mockTimer = nil
        lastBpm = nil
        lastSampleAt = nil
        deviceName = nil
        bodySensorLocation = nil
        connectionState = .disconnected
    }

    /// Latest BPM from VirtualCog Watch. Ignored while a chest strap is connected.
    func applyFromWatch(bpm: Int) {
        guard !hasActiveStrap else { return }
        deviceName = HeartRateUUID.watchAdvertisedName
        bodySensorLocation = "Wrist"
        apply(bpm: bpm)
        connectionState = .ready
    }

    func watchDisconnected() {
        guard !hasActiveStrap else { return }
        guard deviceName == HeartRateUUID.watchAdvertisedName else { return }
        lastBpm = nil
        lastSampleAt = nil
        deviceName = nil
        bodySensorLocation = nil
        connectionState = .disconnected
    }

    private var hasActiveStrap: Bool {
        peripheral != nil && (
            connectionState == .ready
                || connectionState == .connected
                || connectionState == .connecting
                || connectionState == .reconnecting
        )
    }

    func connectMock() {
        connectionState = .ready
        deviceName = "VirtualCog HR (Mock)"
        bodySensorLocation = "Wrist"
        mockTimer?.invalidate()
        mockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.apply(bpm: 148 + Int.random(in: -3...3))
            }
        }
        apply(bpm: 148)
    }

    func handleDiscoverServices(_ peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func handleDiscoverCharacteristics(_ peripheral: CBPeripheral, service: CBService, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        let serviceID = service.uuid.uuidString.uppercased()
        for char in service.characteristics ?? [] {
            let uuid = char.uuid.uuidString.uppercased()
            if serviceID.contains(HeartRateUUID.serviceCBUUIDString),
               uuid.contains(HeartRateUUID.measurementCBUUIDString) {
                measurement = char
                peripheral.setNotifyValue(true, for: char)
                connectionState = .ready
            } else if uuid.contains(HeartRateUUID.bodySensorLocationCBUUIDString) {
                peripheral.readValue(for: char)
            }
        }
    }

    func handleUpdateValue(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier, let data = characteristic.value else { return }
        let uuid = characteristic.uuid.uuidString.uppercased()
        if uuid.contains(HeartRateUUID.measurementCBUUIDString),
           let parsed = HeartRateMeasurement.parse(data), parsed.bpm > 0 {
            apply(bpm: parsed.bpm)
        } else if uuid.contains(HeartRateUUID.bodySensorLocationCBUUIDString), let location = data.first {
            bodySensorLocation = Self.locationName(location)
        }
    }

    private func apply(bpm: Int) {
        lastBpm = bpm
        lastSampleAt = Date()
        if connectionState == .connected || connectionState == .reconnecting {
            connectionState = .ready
        }
    }

    private static func locationName(_ value: UInt8) -> String {
        switch value {
        case 1: return "Chest"
        case 2: return "Wrist"
        case 3: return "Finger"
        case 4: return "Hand"
        case 5: return "Ear lobe"
        case 6: return "Foot"
        default: return "Other"
        }
    }
}
