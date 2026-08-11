import Foundation

struct WorkoutSummary: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date
    var courseName: String
    var distanceMeters: Double
    var movingTimeSeconds: TimeInterval
    var averagePower: Double
    var maxPower: Int
    var elevationGainMeters: Double
    var fitFileName: String?
}

struct WorkoutSample: Equatable {
    var timestamp: Date
    var power: Int
    var cadence: Double
    var speedKmh: Double
    var heartRate: Int?
    var gradePercent: Double
    var distanceMeters: Double
    var gearIndex: Int
}

@MainActor
final class WorkoutRecorder {
    private(set) var samples: [WorkoutSample] = []
    private var startedAt: Date?
    private var courseName: String = "Ride"

    func begin(courseName: String) {
        self.courseName = courseName
        self.startedAt = Date()
        self.samples = []
    }

    func append(_ live: LiveTelemetry, at date: Date) {
        // ~1 Hz recording
        if let last = samples.last, date.timeIntervalSince(last.timestamp) < 0.95 {
            return
        }
        samples.append(
            WorkoutSample(
                timestamp: date,
                power: live.powerWatts,
                cadence: live.cadenceRpm,
                speedKmh: live.speedKmh,
                heartRate: live.heartRateBpm,
                gradePercent: live.gradePercent,
                distanceMeters: live.distanceMeters,
                gearIndex: live.gearIndex
            )
        )
    }

    func finish(telemetry: LiveTelemetry) -> WorkoutSummary? {
        guard let startedAt else { return nil }
        let ended = Date()
        let fitName = "ride-\(Int(ended.timeIntervalSince1970)).fit"
        let fitURL = WorkoutHistoryStore.directory.appendingPathComponent(fitName)
        try? FITEncoder.encode(samples: samples, start: startedAt, to: fitURL)
        let summary = WorkoutSummary(
            startedAt: startedAt,
            endedAt: ended,
            courseName: courseName,
            distanceMeters: telemetry.distanceMeters,
            movingTimeSeconds: telemetry.movingTimeSeconds,
            averagePower: telemetry.averagePower,
            maxPower: telemetry.maxPower,
            elevationGainMeters: telemetry.elevationGainMeters,
            fitFileName: fitName
        )
        self.startedAt = nil
        return summary
    }
}

@MainActor
final class WorkoutHistoryStore: ObservableObject {
    @Published private(set) var items: [WorkoutSummary] = []

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("VirtualCog/Workouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var indexURL: URL { Self.directory.appendingPathComponent("history.json") }

    init() {
        load()
    }

    func add(_ summary: WorkoutSummary) {
        items.insert(summary, at: 0)
        save()
    }

    func fitURL(for summary: WorkoutSummary) -> URL? {
        guard let name = summary.fitFileName else { return nil }
        return Self.directory.appendingPathComponent(name)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([WorkoutSummary].self, from: data)
        else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

/// Minimal FIT file encoder covering record messages needed for training platforms.
enum FITEncoder {
    static func encode(samples: [WorkoutSample], start: Date, to url: URL) throws {
        var records = Data()
        // File header placeholder
        var file = Data()
        // Header: size 14, protocol 2.0, profile 2.0, data size later, ".FIT", CRC
        file.append(contentsOf: [14, 0x10, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00]) // size/protocol/profile + data size placeholder
        file.append(contentsOf: Array(".FIT".utf8))
        file.append(contentsOf: [0x00, 0x00]) // header CRC placeholder

        // Definition + data for file_id (mesg 0)
        records.append(definitionMessage(
            local: 0,
            global: 0,
            fields: [
                (0, 1, 0),  // type enum
                (1, 2, 132), // manufacturer uint16
                (4, 4, 134), // time_created uint32
            ]
        ))
        var fileID = Data([0x00]) // data message local 0
        fileID.append(4) // activity
        appendUInt16(&fileID, 255) // development manufacturer
        appendUInt32(&fileID, UInt32(start.timeIntervalSince1970) - 631_065_600) // FIT epoch
        records.append(fileID)

        // record definition mesg 20
        records.append(definitionMessage(
            local: 1,
            global: 20,
            fields: [
                (253, 4, 134), // timestamp
                (3, 1, 2),     // heart_rate
                (4, 1, 2),     // cadence
                (5, 4, 134),   // distance (cm)
                (6, 2, 132),   // speed (mm/s)
                (7, 2, 132),   // power
                (9, 1, 1),     // grade (signed percent * 100 scaled via sint8 approx — use field 9 as sint8 percent)
            ]
        ))

        for sample in samples {
            var msg = Data([0x01])
            let ts = UInt32(sample.timestamp.timeIntervalSince1970) - 631_065_600
            appendUInt32(&msg, ts)
            msg.append(UInt8(min(255, sample.heartRate ?? 0)))
            msg.append(UInt8(min(255, Int(sample.cadence.rounded()))))
            appendUInt32(&msg, UInt32(min(UInt32.max, sample.distanceMeters * 100)))
            appendUInt16(&msg, UInt16(min(65535, sample.speedKmh / 3.6 * 1000)))
            appendUInt16(&msg, UInt16(min(65535, sample.power)))
            let grade = Int(max(-128, min(127, sample.gradePercent.rounded())))
            msg.append(UInt8(bitPattern: Int8(grade)))
            records.append(msg)
        }

        // Patch data size at bytes 4..7 little-endian
        let dataSize = UInt32(records.count)
        file.replaceSubrange(4..<8, with: withUnsafeBytes(of: dataSize.littleEndian, Array.init))

        // Header CRC (bytes 0..11)
        let headerCRC = crc16(Data(file.prefix(12)))
        file[12] = UInt8(headerCRC & 0xFF)
        file[13] = UInt8(headerCRC >> 8)

        file.append(records)
        let fileCRC = crc16(file)
        file.append(UInt8(fileCRC & 0xFF))
        file.append(UInt8(fileCRC >> 8))
        try file.write(to: url, options: .atomic)
    }

    private static func definitionMessage(local: UInt8, global: UInt16, fields: [(UInt8, UInt8, UInt8)]) -> Data {
        var data = Data([0x40 | local, 0x00, 0x00]) // defn, reserved, architecture LE
        appendUInt16(&data, global)
        data.append(UInt8(fields.count))
        for field in fields {
            data.append(field.0)
            data.append(field.1)
            data.append(field.2)
        }
        return data
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8(value >> 8))
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    /// FIT CRC-16
    static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0
        let table: [UInt16] = [
            0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
            0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400
        ]
        for byte in data {
            var tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int(byte & 0xF)]
            tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int((byte >> 4) & 0xF)]
        }
        return crc
    }
}
