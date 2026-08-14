import Combine
import CoreBluetooth
import Foundation

/// Watch-side BLE central that sends live BPM to VirtualCog on Mac.
///
/// watchOS cannot advertise (`CBPeripheralManager` / `CBMutableService` are unavailable),
/// so the Watch scans for the Mac ingest service and writes Heart Rate Measurement packets.
@MainActor
final class HeartRatePeripheral: NSObject, ObservableObject {
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var isAdvertising = false
    @Published private(set) var subscriberCount = 0
    @Published private(set) var lastError: String?

    private var manager: CBCentralManager?
    private var mac: CBPeripheral?
    private var measurement: CBCharacteristic?
    private var queuedStart = false
    private var lastPacket: Data?

    var isMacConnected: Bool { subscriberCount > 0 }

    func start() {
        queuedStart = true
        lastError = nil
        if manager == nil {
            manager = CBCentralManager(delegate: self, queue: .main)
        }
        if bluetoothState == .poweredOn {
            beginScanning()
        }
    }

    func stop() {
        queuedStart = false
        manager?.stopScan()
        if let mac {
            manager?.cancelPeripheralConnection(mac)
        }
        isAdvertising = false
        subscriberCount = 0
        measurement = nil
        lastPacket = nil
        self.mac = nil
    }

    func update(bpm: Int, contactDetected: Bool) {
        let packet = HeartRateMeasurement.notifyPacket(bpm: bpm, contactDetected: contactDetected)
        lastPacket = packet
        guard let mac, let measurement, mac.state == .connected else { return }
        mac.writeValue(packet, for: measurement, type: .withoutResponse)
    }

    private func beginScanning() {
        guard let manager, manager.state == .poweredOn else { return }
        if let mac, mac.state == .connected || mac.state == .connecting {
            isAdvertising = false
            return
        }
        manager.scanForPeripherals(
            withServices: [CBUUID(string: HeartRateUUID.watchIngestService)],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isAdvertising = true
    }

    private func flushLastPacket() {
        guard let lastPacket, let mac, let measurement, mac.state == .connected else { return }
        mac.writeValue(lastPacket, for: measurement, type: .withoutResponse)
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

extension HeartRatePeripheral: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.bluetoothState = central.state
            if central.state == .poweredOn, self.queuedStart {
                self.beginScanning()
            } else if central.state != .poweredOn {
                self.isAdvertising = false
                if self.queuedStart {
                    self.lastError = "Bluetooth unavailable (\(Self.label(for: central.state)))"
                }
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            guard self.queuedStart else { return }
            if let existing = self.mac, existing.identifier == peripheral.identifier,
               existing.state == .connected || existing.state == .connecting {
                return
            }
            central.stopScan()
            self.isAdvertising = false
            self.mac = peripheral
            peripheral.delegate = self
            self.subscriberCount = 0
            self.measurement = nil
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            guard self.mac?.identifier == peripheral.identifier else { return }
            peripheral.discoverServices([CBUUID(string: HeartRateUUID.watchIngestService)])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            guard self.mac?.identifier == peripheral.identifier else { return }
            self.lastError = error?.localizedDescription ?? "Mac connection failed"
            self.subscriberCount = 0
            self.measurement = nil
            if self.queuedStart {
                self.beginScanning()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            guard self.mac?.identifier == peripheral.identifier else { return }
            self.subscriberCount = 0
            self.measurement = nil
            if self.queuedStart {
                self.beginScanning()
            }
        }
    }
}

extension HeartRatePeripheral: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                self.lastError = error.localizedDescription
                return
            }
            guard self.mac?.identifier == peripheral.identifier,
                  let service = peripheral.services?.first(where: {
                      $0.uuid == CBUUID(string: HeartRateUUID.watchIngestService)
                  })
            else { return }
            peripheral.discoverCharacteristics(
                [CBUUID(string: HeartRateUUID.watchIngestMeasurement)],
                for: service
            )
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                self.lastError = error.localizedDescription
                return
            }
            guard self.mac?.identifier == peripheral.identifier else { return }
            guard let char = service.characteristics?.first(where: {
                $0.uuid == CBUUID(string: HeartRateUUID.watchIngestMeasurement)
            }) else {
                self.lastError = "Mac is missing the heart-rate characteristic."
                return
            }
            self.measurement = char
            peripheral.setNotifyValue(true, for: char)
            self.subscriberCount = 1
            self.lastError = nil
            self.flushLastPacket()
        }
    }
}
