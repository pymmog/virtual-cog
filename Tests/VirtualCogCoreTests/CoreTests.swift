import XCTest
@testable import VirtualCogCore

final class GearModelTests: XCTestCase {
    func testTwentyFourGearsLinear() {
        var gear = GearModel(gearIndex: 1)
        XCTAssertEqual(gear.ratiosX10000.count, 24)
        XCTAssertEqual(gear.ratioX10000, GearModel.defaultRatiosX10000[0])
        for _ in 0..<23 { XCTAssertTrue(gear.shiftUp()) }
        XCTAssertFalse(gear.shiftUp())
        XCTAssertEqual(gear.gearIndex, 24)
        XCTAssertGreaterThan(gear.ratioX10000, GearModel.defaultRatiosX10000[0])
    }

    func testDebouncerIgnoresHold() {
        var debouncer = ClickDebouncer(minimumInterval: 0.2)
        let t0 = Date()
        let first: [ClickDebouncer.Event] = debouncer.process(plusDown: true, minusDown: false, now: t0)
        XCTAssertEqual(first, [.shiftUp])
        let held: [ClickDebouncer.Event] = debouncer.process(plusDown: true, minusDown: false, now: t0.addingTimeInterval(0.05))
        XCTAssertTrue(held.isEmpty)
        let released: [ClickDebouncer.Event] = debouncer.process(plusDown: false, minusDown: false, now: t0.addingTimeInterval(0.06))
        XCTAssertTrue(released.isEmpty)
        let second: [ClickDebouncer.Event] = debouncer.process(plusDown: true, minusDown: false, now: t0.addingTimeInterval(0.3))
        XCTAssertEqual(second, [.shiftUp])
    }
}

final class ProtobufGoldenTests: XCTestCase {
    func testHubRidingDataMakinoloVector() throws {
        let packet = BleMockFixtures.data(fromHex: BleMockFixtures.hubRidingDataHex)
        let unwrapped = try XCTUnwrap(ZwiftPacket.unwrap(packet))
        XCTAssertEqual(unwrapped.opcode, ZwiftOpcode.hubRidingData)
        let riding = try HubRidingData.decode(unwrapped.payload)
        XCTAssertEqual(riding.power, 190)
        XCTAssertEqual(riding.cadence, 80)
        XCTAssertEqual(riding.speedX100, 829)
        XCTAssertEqual(riding.hr, 0)
    }

    func testSimulationScalingDefaults() {
        let sim = SimulationParam(
            wind: ZwiftSimDefaults.wind,
            inclineX100: 350,
            cwa: ZwiftSimDefaults.cwa,
            crr: ZwiftSimDefaults.crr
        )
        let encoded = HubCommand(simulation: sim).encode()
        let decoded = try! SimulationParam.decode(
            // extract field 4 length-delimited manually via round-trip encode of simulation alone
            sim.encode()
        )
        XCTAssertEqual(decoded.inclineX100, 350)
        XCTAssertEqual(decoded.cwa, 5100)
        XCTAssertEqual(decoded.crr, 400)
        XCTAssertFalse(encoded.isEmpty)
    }

    func testClickKeyPadDecode() throws {
        let status = try ClickKeyPadStatus.decode(Data([0x08, 0x00, 0x10, 0x01]))
        XCTAssertEqual(status.buttonPlus, .on)
        XCTAssertEqual(status.buttonMinus, .off)
    }
}

final class FTMSCodecTests: XCTestCase {
    func testIndoorBikeDataPowerCadenceSpeed() {
        // flags: speed present (bit0=0), cadence (bit2), power (bit6) => 0x0044
        // speed 3210 => 32.10 km/h, cadence 170 => 85 rpm, power 200
        var data = Data([0x44, 0x00])
        data.append(contentsOf: [0x8A, 0x0C]) // 3210
        data.append(contentsOf: [0xAA, 0x00]) // 170
        data.append(contentsOf: [0xC8, 0x00]) // 200
        let parsed = IndoorBikeData.parse(data)
        XCTAssertEqual(parsed.instantaneousSpeedKmh!, 32.1, accuracy: 0.01)
        XCTAssertEqual(parsed.instantaneousCadenceRpm!, 85.0, accuracy: 0.01)
        XCTAssertEqual(parsed.instantaneousPowerWatts, 200)
    }

    func testSimulationControlPacket() {
        let pkt = FTMSControlBuilder.setIndoorBikeSimulation(gradePercentX100: 500)
        XCTAssertEqual(pkt[0], FTMSOpcode.setIndoorBikeSimulation)
        XCTAssertEqual(pkt.count, 1 + 2 + 2 + 1 + 1)
    }
}

final class CourseTests: XCTestCase {
    func testGPXGradeAndDistance() throws {
        let gpx = """
        <?xml version="1.0"?>
        <gpx><trk><name>T</name><trkseg>
        <trkpt lat="0.0" lon="0.0"><ele>0</ele></trkpt>
        <trkpt lat="0.001" lon="0.0"><ele>10</ele></trkpt>
        <trkpt lat="0.002" lon="0.0"><ele>10</ele></trkpt>
        </trkseg></trk></gpx>
        """
        let course = try GPXParser.parse(data: Data(gpx.utf8), name: "T")
        XCTAssertGreaterThan(course.totalDistanceMeters, 100)
        XCTAssertFalse(course.points.isEmpty)
        let mid = course.grade(atDistance: course.totalDistanceMeters / 2)
        XCTAssertTrue(mid.isFinite)
    }
}

final class AESCCMGoldenTests: XCTestCase {
    func testRoundTrip() throws {
        let crypto = ZwiftClickCrypto()
        let key = [UInt8](repeating: 0x11, count: 32)
        let suffix: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD]
        crypto.installKeysForTesting(encryptionKey: key, nonceSuffix: suffix)
        let plain = Data([ZwiftOpcode.clickKeyPad, 0x08, 0x00, 0x10, 0x01])
        let sealed = try crypto.encrypt(plain)
        XCTAssertGreaterThan(sealed.count, plain.count)
        // New instance with same keys & counter 0 for decrypt of first packet
        let crypto2 = ZwiftClickCrypto()
        crypto2.installKeysForTesting(encryptionKey: key, nonceSuffix: suffix)
        let opened = try crypto2.decrypt(sealed)
        XCTAssertEqual(opened, plain)
    }
}

final class FITEncoderTests: XCTestCase {
    func testCRCAndFileWrite() throws {
        let samples = [
            WorkoutSample(
                timestamp: Date(),
                power: 200,
                cadence: 90,
                speedKmh: 30,
                heartRate: 140,
                gradePercent: 3,
                distanceMeters: 100,
                gearIndex: 12
            )
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.fit")
        try FITEncoder.encode(samples: samples, start: Date(), to: url)
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 20)
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), ".FIT")
        // verify CRC trailer validates whole file minus CRC
        let body = data.dropLast(2)
        let expected = FITEncoder.crc16(Data(body))
        let actual = UInt16(data[data.count - 2]) | (UInt16(data[data.count - 1]) << 8)
        XCTAssertEqual(actual, expected)
    }
}
