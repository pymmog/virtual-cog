import AppKit
import Foundation
import UniformTypeIdentifiers

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
    var averageHeartRate: Int?
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
        try? FITEncoder.encode(samples: samples, start: startedAt, end: ended, to: fitURL)
        let hrs = samples.compactMap(\.heartRate)
        let summary = WorkoutSummary(
            startedAt: startedAt,
            endedAt: ended,
            courseName: courseName,
            distanceMeters: telemetry.distanceMeters,
            movingTimeSeconds: telemetry.movingTimeSeconds,
            averagePower: telemetry.averagePower,
            maxPower: telemetry.maxPower,
            elevationGainMeters: telemetry.elevationGainMeters,
            averageHeartRate: hrs.isEmpty ? nil : hrs.reduce(0, +) / hrs.count,
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
        let url = Self.directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Copy a stored FIT to a user-chosen destination (Save panel).
    func exportFit(for summary: WorkoutSummary, to destination: URL) throws {
        guard let source = fitURL(for: summary) else {
            throw FitExportError.missingFile
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
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

enum FitExportError: LocalizedError {
    case missingFile

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "The FIT file for this ride is missing."
        }
    }
}

/// Minimal FIT file encoder covering record + session + activity for importers.
enum FITEncoder {
    /// FIT sport: cycling
    private static let sportCycling: UInt8 = 2
    /// FIT sub_sport: indoor cycling
    private static let subSportIndoorCycling: UInt8 = 6

    static func encode(samples: [WorkoutSample], start: Date, end: Date = Date(), to url: URL) throws {
        var records = Data()
        var file = Data()
        // Header: size 14, protocol 2.0, profile 2.0, data size later, ".FIT", CRC
        file.append(contentsOf: [14, 0x10, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00])
        file.append(contentsOf: Array(".FIT".utf8))
        file.append(contentsOf: [0x00, 0x00]) // header CRC placeholder

        let startFit = fitEpoch(start)
        let endFit = fitEpoch(end)
        let elapsedSeconds = max(0, end.timeIntervalSince(start))
        let elapsedMs = UInt32(min(Double(UInt32.max), elapsedSeconds * 1000).rounded())

        let distanceCm: UInt32 = {
            if let last = samples.last {
                return UInt32(clamping: Int(last.distanceMeters * 100))
            }
            return 0
        }()

        let powers = samples.map(\.power)
        let avgPower = powers.isEmpty ? 0 : powers.reduce(0, +) / powers.count
        let maxPower = powers.max() ?? 0
        let avgCadence = samples.isEmpty ? 0 : Int(samples.map(\.cadence).reduce(0, +) / Double(samples.count))
        let hrs = samples.compactMap(\.heartRate)
        let avgHR = hrs.isEmpty ? 0 : hrs.reduce(0, +) / hrs.count

        // file_id (mesg 0)
        records.append(definitionMessage(
            local: 0,
            global: 0,
            fields: [
                (0, 1, 0),   // type enum
                (1, 2, 132), // manufacturer uint16
                (4, 4, 134), // time_created uint32
            ]
        ))
        var fileID = Data([0x00])
        fileID.append(4) // activity
        appendUInt16(&fileID, 255) // development manufacturer
        appendUInt32(&fileID, startFit)
        records.append(fileID)

        // record (mesg 20)
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
                (9, 1, 1),     // grade (sint8 percent)
            ]
        ))

        for sample in samples {
            var msg = Data([0x01])
            appendUInt32(&msg, fitEpoch(sample.timestamp))
            msg.append(UInt8(min(255, sample.heartRate ?? 0)))
            msg.append(UInt8(min(255, Int(sample.cadence.rounded()))))
            appendUInt32(&msg, UInt32(clamping: Int(sample.distanceMeters * 100)))
            appendUInt16(&msg, UInt16(clamping: Int((sample.speedKmh / 3.6 * 1000).rounded())))
            appendUInt16(&msg, UInt16(clamping: sample.power))
            let grade = Int(max(-128, min(127, sample.gradePercent.rounded())))
            msg.append(UInt8(bitPattern: Int8(grade)))
            records.append(msg)
        }

        // session (mesg 18)
        records.append(definitionMessage(
            local: 2,
            global: 18,
            fields: [
                (253, 4, 134), // timestamp
                (2, 4, 134),   // start_time
                (5, 1, 0),     // sport
                (6, 1, 0),     // sub_sport
                (7, 4, 134),   // total_elapsed_time (ms)
                (8, 4, 134),   // total_timer_time (ms)
                (9, 4, 134),   // total_distance (cm)
                (16, 1, 2),    // avg_heart_rate
                (18, 1, 2),    // avg_cadence
                (20, 2, 132),  // avg_power
                (21, 2, 132),  // max_power
                (26, 2, 132),  // num_laps
            ]
        ))
        var session = Data([0x02])
        appendUInt32(&session, endFit)
        appendUInt32(&session, startFit)
        session.append(sportCycling)
        session.append(subSportIndoorCycling)
        appendUInt32(&session, elapsedMs)
        appendUInt32(&session, elapsedMs)
        appendUInt32(&session, distanceCm)
        session.append(UInt8(min(255, avgHR)))
        session.append(UInt8(min(255, avgCadence)))
        appendUInt16(&session, UInt16(clamping: avgPower))
        appendUInt16(&session, UInt16(clamping: maxPower))
        appendUInt16(&session, 1) // num_laps
        records.append(session)

        // activity (mesg 34)
        records.append(definitionMessage(
            local: 3,
            global: 34,
            fields: [
                (253, 4, 134), // timestamp
                (0, 4, 134),   // total_timer_time (ms)
                (1, 2, 132),   // num_sessions
                (2, 1, 0),     // type
                (3, 1, 0),     // event
                (4, 1, 0),     // event_type
            ]
        ))
        var activity = Data([0x03])
        appendUInt32(&activity, endFit)
        appendUInt32(&activity, elapsedMs)
        appendUInt16(&activity, 1) // num_sessions
        activity.append(0) // type = manual
        activity.append(26) // event = activity
        activity.append(1) // event_type = stop
        records.append(activity)

        let dataSize = UInt32(records.count)
        file.replaceSubrange(4..<8, with: withUnsafeBytes(of: dataSize.littleEndian, Array.init))

        let headerCRC = crc16(Data(file.prefix(12)))
        file[12] = UInt8(headerCRC & 0xFF)
        file[13] = UInt8(headerCRC >> 8)

        file.append(records)
        let fileCRC = crc16(file)
        file.append(UInt8(fileCRC & 0xFF))
        file.append(UInt8(fileCRC >> 8))
        try file.write(to: url, options: .atomic)
    }

    private static func fitEpoch(_ date: Date) -> UInt32 {
        UInt32(max(0, date.timeIntervalSince1970 - 631_065_600))
    }

    private static func definitionMessage(local: UInt8, global: UInt16, fields: [(UInt8, UInt8, UInt8)]) -> Data {
        var data = Data([0x40 | local, 0x00, 0x00])
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

enum FitExportUI {
    @MainActor
    static func presentShareSheet(for url: URL, relativeTo view: NSView? = nil) {
        let picker = NSSharingServicePicker(items: [url])
        if let view {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            return
        }
        if let window = NSApp.keyWindow ?? NSApp.windows.first,
           let content = window.contentView {
            let rect = CGRect(x: content.bounds.midX, y: content.bounds.midY, width: 1, height: 1)
            picker.show(relativeTo: rect, of: content, preferredEdge: .minY)
        }
    }

    @MainActor
    static func presentSavePanel(for summary: WorkoutSummary, history: WorkoutHistoryStore) {
        guard let source = history.fitURL(for: summary) else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = summary.fitFileName ?? source.lastPathComponent
        panel.allowedContentTypes = [UTType(filenameExtension: "fit") ?? .data]
        panel.title = "Save workout FIT"
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                try history.exportFit(for: summary, to: destination)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }
}
