import SwiftUI
import UniformTypeIdentifiers

struct CoursePicker: View {
    @EnvironmentObject private var app: AppModel
    @State private var isImporterPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Courses")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Spacer()
                Button("Import GPX") { isImporterPresented = true }
            }

            List(selection: Binding(
                get: { app.courses.selected?.id },
                set: { id in
                    app.courses.selected = app.courses.courses.first { $0.id == id }
                }
            )) {
                ForEach(app.courses.courses) { course in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(course.name).font(.headline)
                        Text(String(format: "%.1f km · +%.0f m", course.totalDistanceMeters / 1000, course.totalElevationGainMeters))
                            .foregroundStyle(.secondary)
                    }
                    .tag(course.id)
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: 280)

            if let selected = app.courses.selected {
                CourseProfileView(course: selected, distanceMeters: 0)
                    .frame(height: 100)
                Text("Start a ride from the Ride tab to follow this grade profile.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.gpxType, .xml, .data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                try? app.courses.importFile(url: url)
            }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("History")
                .font(.system(size: 34, weight: .semibold, design: .rounded))

            if app.history.items.isEmpty {
                Text("Finished rides show up here. Export the FIT file, AirDrop it to your iPhone, then import with HealthFit or RunGap into Apple Health (Fitness can’t open FIT directly).")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(app.history.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.courseName).font(.headline)
                            Text(item.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                            Text(historyLine(for: item))
                            if let name = item.fitFileName {
                                Text("FIT: \(name)")
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer(minLength: 8)
                        if app.history.fitURL(for: item) != nil {
                            VStack(spacing: 8) {
                                Button("Share") {
                                    app.shareFit(for: item)
                                }
                                Button("Save…") {
                                    FitExportUI.presentSavePanel(for: item, history: app.history)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
    }

    private func historyLine(for item: WorkoutSummary) -> String {
        var parts = [
            String(format: "%.1f km", item.distanceMeters / 1000),
            String(format: "avg %.0f W", item.averagePower),
            String(format: "max %d W", item.maxPower),
            String(format: "+%.0f m", item.elevationGainMeters)
        ]
        if let hr = item.averageHeartRate {
            parts.append("avg \(hr) bpm")
        }
        return parts.joined(separator: " · ")
    }
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        SettingsForm(settings: app.settings)
    }
}

private struct SettingsForm: View {
    @ObservedObject var settings: RiderSettingsStore

    var body: some View {
        Form {
            Section("Simulation defaults") {
                Text("Crr scaled (×100000): \(settings.crrScaled)")
                Text("CWa scaled (×10000): \(settings.cwaScaled)")
                Text("Defaults match documented Zwift Hub values (400 / 5100). Wrong scaling breaks gear/slope feel.")
                    .foregroundStyle(.secondary)
            }
            Section("Heart rate") {
                Text("Pair a BLE heart-rate monitor on the Setup tab, or run VirtualCog HR on Apple Watch while this Mac app is open. Apple Watch cannot advertise 0x180D; the Watch connects to VirtualCog instead.")
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                Text("VirtualCog is an unofficial interoperability client. Zwift Cog is passive mechanical — no BLE.")
                Text("Not affiliated with Zwift or Wahoo.")
            }
        }
        .frame(width: 420, height: 320)
        .padding()
    }
}

extension UTType {
    static var gpxType: UTType {
        UTType(filenameExtension: "gpx") ?? .xml
    }
}
