import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        PairingContent(app: app, settings: app.settings)
    }
}

private struct PairingContent: View {
    @ObservedObject var app: AppModel
    @ObservedObject var settings: RiderSettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Setup")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text("Quit Zwift, Wahoo, and other BLE training apps before pairing. Only one central should own the trainer and Click.")
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 20) {
                    deviceColumn(
                        title: "KICKR CORE 2",
                        devices: app.ble.discoveredTrainers,
                        connect: { app.ble.connectTrainer(id: $0) }
                    )
                    deviceColumn(
                        title: "Zwift Click",
                        devices: app.ble.discoveredClicks,
                        connect: { app.ble.connectClick(id: $0) }
                    )
                    heartRateColumn()
                }

                Text("Apple Watch cannot advertise the Heart Rate Profile. Keep this Mac app open — it listens for VirtualCog HR automatically — then tap Broadcast HR on the Watch. Chest straps (Polar, TICKR, Garmin) still pair via Scan as BLE 0x180D.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Scan for devices") {
                        app.ble.startScan()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Stop scan") {
                        app.ble.stopScan()
                    }

                    if app.ble.useMocks {
                        Button("Connect mocks") {
                            app.ble.connectAllMocks()
                        }
                        Button("Start demo ride") {
                            app.startMockDemoRide()
                        }
                        .buttonStyle(.borderedProminent)
                        Text("Mock BLE enabled")
                            .foregroundStyle(.orange)
                    }
                }

                if app.ble.useMocks {
                    Text("Demo ride pairs the mock trainer, Click, and heart-rate monitor, selects a course, and starts a session on the Ride tab. End the ride to open a Share sheet for the FIT (AirDrop → HealthFit/RunGap → Apple Health).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Rider & bike") {
                    VStack(alignment: .leading) {
                        SteppedNumber(title: "Rider weight (kg)", value: $settings.riderWeightKg, range: 40...140, step: 0.5)
                        SteppedNumber(title: "Bike weight (kg)", value: $settings.bikeWeightKg, range: 5...20, step: 0.1)
                        Toggle("Prefer Zwift Hub over FTMS", isOn: $settings.preferHubOverFtms)
                        Button("Save settings") {
                            settings.save()
                            app.session.preferHub = settings.preferHubOverFtms
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
        }
    }

    private func deviceColumn(title: String, devices: [BlePeripheralSummary], connect: @escaping (UUID) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            if devices.isEmpty {
                Text("No devices yet — press Scan.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(devices) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("RSSI \(device.rssi) dBm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect") { connect(device.id) }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heartRateColumn() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heart rate")
                .font(.headline)

            if !app.ble.useMocks {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Apple Watch")
                        Text(watchIngestDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if app.ble.watchIngest.watchConnected || app.ble.heartRate.deviceName == HeartRateUUID.watchAdvertisedName {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }

            let straps = app.ble.discoveredHeartRateMonitors
            if straps.isEmpty {
                Text(app.ble.useMocks ? "No devices yet — press Scan." : "Chest straps appear after Scan.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(straps) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("RSSI \(device.rssi) dBm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect") { app.ble.connectHeartRate(id: device.id) }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var watchIngestDetail: String {
        if let error = app.ble.watchIngest.lastError {
            return error
        }
        if app.ble.watchIngest.watchConnected || app.ble.heartRate.deviceName == HeartRateUUID.watchAdvertisedName {
            if let bpm = app.ble.heartRate.lastBpm {
                return "Connected · \(bpm) bpm"
            }
            return "Watch connected"
        }
        if app.ble.watchIngest.isAdvertising {
            return "Listening — tap Broadcast HR on the Watch"
        }
        return "Starting Bluetooth…"
    }
}

struct SteppedNumber: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value, format: .number.precision(.fractionLength(1)))
                .monospacedDigit()
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
    }
}
