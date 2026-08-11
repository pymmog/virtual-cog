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

## Notes
- CORE 2 VS firmware: ≥ 2.2.44 / 3.2.44
- Zwift Cog is passive — no pairing expected
- Prefer Hub path for native VS; FTMS remains fallback
