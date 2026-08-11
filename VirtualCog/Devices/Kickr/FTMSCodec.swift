import Foundation

/// Parsed FTMS Indoor Bike Data (0x2AD2).
struct IndoorBikeData: Equatable {
    var instantaneousSpeedKmh: Double?
    var averageSpeedKmh: Double?
    var instantaneousCadenceRpm: Double?
    var averageCadenceRpm: Double?
    var totalDistanceMeters: UInt32?
    var resistanceLevel: Int16?
    var instantaneousPowerWatts: Int16?
    var averagePowerWatts: Int16?
    var expendedEnergyKcal: UInt16?
    var heartRateBpm: UInt8?

    static func parse(_ data: Data) -> IndoorBikeData {
        let bytes = Array(data)
        guard bytes.count >= 2 else { return IndoorBikeData() }
        let flags = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        var offset = 2
        var out = IndoorBikeData()

        func takeUInt16() -> UInt16? {
            guard offset + 1 < bytes.count else { return nil }
            let v = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
            offset += 2
            return v
        }
        func takeInt16() -> Int16? {
            guard let u = takeUInt16() else { return nil }
            return Int16(bitPattern: u)
        }
        func takeUInt24() -> UInt32? {
            guard offset + 2 < bytes.count else { return nil }
            let v = UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16)
            offset += 3
            return v
        }
        func takeUInt8() -> UInt8? {
            guard offset < bytes.count else { return nil }
            defer { offset += 1 }
            return bytes[offset]
        }

        // Bit 0: more data / instantaneous speed present when 0 (FTMS weirdness).
        let speedPresent = (flags & 0x0001) == 0
        if speedPresent, let raw = takeUInt16() {
            out.instantaneousSpeedKmh = Double(raw) / 100.0
        }
        if flags & 0x0002 != 0, let raw = takeUInt16() {
            out.averageSpeedKmh = Double(raw) / 100.0
        }
        if flags & 0x0004 != 0, let raw = takeUInt16() {
            // Unit: 1/2 rpm
            out.instantaneousCadenceRpm = Double(raw) / 2.0
        }
        if flags & 0x0008 != 0, let raw = takeUInt16() {
            out.averageCadenceRpm = Double(raw) / 2.0
        }
        if flags & 0x0010 != 0, let raw = takeUInt24() {
            out.totalDistanceMeters = raw
        }
        if flags & 0x0020 != 0, let raw = takeInt16() {
            out.resistanceLevel = raw
        }
        if flags & 0x0040 != 0, let raw = takeInt16() {
            out.instantaneousPowerWatts = raw
        }
        if flags & 0x0080 != 0, let raw = takeInt16() {
            out.averagePowerWatts = raw
        }
        if flags & 0x0100 != 0 {
            _ = takeUInt16() // total energy
            out.expendedEnergyKcal = takeUInt16()
            _ = takeUInt8() // energy per hour/min leftover handling simplified
        }
        if flags & 0x0200 != 0, let hr = takeUInt8() {
            out.heartRateBpm = hr
        }
        return out
    }
}

enum FTMSControlBuilder {
    static func requestControl() -> Data { Data([FTMSOpcode.requestControl]) }
    static func startOrResume() -> Data { Data([FTMSOpcode.startOrResume]) }
    static func stop() -> Data { Data([FTMSOpcode.stopOrPause, 0x01]) }
    static func pause() -> Data { Data([FTMSOpcode.stopOrPause, 0x02]) }

    static func setTargetPower(watts: UInt16) -> Data {
        Data([FTMSOpcode.setTargetPower, UInt8(watts & 0xFF), UInt8(watts >> 8)])
    }

    /// Indoor Bike Simulation Parameters (FTMS).
    /// wind: m/s * 1000 as sint16, grade: % * 100 as sint16,
    /// crr: unitless * 10000 as uint8, cw: unitless * 100 as uint8 — per FTMS spec.
    static func setIndoorBikeSimulation(
        windMsX1000: Int16 = 0,
        gradePercentX100: Int16,
        crrX10000: UInt8 = 40,
        cwX100: UInt8 = 51
    ) -> Data {
        var data = Data([FTMSOpcode.setIndoorBikeSimulation])
        func appendInt16(_ v: Int16) {
            let u = UInt16(bitPattern: v)
            data.append(UInt8(u & 0xFF))
            data.append(UInt8(u >> 8))
        }
        appendInt16(windMsX1000)
        appendInt16(gradePercentX100)
        data.append(crrX10000)
        data.append(cwX100)
        return data
    }
}
