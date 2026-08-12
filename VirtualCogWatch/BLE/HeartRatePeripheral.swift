import Combine
import CoreBluetooth
import Foundation

/// Watch-side BLE peripheral that advertises the standard Heart Rate Profile (0x180D).
final class HeartRatePeripheral: NSObject, ObservableObject {
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var isAdvertising = false
    @Published private(set) var subscriberCount = 0
    @Published private(set) var lastError: String?

    private var manager: CBPeripheralManager?
    private var measurement: CBMutableCharacteristic?
    private var queuedStart = false
    private var lastPacket: Data?

    var isMacConnected: Bool { subscriberCount > 0 }

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
        subscriberCount = 0
        measurement = nil
        lastPacket = nil
    }

    func update(bpm: Int, contactDetected: Bool) {
        let packet = HeartRateMeasurement.notifyPacket(bpm: bpm, contactDetected: contactDetected)
        lastPacket = packet
        guard let measurement, let manager, manager.state == .poweredOn else { return }
        manager.updateValue(packet, for: measurement, onSubscribedCentrals: nil)
    }

    private func beginAdvertising() {
        guard let manager, manager.state == .poweredOn else { return }
        manager.removeAllServices()

        let measurement = CBMutableCharacteristic(
            type: CBUUID(string: HeartRateUUID.measurementCBUUIDString),
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        let location = CBMutableCharacteristic(
            type: CBUUID(string: HeartRateUUID.bodySensorLocationCBUUIDString),
            properties: [.read],
            value: Data([HeartRateMeasurement.wristLocation]),
            permissions: [.readable]
        )
        let service = CBMutableService(type: CBUUID(string: HeartRateUUID.serviceCBUUIDString), primary: true)
        service.characteristics = [measurement, location]
        self.measurement = measurement
        manager.add(service)
    }
}

extension HeartRatePeripheral: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        bluetoothState = peripheral.state
        if peripheral.state == .poweredOn, queuedStart {
            beginAdvertising()
        } else if peripheral.state != .poweredOn {
            isAdvertising = false
            if queuedStart {
                lastError = "Bluetooth unavailable (\(Self.label(for: peripheral.state)))"
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            lastError = error.localizedDescription
            isAdvertising = false
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: HeartRateUUID.serviceCBUUIDString)],
            CBAdvertisementDataLocalNameKey: HeartRateUUID.watchAdvertisedName
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            lastError = error.localizedDescription
            isAdvertising = false
            return
        }
        isAdvertising = true
        lastError = nil
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        subscriberCount += 1
        if let lastPacket, let measurement {
            peripheral.updateValue(lastPacket, for: measurement, onSubscribedCentrals: [central])
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscriberCount = max(0, subscriberCount - 1)
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
