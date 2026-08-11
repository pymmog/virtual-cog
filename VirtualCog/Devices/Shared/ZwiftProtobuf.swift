import Foundation

/// Minimal protobuf2 wire helper for Zwift BLE payloads (opcode is outside PB).
enum ProtobufWire {
    enum WireType: UInt8 {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case fixed32 = 5
    }

    struct Reader {
        private let data: [UInt8]
        private(set) var index: Int = 0

        init(_ data: Data) { self.data = Array(data) }
        init(_ bytes: [UInt8]) { self.data = bytes }

        var isEOF: Bool { index >= data.count }

        mutating func readVarint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard index < data.count else { throw ProtoError.truncated }
                let byte = data[index]
                index += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
                if shift > 63 { throw ProtoError.overflow }
            }
        }

        mutating func readKey() throws -> (field: UInt32, wire: WireType)? {
            if isEOF { return nil }
            let key = try readVarint()
            let field = UInt32(key >> 3)
            guard let wire = WireType(rawValue: UInt8(key & 0x7)) else {
                throw ProtoError.invalidWireType
            }
            return (field, wire)
        }

        mutating func skip(wire: WireType) throws {
            switch wire {
            case .varint:
                _ = try readVarint()
            case .fixed64:
                try skipBytes(8)
            case .fixed32:
                try skipBytes(4)
            case .lengthDelimited:
                let len = Int(try readVarint())
                try skipBytes(len)
            }
        }

        mutating func readLengthDelimited() throws -> Data {
            let len = Int(try readVarint())
            guard index + len <= data.count else { throw ProtoError.truncated }
            let slice = Array(data[index..<(index + len)])
            index += len
            return Data(slice)
        }

        mutating func readSInt32() throws -> Int32 {
            let n = try readVarint()
            return Int32(bitPattern: UInt32(zigZagDecode(n)))
        }

        private mutating func skipBytes(_ count: Int) throws {
            guard index + count <= data.count else { throw ProtoError.truncated }
            index += count
        }
    }

    struct Writer {
        private(set) var bytes: [UInt8] = []

        mutating func writeVarint(_ value: UInt64) {
            var v = value
            while v > 0x7F {
                bytes.append(UInt8(v & 0x7F) | 0x80)
                v >>= 7
            }
            bytes.append(UInt8(v & 0x7F))
        }

        mutating func writeKey(field: UInt32, wire: WireType) {
            writeVarint(UInt64(field << 3 | UInt32(wire.rawValue)))
        }

        mutating func writeUInt32(field: UInt32, value: UInt32) {
            writeKey(field: field, wire: .varint)
            writeVarint(UInt64(value))
        }

        mutating func writeSInt32(field: UInt32, value: Int32) {
            writeKey(field: field, wire: .varint)
            writeVarint(zigZagEncode(UInt32(bitPattern: value)))
        }

        mutating func writeMessage(field: UInt32, _ nested: Data) {
            writeKey(field: field, wire: .lengthDelimited)
            writeVarint(UInt64(nested.count))
            bytes.append(contentsOf: nested)
        }

        var data: Data { Data(bytes) }
    }

    static func zigZagEncode(_ n: UInt32) -> UInt64 {
        UInt64((n << 1) ^ UInt32(bitPattern: Int32(bitPattern: n) >> 31))
    }

    static func zigZagDecode(_ n: UInt64) -> UInt32 {
        UInt32((n >> 1) ^ (~(n & 1) + 1))
    }

    enum ProtoError: Error {
        case truncated
        case overflow
        case invalidWireType
    }
}

// MARK: - Hub messages

struct HubRidingData: Equatable {
    var power: UInt32?
    var cadence: UInt32?
    var speedX100: UInt32?
    var hr: UInt32?
    var unknown1: UInt32?
    var unknown2: UInt32?

    static func decode(_ payload: Data) throws -> HubRidingData {
        var reader = ProtobufWire.Reader(payload)
        var msg = HubRidingData()
        while let key = try reader.readKey() {
            switch (key.field, key.wire) {
            case (1, .varint): msg.power = UInt32(try reader.readVarint())
            case (2, .varint): msg.cadence = UInt32(try reader.readVarint())
            case (3, .varint): msg.speedX100 = UInt32(try reader.readVarint())
            case (4, .varint): msg.hr = UInt32(try reader.readVarint())
            case (5, .varint): msg.unknown1 = UInt32(try reader.readVarint())
            case (6, .varint): msg.unknown2 = UInt32(try reader.readVarint())
            default: try reader.skip(wire: key.wire)
            }
        }
        return msg
    }
}

struct SimulationParam: Equatable {
    var wind: Int32?
    var inclineX100: Int32?
    var cwa: UInt32?
    var crr: UInt32?

    func encode() -> Data {
        var w = ProtobufWire.Writer()
        if let wind { w.writeSInt32(field: 1, value: wind) }
        if let inclineX100 { w.writeSInt32(field: 2, value: inclineX100) }
        if let cwa { w.writeUInt32(field: 3, value: cwa) }
        if let crr { w.writeUInt32(field: 4, value: crr) }
        return w.data
    }

    static func decode(_ data: Data) throws -> SimulationParam {
        var reader = ProtobufWire.Reader(data)
        var msg = SimulationParam()
        while let key = try reader.readKey() {
            switch (key.field, key.wire) {
            case (1, .varint): msg.wind = try reader.readSInt32()
            case (2, .varint): msg.inclineX100 = try reader.readSInt32()
            case (3, .varint): msg.cwa = UInt32(try reader.readVarint())
            case (4, .varint): msg.crr = UInt32(try reader.readVarint())
            default: try reader.skip(wire: key.wire)
            }
        }
        return msg
    }
}

struct PhysicalParam: Equatable {
    var gearRatioX10000: UInt32?
    var bikeWeightX100: UInt32?
    var riderWeightX100: UInt32?

    func encode() -> Data {
        var w = ProtobufWire.Writer()
        if let gearRatioX10000 { w.writeUInt32(field: 2, value: gearRatioX10000) }
        if let bikeWeightX100 { w.writeUInt32(field: 4, value: bikeWeightX100) }
        if let riderWeightX100 { w.writeUInt32(field: 5, value: riderWeightX100) }
        return w.data
    }
}

struct HubCommand: Equatable {
    var powerTarget: UInt32?
    var simulation: SimulationParam?
    var physical: PhysicalParam?

    func encode() -> Data {
        var w = ProtobufWire.Writer()
        if let powerTarget { w.writeUInt32(field: 3, value: powerTarget) }
        if let simulation { w.writeMessage(field: 4, simulation.encode()) }
        if let physical { w.writeMessage(field: 5, physical.encode()) }
        return w.data
    }
}

enum PlayButtonStatus: Int {
    case on = 0
    case off = 1
}

struct ClickKeyPadStatus: Equatable {
    var buttonPlus: PlayButtonStatus?
    var buttonMinus: PlayButtonStatus?

    static func decode(_ payload: Data) throws -> ClickKeyPadStatus {
        var reader = ProtobufWire.Reader(payload)
        var msg = ClickKeyPadStatus()
        while let key = try reader.readKey() {
            switch (key.field, key.wire) {
            case (1, .varint):
                msg.buttonPlus = PlayButtonStatus(rawValue: Int(try reader.readVarint()))
            case (2, .varint):
                msg.buttonMinus = PlayButtonStatus(rawValue: Int(try reader.readVarint()))
            default:
                try reader.skip(wire: key.wire)
            }
        }
        return msg
    }
}

enum ZwiftOpcode {
    static let hubInfo: UInt8 = 0x00
    static let hubRidingData: UInt8 = 0x03
    static let hubCommand: UInt8 = 0x04
    static let playKeyPad: UInt8 = 0x07
    static let haptic: UInt8 = 0x12
    static let idleA: UInt8 = 0x15
    static let idleB: UInt8 = 0x19
    static let clickKeyPad: UInt8 = 0x37
}

enum ZwiftPacket {
    static func wrap(opcode: UInt8, payload: Data) -> Data {
        var out = Data([opcode])
        out.append(payload)
        return out
    }

    static func unwrap(_ data: Data) -> (opcode: UInt8, payload: Data)? {
        guard let first = data.first else { return nil }
        return (first, data.dropFirst())
    }
}
