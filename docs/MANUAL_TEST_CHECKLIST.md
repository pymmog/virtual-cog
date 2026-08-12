# Manual hardware checklist — KICKR CORE 2 + Zwift Click

Use after building `VirtualCog.xcodeproj` on macOS 14+. Quit Zwift / Wahoo / other BLE centrals first.

## Phase 1 — FTMS telemetry
- [ ] Scan finds KICKR CORE 2
- [ ] Connect → Indoor Bike Data power / cadence / speed update on Ride dashboard
- [ ] Disconnect/reconnect recovers within a few seconds

## Phase 2 — FTMS control
- [ ] Manual grade slider changes trainer load (SIM)
- [ ] ERG target holds watts within normal trainer tolerance
- [ ] Control-lost status recovers after Request Control

## Phase 3 — Zwift Hub
- [ ] Hub service discovered; RideOn handshake completes
- [ ] Hub power/cadence match FTMS within BLE jitter
- [ ] Hub virtual speed may differ from FTMS wheel speed (both shown when available)
- [ ] Weight write + incline write feel sane with Crr=400 / CWa=5100

## Phase 4 — Click + virtual gears
- [ ] Scan/pair Click (press button to wake)
- [ ] Plus/Minus change gear 1–24 on dashboard
- [ ] On flat SIM grade, constant cadence → load changes when shifting
- [ ] Held buttons do not spam shifts
- [ ] Firmware without encryption still connects via plain RideOn fallback

## Phase 5 — Course + session + FIT
- [ ] Select Demo Hills or import GPX
- [ ] Start ride → grade follows course distance
- [ ] Pause / resume / end work
- [ ] History lists ride; `.fit` file opens in a FIT-aware tool (power, cadence, HR, speed, grade, distance)

## Heart rate — strap or Apple Watch
- [ ] Scan finds a BLE HRM (Polar / TICKR / Garmin) or **VirtualCog HR**
- [ ] Connect → Ride tile shows BPM with source “Watch / HRM”
- [ ] Apple Watch: VirtualCogWatch → Broadcast HR → Mac connects while Watch workout is running
- [ ] Dedicated HRM wins over trainer-bridged HR; FIT includes HR; History shows avg bpm
- [ ] `--mock-ble` Connect mocks / Start demo ride shows mock Watch HR (~148 bpm)

## Notes
- CORE 2 VS firmware: ≥ 2.2.44 / 3.2.44
- Zwift Cog is passive — no pairing expected
- Prefer Hub path for native VS; FTMS remains fallback
- Apple Watch does not advertise HR to Mac without VirtualCog Watch (or another 0x180D Watch app)
- Watch Simulator cannot BLE-pair to Mac; use a real Watch
