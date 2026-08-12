import Foundation

/// Deterministic BLE fixtures for CI / `--mock-ble` without hardware.
enum BleMockFixtures {
    /// Example HubRidingData opcode 0x03 from Makinolo:
    /// Power 190, Cadence 80, SpeedX100 829, HR 0, …
    static let hubRidingDataHex = "0308be01105018bd06200028e2ba01308beb01"

    /// Physical weights command: bike 6.41 kg, rider 76.2 kg
    static let hubWeightsHex = "042a08100020810528c43b"

    /// Click keypad plus pressed (Button_Plus=ON=0, Button_Minus=OFF=1) — illustrative.
    static let clickPlusPressedPayload = Data([0x08, 0x00, 0x10, 0x01])

    /// Heart Rate Measurement: flags contact supported+detected (0x06), 142 bpm.
    static let heartRateMeasurementHex = "068e"

    static func data(fromHex hex: String) -> Data {
        var result = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            let byteStr = hex[index..<next]
            result.append(UInt8(byteStr, radix: 16)!)
            index = next
        }
        return result
    }
}
