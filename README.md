# virtual-cog

Native macOS training client for **KICKR CORE 2** with **Zwift Click** virtual shifting, slope/ERG simulation, GPX course running, and FIT logging.

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

## Layout

```
VirtualCog/
  App/           # SwiftUI entry, entitlements, Info.plist
  BLE/           # CBCentralManager + peripheral delegate router
  Devices/
    Click/       # ECDH / AES-CCM handshake + keypad
    Kickr/       # Zwift Hub + FTMS (+ DirCon stub)
    Shared/      # UUIDs, protobuf codec, zwift.proto
  Physics/       # 24-gear model + Click debounce
  Course/        # GPX → distance/grade
  Session/       # ride state machine
  Telemetry/     # live metrics + NP/IF/TSS estimates
  Workout/       # FIT encoder + history
  UI/            # Setup, Ride, Courses, History
  Mocks/         # BLE fixtures
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

Full validation of VS load feel requires real CORE 2 (≥ firmware 2.2.44 / 3.2.44) + Click.
