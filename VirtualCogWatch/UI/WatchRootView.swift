import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var model: WatchHeartRateModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("VirtualCog")
                    .font(.headline)
                Text("Heart rate")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(model.bpm.map(String.init) ?? "—")
                    .font(.system(size: 52, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                Text("bpm")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(model.status)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(model.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if model.subscriberCount > 0 {
                    Label("Mac connected", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                Button(model.isBroadcasting ? "Stop" : "Broadcast HR") {
                    model.toggle()
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isBroadcasting ? .red : .accentColor)
                .disabled(!model.canBroadcast && !model.isBroadcasting)
            }
            .padding(.horizontal, 6)
        }
    }
}
