import CoreBluetooth
import Foundation

/// FTMS Indoor Bike client — Phase 1/2 telemetry + control fallback.
@MainActor
final class KickrFtmsClient: NSObject, ObservableObject, TrainerControlling {
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var lastTelemetry = LiveTelemetry(source: .ftms)
    @Published private(set) var controlGranted = false

    private weak var manager: BleManager?
    private var peripheral: CBPeripheral?
    private var controlPoint: CBCharacteristic?
    private var indoorBikeData: CBCharacteristic?
    private var statusChar: CBCharacteristic?
    private var mockTimer: Timer?
    private var pendingGradeX100: Int16 = 0
    private var pendingPower: UInt16?

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
            CBUUID(string: String(format: "%04X", FTMSUUID.fitnessMachine)),
            CBUUID(string: String(format: "%04X", FTMSUUID.deviceInformation)),
            CBUUID(string: ZwiftBleIDs.service)
        ])
    }

    func didFail(_ peripheral: CBPeripheral, message: String) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        connectionState = .failed(message)
    }

    func didDisconnect(_ peripheral: CBPeripheral) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        connectionState = .reconnecting
        controlGranted = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, let manager = self.manager, let p = self.peripheral else { return }
            manager.centralManager?.connect(p, options: nil)
        }
    }

    func disconnect() {
        mockTimer?.invalidate()
        mockTimer = nil
        connectionState = .disconnected
        controlGranted = false
    }

    func connectMock() {
        connectionState = .ready
        controlGranted = true
        lastTelemetry.source = .mock
        mockTimer?.invalidate()
        mockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                var t = self.lastTelemetry
                t.powerWatts = 180 + Int.random(in: -15...15)
                t.cadenceRpm = 85 + Double.random(in: -3...3)
                t.speedKmh = 32 + Double.random(in: -1...1)
                t.ftmsWheelSpeedKmh = t.speedKmh
                t.heartRateBpm = 140 + Int.random(in: -2...2)
                t.source = .mock
                self.lastTelemetry = t
            }
        }
    }

    func requestControl() {
        writeControl(FTMSControlBuilder.requestControl())
        writeControl(FTMSControlBuilder.startOrResume())
    }

    func setSimulation(gradePercent: Double, wind: Int32, cwa: UInt32, crr: UInt32) {
        pendingGradeX100 = Int16((gradePercent * 100).rounded())
        let crrByte = UInt8(min(255, crr / 10))
        let cwByte = UInt8(min(255, cwa / 100))
        writeControl(
            FTMSControlBuilder.setIndoorBikeSimulation(
                windMsX1000: Int16(clamping: wind * 10),
                gradePercentX100: pendingGradeX100,
                crrX10000: crrByte,
                cwX100: cwByte
            )
        )
        lastTelemetry.gradePercent = gradePercent
        lastTelemetry.mode = .sim
    }

    func setGearRatioX10000(_ ratio: UInt32) {
        _ = ratio
    }

    func setWeights(riderKg: Double, bikeKg: Double) {
        _ = (riderKg, bikeKg)
    }

    func setTargetPower(_ watts: UInt16) {
        pendingPower = watts
        writeControl(FTMSControlBuilder.setTargetPower(watts: watts))
        lastTelemetry.mode = .erg
    }

    private func writeControl(_ data: Data) {
        guard let peripheral, let controlPoint else { return }
        peripheral.writeValue(data, for: controlPoint, type: .withResponse)
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
        guard service.uuid == CBUUID(string: String(format: "%04X", FTMSUUID.fitnessMachine)) else { return }
        for char in service.characteristics ?? [] {
            let uuid = char.uuid.uuidString.uppercased()
            if uuid.contains(String(format: "%04X", FTMSUUID.indoorBikeData)) {
                indoorBikeData = char
                peripheral.setNotifyValue(true, for: char)
            } else if uuid.contains(String(format: "%04X", FTMSUUID.fitnessMachineControlPoint)) {
                controlPoint = char
                peripheral.setNotifyValue(true, for: char)
                requestControl()
            } else if uuid.contains(String(format: "%04X", FTMSUUID.fitnessMachineStatus)) {
                statusChar = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
        connectionState = .ready
    }

    func handleUpdateValue(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier, let data = characteristic.value else { return }
        let uuid = characteristic.uuid.uuidString.uppercased()
        if uuid.contains(String(format: "%04X", FTMSUUID.indoorBikeData)) {
            let parsed = IndoorBikeData.parse(data)
            var t = lastTelemetry
            if let p = parsed.instantaneousPowerWatts { t.powerWatts = Int(p) }
            if let c = parsed.instantaneousCadenceRpm { t.cadenceRpm = c }
            if let s = parsed.instantaneousSpeedKmh {
                t.speedKmh = s
                t.ftmsWheelSpeedKmh = s
            }
            if let hr = parsed.heartRateBpm { t.heartRateBpm = Int(hr) }
            t.source = .ftms
            t.maxPower = max(t.maxPower, t.powerWatts)
            lastTelemetry = t
        } else if uuid.contains(String(format: "%04X", FTMSUUID.fitnessMachineControlPoint)) {
            if data.first == FTMSOpcode.responseCode, data.count >= 3, data[2] == 0x01 {
                controlGranted = true
            }
        }
    }
}
