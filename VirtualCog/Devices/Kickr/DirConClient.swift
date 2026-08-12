import Foundation
import Network

/// Optional DirCon / Wi‑Fi transport stub (Phase 6).
/// Classic DirCon exposes GATT-over-TCP via Bonjour `_wahoo-fitness-tnp._tcp` (often port 36866).
@MainActor
final class DirConClient: ObservableObject {
    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var discoveredHosts: [String] = []

    private var browser: NWBrowser?
    private var connection: NWConnection?

    func startBrowse() {
        state = .scanning
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_wahoo-fitness-tnp._tcp", domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.stateUpdateHandler = { _ in }
        browser.browseResultsChangedHandler = { [weak self] (results: Set<NWBrowser.Result>, _: Set<NWBrowser.Result.Change>) in
            Task { @MainActor in
                self?.discoveredHosts = results.compactMap { result in
                    switch result.endpoint {
                    case .service(let name, _, _, _):
                        return name
                    default:
                        return nil
                    }
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stopBrowse() {
        browser?.cancel()
        browser = nil
        if state == .scanning { state = .idle }
    }

    /// Placeholder connection — framing/GATT proxy to be layered behind KickrFtmsClient.
    func connect(host: String, port: UInt16 = 36866) {
        state = .connecting
        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.state = .ready
                case .failed(let error):
                    self?.state = .failed(error.localizedDescription)
                case .cancelled:
                    self?.state = .disconnected
                default:
                    break
                }
            }
        }
        conn.start(queue: .main)
        connection = conn
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        state = .disconnected
    }
}
