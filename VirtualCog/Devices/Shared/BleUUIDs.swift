import Foundation

/// Zwift proprietary Race Controller / Hub BLE UUIDs and discovery helpers.
enum ZwiftBleIDs {
    static let service = "00000001-19CA-4651-86E5-FA29DCDD09D1"
    static let measurement = "00000002-19CA-4651-86E5-FA29DCDD09D1"
    static let controlPoint = "00000003-19CA-4651-86E5-FA29DCDD09D1"
    static let commandResponse = "00000004-19CA-4651-86E5-FA29DCDD09D1"

    /// Bluetooth SIG company / manufacturer ID used in Click/Play ads.
    static let manufacturerID: UInt16 = 0x094A

    enum ControllerType: UInt8 {
        case playRight = 2
        case playLeft = 3
        case click = 9
    }

    static func parseControllerType(manufacturerData: Data) -> ControllerType? {
        // Format: company ID (2 LE) already stripped by CoreBluetooth on some paths,
        // or included depending on platform. Accept both.
        let bytes = Array(manufacturerData)
        if bytes.count >= 3, bytes[0] == 0x4A, bytes[1] == 0x09 {
            return ControllerType(rawValue: bytes[2])
        }
        if bytes.count >= 1 {
            return ControllerType(rawValue: bytes[0])
        }
        return nil
    }
}

enum FTMSUUID {
    static let fitnessMachine: UInt16 = 0x1826
    static let indoorBikeData: UInt16 = 0x2AD2
    static let fitnessMachineControlPoint: UInt16 = 0x2AD9
    static let fitnessMachineFeature: UInt16 = 0x2ACC
    static let fitnessMachineStatus: UInt16 = 0x2ADA
    static let supportedResistanceRange: UInt16 = 0x2AD6
    static let cyclingPower: UInt16 = 0x1818
    static let deviceInformation: UInt16 = 0x180A
    static let battery: UInt16 = 0x180F
    static let heartRate: UInt16 = 0x180D
    static let userData: UInt16 = 0x181C
}

enum FTMSOpcode {
    static let requestControl: UInt8 = 0x00
    static let reset: UInt8 = 0x01
    static let setTargetPower: UInt8 = 0x05
    static let startOrResume: UInt8 = 0x07
    static let stopOrPause: UInt8 = 0x08
    static let setIndoorBikeSimulation: UInt8 = 0x11
    static let responseCode: UInt8 = 0x80
}
