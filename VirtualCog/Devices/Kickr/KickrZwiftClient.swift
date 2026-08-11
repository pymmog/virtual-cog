import CoreBluetooth
import Foundation

/// Zwift Hub proprietary trainer client — primary path for CORE 2 native virtual shifting.
@MainActor
final class KickrZwiftClient: NSObject, ObservableObject, TrainerControlling {
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var lastTelemetry = LiveTelemetry(source: .hub)
    @Published private(set) var hubAvailable = false

    private weak var manager: BleManager?
    private var peripheral: CBPeripheral?
    private var measurement: CBCharacteristic?
    private var controlPoint: CBCharacteristic?
    private var commandResponse: CBCharacteristic?
    private var mockTimer: Timer?
    private var handshakeSent = false

    func attach(manager: BleManager) {
        self.manager = manager
    }

    func willConnect(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        connectionState = .connecting
        handshakeSent = false
    }

    func didConnect(_ peripheral: CBPeripheral) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        connectionState = .connected
        // Service discovery is shared with FTMS via router; ensure Hub UUID is included there.
    }

    func didFail(_ peripheral: CBPeripheral, message: String) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        connectionState = .failed(message)
        hubAvailable = false
    }

    func didDisconnect(_ peripheral: CBPeripheral) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        connectionState = .reconnecting
        hubAvailable = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, let manager = self.manager, let p = self.peripheral else { return }
            manager.centralManager?.connect(p, options: nil)
        }
    }

    func disconnect() {
        mockTimer?.invalidate()
        mockTimer = nil
        connectionState = .disconnected
        hubAvailable = false
    }

    func connectMock() {
        hubAvailable = true
        connectionState = .ready
        lastTelemetry.source = .mock
        mockTimer?.invalidate()
        mockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                var t = self.lastTelemetry
                t.powerWatts = 185 + Int.random(in: -10...10)
                t.cadenceRpm = 88
                t.hubVirtualSpeedKmh = 33.2
                t.speedKmh = t.hubVirtualSpeedKmh ?? t.speedKmh
                t.source = .mock
                self.lastTelemetry = t
            }
        }
    }

    func requestControl() {
        sendRideOnHandshake()
    }

    func setSimulation(gradePercent: Double, wind: Int32, cwa: UInt32, crr: UInt32) {
        let sim = SimulationParam(
            wind: wind,
            inclineX100: Int32((gradePercent * 100).rounded()),
            cwa: cwa,
            crr: crr
        )
        writeHub(opcode: ZwiftOpcode.hubCommand, payload: HubCommand(simulation: sim).encode())
        lastTelemetry.gradePercent = gradePercent
        lastTelemetry.mode = .sim
    }

    func setGearRatioX10000(_ ratio: UInt32) {
        let physical = PhysicalParam(gearRatioX10000: ratio)
        writeHub(opcode: ZwiftOpcode.hubCommand, payload: HubCommand(physical: physical).encode())
        lastTelemetry.gearRatio = Double(ratio) / 10_000.0
    }

    func setWeights(riderKg: Double, bikeKg: Double) {
        let physical = PhysicalParam(
            bikeWeightX100: UInt32((bikeKg * 100).rounded()),
            riderWeightX100: UInt32((riderKg * 100).rounded())
        )
        writeHub(opcode: ZwiftOpcode.hubCommand, payload: HubCommand(physical: physical).encode())
    }

    func setTargetPower(_ watts: UInt16) {
        writeHub(opcode: ZwiftOpcode.hubCommand, payload: HubCommand(powerTarget: UInt32(watts)).encode())
        lastTelemetry.mode = .erg
    }

    func probeGearRatio() {
        var w = ProtobufWire.Writer()
        w.writeUInt32(field: 1, value: 520)
        writeHub(opcode: ZwiftOpcode.hubInfo, payload: w.data)
    }

    private func sendRideOnHandshake() {
        guard !handshakeSent else { return }
        handshakeSent = true
        writeHubRaw(Data(ZwiftClickCrypto.rideOnASCII))
    }

    private func writeHub(opcode: UInt8, payload: Data) {
        writeHubRaw(ZwiftPacket.wrap(opcode: opcode, payload: payload))
    }

    private func writeHubRaw(_ data: Data) {
        guard let peripheral, let controlPoint else { return }
        peripheral.writeValue(data, for: controlPoint, type: .withResponse)
    }

    private func handleNotification(_ data: Data) {
        if data.starts(with: ZwiftClickCrypto.rideOnASCII) {
            hubAvailable = true
            connectionState = .ready
            return
        }
        guard let packet = ZwiftPacket.unwrap(data) else { return }
        switch packet.opcode {
        case ZwiftOpcode.hubRidingData:
            if let riding = try? HubRidingData.decode(packet.payload) {
                var t = lastTelemetry
                if let p = riding.power { t.powerWatts = Int(p) }
                if let c = riding.cadence { t.cadenceRpm = Double(c) }
                if let s = riding.speedX100 {
                    t.hubVirtualSpeedKmh = Double(s) / 100.0
                    t.speedKmh = t.hubVirtualSpeedKmh ?? t.speedKmh
                }
                if let hr = riding.hr, hr > 0 { t.heartRateBpm = Int(hr) }
                t.source = .hub
                t.maxPower = max(t.maxPower, t.powerWatts)
                lastTelemetry = t
            }
        default:
            break
        }
    }

    // MARK: - Router hooks

    func handleDiscoverServices(_ peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: ZwiftBleIDs.service) }) else {
            return
        }
        peripheral.discoverCharacteristics([
            CBUUID(string: ZwiftBleIDs.measurement),
            CBUUID(string: ZwiftBleIDs.controlPoint),
            CBUUID(string: ZwiftBleIDs.commandResponse)
        ], for: service)
    }

    func handleDiscoverCharacteristics(_ peripheral: CBPeripheral, service: CBService, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        guard service.uuid == CBUUID(string: ZwiftBleIDs.service) else { return }
        for char in service.characteristics ?? [] {
            switch char.uuid {
            case CBUUID(string: ZwiftBleIDs.measurement):
                measurement = char
                peripheral.setNotifyValue(true, for: char)
            case CBUUID(string: ZwiftBleIDs.controlPoint):
                controlPoint = char
            case CBUUID(string: ZwiftBleIDs.commandResponse):
                commandResponse = char
                peripheral.setNotifyValue(true, for: char)
                peripheral.readValue(for: char)
            default:
                break
            }
        }
        sendRideOnHandshake()
    }

    func handleUpdateValue(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier, let data = characteristic.value else { return }
        let uuid = characteristic.uuid.uuidString.uppercased()
        if uuid.contains("00000002") || uuid.contains("00000004") || characteristic.uuid == CBUUID(string: ZwiftBleIDs.measurement) || characteristic.uuid == CBUUID(string: ZwiftBleIDs.commandResponse) {
            handleNotification(data)
        }
    }
}
