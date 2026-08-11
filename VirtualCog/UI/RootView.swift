import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @State private var tab: AppTab = .setup

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView(selection: $tab) {
                PairingView()
                    .tabItem { Label("Setup", systemImage: "dot.radiowaves.left.and.right") }
                    .tag(AppTab.setup)
                RideDashboard()
                    .tabItem { Label("Ride", systemImage: "bicycle") }
                    .tag(AppTab.ride)
                CoursePicker()
                    .tabItem { Label("Courses", systemImage: "map") }
                    .tag(AppTab.courses)
                HistoryView()
                    .tabItem { Label("History", systemImage: "clock") }
                    .tag(AppTab.history)
            }
        }
        .background(AmbientBackground())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("VirtualCog")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("KICKR CORE 2 training")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            connectionPills
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var connectionPills: some View {
        HStack(spacing: 10) {
            StatusDot(title: "Trainer", state: trainerState)
            StatusDot(title: "Click", state: app.ble.click.connectionState)
        }
    }

    private var trainerState: ConnectionState {
        if app.ble.kickrHub.connectionState == .ready { return .ready }
        return app.ble.kickrFtms.connectionState
    }
}

enum AppTab: Hashable {
    case setup, ride, courses, history
}

struct StatusDot: View {
    let title: String
    let state: ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(title): \(state.label)")
                .font(.system(.caption, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }

    private var color: Color {
        switch state {
        case .ready, .connected: return .green
        case .scanning, .connecting, .reconnecting: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }
}

struct AmbientBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.96, blue: 0.97),
                Color(red: 0.86, green: 0.91, blue: 0.94),
                Color(red: 0.95, green: 0.94, blue: 0.90)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
