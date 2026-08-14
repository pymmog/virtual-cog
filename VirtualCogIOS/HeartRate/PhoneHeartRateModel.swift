import Combine
import Foundation
import WatchConnectivity

/// Mirrors Watch HR status over WatchConnectivity so the iPhone companion can show live BPM.
@MainActor
final class PhoneHeartRateModel: NSObject, ObservableObject {
    @Published var payload = PhoneWatchPayload.empty
    @Published var watchReachable = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
}

extension PhoneHeartRateModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.watchReachable = session.isReachable
            if !session.receivedApplicationContext.isEmpty {
                self.payload = PhoneWatchPayload.from(session.receivedApplicationContext)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.watchReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.payload = PhoneWatchPayload.from(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.payload = PhoneWatchPayload.from(message)
        }
    }
}
