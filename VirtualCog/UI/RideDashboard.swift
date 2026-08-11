import SwiftUI

struct RideDashboard: View {
    @EnvironmentObject private var app: AppModel

    private var live: LiveTelemetry { app.session.telemetry.live }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Ride")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Spacer()
                Picker("Mode", selection: modeBinding) {
                    ForEach([TrainerMode.sim, .erg], id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                MetricTile(label: "Power", value: "\(live.powerWatts)", unit: "W")
                MetricTile(label: "Cadence", value: String(format: "%.0f", live.cadenceRpm), unit: "rpm")
                MetricTile(label: "Speed", value: String(format: "%.1f", live.speedKmh), unit: "km/h")
                MetricTile(label: "Heart rate", value: live.heartRateBpm.map(String.init) ?? "—", unit: "bpm")
                MetricTile(label: "Gear", value: "\(live.gearIndex)", unit: String(format: "%.2f×", live.gearRatio))
                MetricTile(label: "Grade", value: String(format: "%+.1f", live.gradePercent), unit: "%")
                MetricTile(label: "Distance", value: String(format: "%.2f", live.distanceMeters / 1000), unit: "km")
                MetricTile(label: "Moving", value: formatTime(live.movingTimeSeconds), unit: "")
            }

            if let hub = live.hubVirtualSpeedKmh, let wheel = live.ftmsWheelSpeedKmh {
                Text("Hub virtual \(String(format: "%.1f", hub)) km/h · FTMS wheel \(String(format: "%.1f", wheel)) km/h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            CourseProfileView(
                course: app.courses.selected,
                distanceMeters: app.session.distanceMeters
            )
            .frame(height: 120)

            if app.session.mode == .sim && app.courses.selected == nil {
                HStack {
                    Text("Manual grade")
                    Slider(value: manualGradeBinding, in: -10...15, step: 0.1)
                    Text(app.session.manualGradePercent, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }

            if app.session.mode == .erg {
                HStack {
                    Text("ERG target")
                    Slider(
                        value: Binding(
                            get: { Double(app.session.ergTargetWatts) },
                            set: { app.session.updateERG(UInt16($0.rounded())) }
                        ),
                        in: 50...400,
                        step: 5
                    )
                    Text("\(app.session.ergTargetWatts) W")
                        .monospacedDigit()
                }
            }

            HStack(spacing: 12) {
                Button(app.session.isRiding ? "Riding…" : "Start ride") {
                    app.session.startRide()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!app.session.canStart || app.session.isRiding)

                Button(app.session.isPaused ? "Resume" : "Pause") {
                    app.session.togglePause()
                }
                .disabled(!app.session.isRiding && !app.session.isPaused)

                Button("End") {
                    app.session.endRide()
                }
                .disabled(!app.session.isRiding && !app.session.isPaused)

                if app.ble.useMocks {
                    Button("Mock +") { app.ble.click.simulateButton(plus: true) }
                    Button("Mock −") { app.ble.click.simulateButton(minus: true) }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private var modeBinding: Binding<TrainerMode> {
        Binding(
            get: { app.session.mode },
            set: { app.session.setMode($0) }
        )
    }

    private var manualGradeBinding: Binding<Double> {
        Binding(
            get: { app.session.manualGradePercent },
            set: { app.session.updateManualGrade($0) }
        )
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CourseProfileView: View {
    let course: Course?
    let distanceMeters: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                if let course, course.totalDistanceMeters > 0 {
                    profilePath(course: course, size: geo.size)
                        .stroke(Color.accentColor.opacity(0.85), lineWidth: 2)
                    let x = CGFloat(distanceMeters / course.totalDistanceMeters) * geo.size.width
                    Rectangle()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: 2)
                        .offset(x: min(max(0, x), geo.size.width - 2))
                } else {
                    Text("Select a course for elevation profile")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
    }

    private func profilePath(course: Course, size: CGSize) -> Path {
        let elevs = course.points.map(\.elevationMeters)
        let minE = elevs.min() ?? 0
        let maxE = elevs.max() ?? 1
        let span = max(1, maxE - minE)
        return Path { path in
            for (idx, point) in course.points.enumerated() {
                let x = CGFloat(point.distanceMeters / course.totalDistanceMeters) * size.width
                let y = size.height - CGFloat((point.elevationMeters - minE) / span) * (size.height - 16) - 8
                if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }
}
