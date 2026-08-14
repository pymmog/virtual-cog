# virtual-cog

Native macOS training client for **KICKR CORE 2** with **Zwift Click** virtual shifting, slope/ERG simulation, GPX course running, FIT logging, and **Apple Watch / BLE heart rate**.

The **Zwift Cog** is a passive mechanical part (no electronics). Virtual shifting is Click → app gear index → trainer Hub/FTMS protocol.

Unofficial interoperability only — not affiliated with Zwift or Wahoo.

## Plan

See **[PLAN.md](PLAN.md)** for architecture, BLE/protocol connections, physics/course design, and implementation phases.

## Open in Xcode

1. Open `VirtualCog.xcodeproj` on macOS 14+
2. Wait for SPM packages (`CryptoSwift`, `SwiftProtobuf`) to resolve
3. Enable Bluetooth permission when prompted
4. Run the `VirtualCog` scheme
5. Optional: add launch argument `--mock-ble` to exercise UI without hardware
6. For live Apple Watch HR: plug in the **iPhone**, select the `VirtualCogIOS` scheme, Run on the iPhone. Xcode installs the Watch companion automatically. On the Watch tap **Broadcast HR**, and keep the Mac `VirtualCog` app open.

## Apple Watch heart rate

Apple Watch does **not** advertise the Bluetooth Heart Rate Profile (watchOS has no `CBPeripheralManager`), and macOS HealthKit is iCloud-synced (not live). Pairing:

1. Mac app advertises a custom ingest service as soon as it launches
2. Watch app starts an indoor cycling workout (HealthKit), connects to VirtualCog, and writes BPM
3. Live BPM overlays trainer-bridged HR and is written into the FIT file

Chest straps (Polar, Wahoo TICKR, Garmin) use the same Setup column.

## Layout

```
VirtualCog/
  App/           # SwiftUI entry, entitlements, Info.plist
  BLE/           # CBCentralManager + peripheral delegate router
  Devices/
    Click/       # ECDH / AES-CCM handshake + keypad
    HeartRate/   # BLE HRM central (0x180D)
    Kickr/       # Zwift Hub + FTMS (+ DirCon stub)
    Shared/      # UUIDs, protobuf + HR codecs, zwift.proto
  Physics/       # 24-gear model + Click debounce
  Course/        # GPX → distance/grade
  Session/       # ride state machine
  Telemetry/     # live metrics + NP/IF/TSS estimates
  Workout/       # FIT encoder + history
  UI/            # Setup, Ride, Courses, History
  Mocks/         # BLE fixtures
VirtualCogIOS/   # iPhone companion (installs the Watch app)
VirtualCogWatch/ # Watch HR companion (HealthKit + BLE to Mac)
SharedPhoneWatch/ # WatchConnectivity payload
```

## Tests

```bash
# Protocol / AES-CCM / gear golden tests (no macOS required)
python3 Scripts/golden_tests.py

# On macOS with Swift toolchain:
swift test
```

Hardware checklist: [docs/MANUAL_TEST_CHECKLIST.md](docs/MANUAL_TEST_CHECKLIST.md)

## Phase status

| Phase | Status |
| --- | --- |
| 0 Skeleton (Xcode, entitlements, modules, proto) | Done |
| 1 FTMS telemetry | Done (code + mocks) |
| 2 FTMS control | Done (code + mocks) |
| 3 Zwift Hub trainer | Done (code + mocks) |
| 4 Click + virtual gears | Done (code + mocks) |
| 5 Course + session + FIT | Done (code + mocks) |
| 6 Hardening (DirCon stub, mocks, golden tests) | Foundations in place |
| Direct HR strap + Apple Watch BLE HR | Done (code + mocks; Watch needs a real device) |

Full validation of VS load feel requires real CORE 2 (≥ firmware 2.2.44 / 3.2.44) + Click.
