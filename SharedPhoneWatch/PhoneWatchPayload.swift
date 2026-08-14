import Foundation

/// WatchConnectivity dictionary shared by the iPhone companion and Watch HR app.
struct PhoneWatchPayload: Equatable {
    var bpm: Int?
    var status: String
    var detail: String
    var isBroadcasting: Bool
    var macConnected: Bool
    var simulated: Bool

    static let empty = PhoneWatchPayload(
        bpm: nil,
        status: "Waiting for Watch",
        detail: "Install this iPhone app, then open VirtualCog HR on the Watch and tap Broadcast HR.",
        isBroadcasting: false,
        macConnected: false,
        simulated: false
    )

    func asContext() -> [String: Any] {
        var dict: [String: Any] = [
            "status": status,
            "detail": detail,
            "isBroadcasting": isBroadcasting,
            "macConnected": macConnected,
            "simulated": simulated
        ]
        if let bpm {
            dict["bpm"] = bpm
        }
        return dict
    }

    static func from(_ dict: [String: Any]) -> PhoneWatchPayload {
        PhoneWatchPayload(
            bpm: dict["bpm"] as? Int,
            status: dict["status"] as? String ?? "Watch",
            detail: dict["detail"] as? String ?? "",
            isBroadcasting: dict["isBroadcasting"] as? Bool ?? false,
            macConnected: dict["macConnected"] as? Bool ?? false,
            simulated: dict["simulated"] as? Bool ?? false
        )
    }
}
