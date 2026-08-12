import Combine
import CoreBluetooth
import Foundation

/// Single CBCentralManager owner for the process (macOS BLE stability).
@MainActor
final class BleManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var discoveredTrainers: [BlePeripheralSummary] = []
    @Published private(set) var discoveredClicks: [BlePeripheralSummary] = []
    @Published private(set) var discoveredHeartRateMonitors: [BlePeripheralSummary] = []

    let kickrHub: KickrZwiftClient
    let kickrFtms: KickrFtmsClient
    let click: ClickClient
    let heartRate: HeartRateClient
    let useMocks: Bool

    private var central: CBCentralManager?
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var scanTimer: Timer?
    private let trainerRouter = PeripheralDelegateRouter()
    private let clickRouter = PeripheralDelegateRouter()
    private let heartRateRouter = PeripheralDelegateRouter()
    private var cancellables = Set<AnyCancellable>()

    init(useMocks: Bool = false) {
        self.useMocks = useMocks
        self.kickrHub = KickrZwiftClient()
        self.kickrFtms = KickrFtmsClient()
        self.click = ClickClient()
        self.heartRate = HeartRateClient()
        super.init()
        trainerRouter.ftms = kickrFtms
        trainerRouter.hub = kickrHub
        clickRouter.click = click
        heartRateRouter.heartRate = heartRate
        kickrHub.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        kickrFtms.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        click.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        heartRate.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        if useMocks {
            bluetoothState = .poweredOn
        } else {
            central = CBCentralManager(delegate: self, queue: .main)
            kickrHub.attach(manager: self)
            kickrFtms.attach(manager: self)
            click.attach(manager: self)
            heartRate.attach(manager: self)
        }
    }

    /// Populate mock peripherals so Setup is ready without tapping Scan.
    func bootstrapMocks() {
        guard useMocks else { return }
        startScan()
    }

    /// Connect mock trainer, Click, and heart-rate monitor for demo rides.
    func connectAllMocks() {
        guard useMocks else { return }
        if discoveredTrainers.isEmpty || discoveredClicks.isEmpty || discoveredHeartRateMonitors.isEmpty {
            startScan()
        }
        if let trainer = discoveredTrainers.first {
            connectTrainer(id: trainer.id)
        }
        if let clickDevice = discoveredClicks.first {
            connectClick(id: clickDevice.id)
        }
        if let hrm = discoveredHeartRateMonitors.first {
            connectHeartRate(id: hrm.id)
        }
    }

    func startScan() {
        discoveredTrainers = []
        discoveredClicks = []
        discoveredHeartRateMonitors = []
        if useMocks {
            discoveredTrainers = [
                BlePeripheralSummary(id: UUID(), name: "KICKR CORE 2 (Mock)", rssi: -55, kind: .trainer)
            ]
            discoveredClicks = [
                BlePeripheralSummary(id: UUID(), name: "Zwift Click (Mock)", rssi: -60, kind: .click)
            ]
            discoveredHeartRateMonitors = [
                BlePeripheralSummary(id: UUID(), name: "VirtualCog HR (Mock)", rssi: -52, kind: .heartRate)
            ]
            return
        }
        guard bluetoothState == .poweredOn, let central else { return }
        let services = [
            CBUUID(string: String(format: "%04X", FTMSUUID.fitnessMachine)),
            CBUUID(string: ZwiftBleIDs.service),
            CBUUID(string: HeartRateUUID.serviceCBUUIDString)
        ]
        central.scanForPeripherals(withServices: services, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stopScan() }
        }
    }

    func stopScan() {
        scanTimer?.invalidate()
        central?.stopScan()
    }

    func connectTrainer(id: UUID) {
        if useMocks {
            kickrFtms.connectMock()
            kickrHub.connectMock()
            return
        }
        guard let peripheral = peripheralsByID[id], let central else { return }
        stopScan()
        peripheral.delegate = trainerRouter
        kickrFtms.willConnect(peripheral)
        kickrHub.willConnect(peripheral)
        central.connect(peripheral, options: nil)
    }

    func connectClick(id: UUID) {
        if useMocks {
            click.connectMock()
            return
        }
        guard let peripheral = peripheralsByID[id], let central else { return }
        peripheral.delegate = clickRouter
        click.willConnect(peripheral)
        central.connect(peripheral, options: nil)
    }

    func connectHeartRate(id: UUID) {
        if useMocks {
            heartRate.connectMock()
            return
        }
        guard let peripheral = peripheralsByID[id], let central else { return }
        stopScan()
        peripheral.delegate = heartRateRouter
        heartRate.willConnect(peripheral)
        central.connect(peripheral, options: nil)
    }

    func disconnectAll() {
        if useMocks {
            kickrFtms.disconnect()
            kickrHub.disconnect()
            click.disconnect()
            heartRate.disconnect()
            return
        }
        for peripheral in peripheralsByID.values {
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    func peripheral(for id: UUID) -> CBPeripheral? {
        peripheralsByID[id]
    }

    var centralManager: CBCentralManager? { central }
}

struct BlePeripheralSummary: Identifiable, Equatable {
    enum Kind { case trainer, click, heartRate, unknown }
    let id: UUID
    var name: String
    var rssi: Int
    var kind: Kind
}

extension BleManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.bluetoothState = central.state
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            self.peripheralsByID[peripheral.identifier] = peripheral
            let name = peripheral.name
                ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
                ?? "Unknown"
            var kind: BlePeripheralSummary.Kind = .unknown
            let upper = name.uppercased()
            let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
                + (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
            let hrUUID = CBUUID(string: HeartRateUUID.serviceCBUUIDString)
            if advertised.contains(hrUUID)
                || upper.contains("VIRTUALCOG HR")
                || upper.contains("TICKR")
                || upper.contains("HRM")
                || upper.contains("HEART RATE")
                || upper.contains("POLAR") {
                kind = .heartRate
            }
            if upper.contains("KICKR") || upper.contains("HUB") {
                kind = .trainer
            }
            if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
               ZwiftBleIDs.parseControllerType(manufacturerData: mfg) == .click
                || upper.contains("CLICK") {
                kind = .click
            }
            if upper.contains("CLICK") { kind = .click }

            let summary = BlePeripheralSummary(
                id: peripheral.identifier,
                name: name,
                rssi: RSSI.intValue,
                kind: kind
            )
            switch kind {
            case .trainer:
                upsert(&self.discoveredTrainers, summary)
            case .click:
                upsert(&self.discoveredClicks, summary)
            case .heartRate:
                upsert(&self.discoveredHeartRateMonitors, summary)
            case .unknown:
                if upper.contains("KICKR") {
                    upsert(&self.discoveredTrainers, summary)
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.kickrFtms.didConnect(peripheral)
            self.kickrHub.didConnect(peripheral)
            self.click.didConnect(peripheral)
            self.heartRate.didConnect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            let message = error?.localizedDescription ?? "connection failed"
            self.kickrFtms.didFail(peripheral, message: message)
            self.kickrHub.didFail(peripheral, message: message)
            self.click.didFail(peripheral, message: message)
            self.heartRate.didFail(peripheral, message: message)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.kickrFtms.didDisconnect(peripheral)
            self.kickrHub.didDisconnect(peripheral)
            self.click.didDisconnect(peripheral)
            self.heartRate.didDisconnect(peripheral)
        }
    }
}

@MainActor
private func upsert(_ list: inout [BlePeripheralSummary], _ item: BlePeripheralSummary) {
    if let idx = list.firstIndex(where: { $0.id == item.id }) {
        list[idx] = item
    } else {
        list.append(item)
    }
}
