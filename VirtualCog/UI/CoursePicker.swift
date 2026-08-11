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
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.xml, .data], allowsMultipleSelection: false) { result in
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
                Text("Finished rides will show up here with FIT export paths.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(app.history.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.courseName).font(.headline)
                        Text(item.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                        Text(String(
                            format: "%.1f km · avg %.0f W · max %d W · +%.0f m",
                            item.distanceMeters / 1000,
                            item.averagePower,
                            item.maxPower,
                            item.elevationGainMeters
                        ))
                        if let name = item.fitFileName {
                            Text("FIT: \(name)")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
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
            Section("About") {
                Text("VirtualCog is an unofficial interoperability client. Zwift Cog is passive mechanical — no BLE.")
                Text("Not affiliated with Zwift or Wahoo.")
            }
        }
        .frame(width: 420, height: 240)
        .padding()
    }
}
