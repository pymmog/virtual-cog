import Foundation

/// Bluetooth SIG Heart Rate Measurement (0x2A37).
struct HeartRateMeasurement: Equatable {
    var bpm: Int
    var sensorContactSupported: Bool
    var sensorContactDetected: Bool
    var energyExpendedKj: UInt16?
    var rrIntervalsSeconds: [Double]

    /// Body Sensor Location (0x2A38) — wrist.
    static let wristLocation: UInt8 = 2

    static func parse(_ data: Data) -> HeartRateMeasurement? {
        let bytes = Array(data)
        guard bytes.count >= 2 else { return nil }
        let flags = bytes[0]
        let uint16HR = (flags & 0x01) != 0
        var offset = 1
        let bpm: Int
        if uint16HR {
            guard bytes.count >= 3 else { return nil }
            bpm = Int(UInt16(bytes[1]) | (UInt16(bytes[2]) << 8))
            offset = 3
        } else {
            bpm = Int(bytes[1])
            offset = 2
        }

        let contactSupported = (flags & 0x04) != 0
        let contactDetected = (flags & 0x06) == 0x06

        var energy: UInt16?
        if (flags & 0x08) != 0 {
            guard bytes.count >= offset + 2 else { return nil }
            energy = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
            offset += 2
        }

        var rrs: [Double] = []
        if (flags & 0x10) != 0 {
            while offset + 1 < bytes.count {
                let raw = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
                rrs.append(Double(raw) / 1024.0)
                offset += 2
            }
        }

        return HeartRateMeasurement(
            bpm: bpm,
            sensorContactSupported: contactSupported,
            sensorContactDetected: contactDetected,
            energyExpendedKj: energy,
            rrIntervalsSeconds: rrs
        )
    }

    func encode() -> Data {
        var flags: UInt8 = 0
        var payload = Data()
        if bpm > 255 {
            flags |= 0x01
            let value = UInt16(clamping: bpm)
            payload.append(UInt8(truncatingIfNeeded: value))
            payload.append(UInt8(truncatingIfNeeded: value >> 8))
        } else {
            payload.append(UInt8(clamping: bpm))
        }
        if sensorContactSupported {
            flags |= 0x04
            if sensorContactDetected {
                flags |= 0x02
            }
        }
        if let energy = energyExpendedKj {
            flags |= 0x08
            payload.append(UInt8(truncatingIfNeeded: energy))
            payload.append(UInt8(truncatingIfNeeded: energy >> 8))
        }
        if !rrIntervalsSeconds.isEmpty {
            flags |= 0x10
            for seconds in rrIntervalsSeconds {
                let raw = UInt16(clamping: Int((seconds * 1024.0).rounded()))
                payload.append(UInt8(truncatingIfNeeded: raw))
                payload.append(UInt8(truncatingIfNeeded: raw >> 8))
            }
        }
        var data = Data([flags])
        data.append(payload)
        return data
    }

    static func notifyPacket(bpm: Int, contactDetected: Bool = true) -> Data {
        HeartRateMeasurement(
            bpm: bpm,
            sensorContactSupported: true,
            sensorContactDetected: contactDetected,
            energyExpendedKj: nil,
            rrIntervalsSeconds: []
        ).encode()
    }
}
