import CoreBluetooth
import Foundation

/// Mac-side BLE peripheral that accepts heart-rate writes from VirtualCog Watch.
///
/// watchOS cannot advertise the Heart Rate Profile, so this process listens instead.
@MainActor
final class HeartRateIngestPeripheral: NSObject, ObservableObject {
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var isAdvertising = false
    @Published private(set) var watchConnected = false
    @Published private(set) var lastError: String?

    private var manager: CBPeripheralManager?
    private var measurement: CBMutableCharacteristic?
    private weak var heartRate: HeartRateClient?
    private var queuedStart = false

    func attach(heartRate: HeartRateClient) {
        self.heartRate = heartRate
    }

    func start() {
        queuedStart = true
        lastError = nil
        if manager == nil {
            manager = CBPeripheralManager(delegate: self, queue: .main)
        }
        if bluetoothState == .poweredOn {
            beginAdvertising()
        }
    }

    func stop() {
        queuedStart = false
        manager?.stopAdvertising()
        manager?.removeAllServices()
        isAdvertising = false
        watchConnected = false
        measurement = nil
        heartRate?.watchDisconnected()
    }

    private func beginAdvertising() {
        guard let manager, manager.state == .poweredOn else { return }
        manager.removeAllServices()

        let measurement = CBMutableCharacteristic(
            type: CBUUID(string: HeartRateUUID.watchIngestMeasurement),
            properties: [.write, .writeWithoutResponse, .notify, .read],
            value: nil,
            permissions: [.writeable, .readable]
        )
        let service = CBMutableService(type: CBUUID(string: HeartRateUUID.watchIngestService), primary: true)
        service.characteristics = [measurement]
        self.measurement = measurement
        manager.add(service)
    }

    private func handleWrite(_ data: Data) {
        guard let parsed = HeartRateMeasurement.parse(data), parsed.bpm > 0 else { return }
        heartRate?.applyFromWatch(bpm: parsed.bpm)
    }

    private static func label(for state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return "on"
        case .poweredOff: return "off"
        case .unauthorized: return "unauthorized"
        case .unsupported: return "unsupported"
        case .resetting: return "resetting"
        default: return "unknown"
        }
    }
}

extension HeartRateIngestPeripheral: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            self.bluetoothState = peripheral.state
            if peripheral.state == .poweredOn, self.queuedStart {
                self.beginAdvertising()
            } else if peripheral.state != .poweredOn {
                self.isAdvertising = false
                self.watchConnected = false
                if self.queuedStart {
                    self.lastError = "Bluetooth unavailable (\(Self.label(for: peripheral.state)))"
                }
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                self.lastError = error.localizedDescription
                self.isAdvertising = false
                return
            }
            peripheral.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: HeartRateUUID.watchIngestService)],
                CBAdvertisementDataLocalNameKey: HeartRateUUID.macAdvertisedName
            ])
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        Task { @MainActor in
            if let error {
                self.lastError = error.localizedDescription
                self.isAdvertising = false
                return
            }
            self.isAdvertising = true
            self.lastError = nil
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        Task { @MainActor in
            self.watchConnected = true
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        Task { @MainActor in
            self.watchConnected = false
            self.heartRate?.watchDisconnected()
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        var packets: [Data] = []
        for request in requests {
            if let data = request.value, !data.isEmpty {
                packets.append(data)
            }
            if request.characteristic.properties.contains(.write) {
                peripheral.respond(to: request, withResult: .success)
            }
        }
        Task { @MainActor in
            self.watchConnected = true
            for data in packets {
                self.handleWrite(data)
            }
        }
    }
}
