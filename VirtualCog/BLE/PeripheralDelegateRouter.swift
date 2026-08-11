import CoreBluetooth
import Foundation

/// Fans out CBPeripheralDelegate callbacks to Hub + FTMS clients sharing one connection.
final class PeripheralDelegateRouter: NSObject, CBPeripheralDelegate {
    weak var ftms: KickrFtmsClient?
    weak var hub: KickrZwiftClient?
    weak var click: ClickClient?

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            self.ftms?.handleDiscoverServices(peripheral, error: error)
            self.hub?.handleDiscoverServices(peripheral, error: error)
            self.click?.handleDiscoverServices(peripheral, error: error)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            self.ftms?.handleDiscoverCharacteristics(peripheral, service: service, error: error)
            self.hub?.handleDiscoverCharacteristics(peripheral, service: service, error: error)
            self.click?.handleDiscoverCharacteristics(peripheral, service: service, error: error)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            self.ftms?.handleUpdateValue(peripheral, characteristic: characteristic, error: error)
            self.hub?.handleUpdateValue(peripheral, characteristic: characteristic, error: error)
            self.click?.handleUpdateValue(peripheral, characteristic: characteristic, error: error)
        }
    }
}
