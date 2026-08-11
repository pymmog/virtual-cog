import CoreBluetooth
import Foundation

/// Zwift Click BLE client with ECDH/AES-CCM handshake and plain RideOn fallback.
@MainActor
final class ClickClient: NSObject, ObservableObject, ShifterControlling {
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var lastPlus = false
    @Published private(set) var lastMinus = false

    var onShift: ((ClickDebouncer.Event) -> Void)?

    private weak var manager: BleManager?
    private var peripheral: CBPeripheral?
    private var measurement: CBCharacteristic?
    private var controlPoint: CBCharacteristic?
    private var commandResponse: CBCharacteristic?
    private let crypto = ZwiftClickCrypto()
    private var debouncer = ClickDebouncer()
    private var mockTimer: Timer?

    func attach(manager: BleManager) {
        self.manager = manager
    }

    func willConnect(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        connectionState = .connecting
    }

    func didConnect(_ peripheral: CBPeripheral) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        connectionState = .connected
        peripheral.discoverServices([
            CBUUID(string: ZwiftBleIDs.service),
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, let manager = self.manager, let p = self.peripheral else { return }
            manager.centralManager?.connect(p, options: nil)
        }
    }

    func disconnect() {
        mockTimer?.invalidate()
        mockTimer = nil
        connectionState = .disconnected
    }

    func connectMock() {
        connectionState = .ready
        batteryPercent = 93
    }

    func simulateButton(plus: Bool = false, minus: Bool = false) {
        handleKeypad(plusDown: plus, minusDown: minus)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.handleKeypad(plusDown: false, minusDown: false)
        }
    }

    func sendHaptic(pattern: UInt32 = 2) {
        var nested = ProtobufWire.Writer()
        nested.writeUInt32(field: 3, value: pattern)
        var contents = ProtobufWire.Writer()
        contents.writeMessage(field: 1, nested.data)
        var cmd = ProtobufWire.Writer()
        cmd.writeMessage(field: 2, contents.data)
        writeControl(opcode: ZwiftOpcode.haptic, payload: cmd.data)
    }

    private func startHandshake() {
        do {
            if let commandResponse {
                peripheral?.readValue(for: commandResponse)
            }
            let payload = try crypto.buildAppPublicKeyPayload()
            writeRaw(payload)
        } catch {
            crypto.markPlainRideOn()
            writeRaw(Data(ZwiftClickCrypto.rideOnASCII))
        }
    }

    private func writeControl(opcode: UInt8, payload: Data) {
        let packet = ZwiftPacket.wrap(opcode: opcode, payload: payload)
        do {
            let wire = try crypto.encrypt(packet)
            writeRaw(wire)
        } catch {
            writeRaw(packet)
        }
    }

    private func writeRaw(_ data: Data) {
        guard let peripheral, let controlPoint else { return }
        peripheral.writeValue(data, for: controlPoint, type: .withResponse)
    }

    private func handleIncoming(_ data: Data) {
        if data.starts(with: ZwiftClickCrypto.rideOnASCII) {
            do {
                _ = try crypto.processDeviceHandshakeResponse(data)
                connectionState = .ready
            } catch {
                crypto.markPlainRideOn()
                connectionState = .ready
            }
            return
        }

        let plain: Data
        if crypto.encryptionEnabled && crypto.handshakeComplete {
            plain = (try? crypto.decrypt(data)) ?? data
        } else {
            plain = data
        }

        guard let packet = ZwiftPacket.unwrap(plain) else { return }
        switch packet.opcode {
        case ZwiftOpcode.clickKeyPad:
            if let status = try? ClickKeyPadStatus.decode(packet.payload) {
                handleKeypad(plusDown: status.buttonPlus == .on, minusDown: status.buttonMinus == .on)
            }
        case ZwiftOpcode.idleA, ZwiftOpcode.idleB:
            break
        default:
            break
        }
    }

    private func handleKeypad(plusDown: Bool, minusDown: Bool) {
        lastPlus = plusDown
        lastMinus = minusDown
        let events = debouncer.process(plusDown: plusDown, minusDown: minusDown)
        for event in events {
            onShift?(event)
            sendHaptic(pattern: 2)
        }
    }

    // MARK: - Router hooks

    func handleDiscoverServices(_ peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func handleDiscoverCharacteristics(_ peripheral: CBPeripheral, service: CBService, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        for char in service.characteristics ?? [] {
            if char.uuid == CBUUID(string: ZwiftBleIDs.measurement) {
                measurement = char
                peripheral.setNotifyValue(true, for: char)
            } else if char.uuid == CBUUID(string: ZwiftBleIDs.controlPoint) {
                controlPoint = char
            } else if char.uuid == CBUUID(string: ZwiftBleIDs.commandResponse) {
                commandResponse = char
                peripheral.setNotifyValue(true, for: char)
            } else if char.uuid.uuidString.uppercased().contains("2A19") {
                peripheral.setNotifyValue(true, for: char)
                peripheral.readValue(for: char)
            }
        }
        if service.uuid == CBUUID(string: ZwiftBleIDs.service) {
            startHandshake()
        }
    }

    func handleUpdateValue(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier, let data = characteristic.value else { return }
        if characteristic.uuid.uuidString.uppercased().contains("2A19"), let level = data.first {
            batteryPercent = Int(level)
            return
        }
        handleIncoming(data)
    }
}
