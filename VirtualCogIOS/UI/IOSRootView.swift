import SwiftUI

struct IOSRootView: View {
    @EnvironmentObject private var model: PhoneHeartRateModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("VirtualCog")
                    .font(.largeTitle.weight(.semibold))
                Text("Watch heart rate")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(model.payload.bpm.map(String.init) ?? "—")
                    .font(.system(size: 96, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                Text("bpm")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text(model.payload.status)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(model.payload.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if model.payload.macConnected {
                    Label("Mac connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Spacer()

                Text("Run this iPhone app from Xcode to install the Watch app. Broadcast HR on the Watch, and keep VirtualCog open on the Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
