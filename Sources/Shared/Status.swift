import Foundation

enum DeviceKind: String, Codable {
    case keyboard, pointing, other

    var label: String {
        switch self {
        case .keyboard: return L("keyboard")
        case .pointing: return L("mouse")
        case .other:    return "—"
        }
    }
}

enum BluetoothState: String, Codable {
    case on, off, unauthorized, unsupported, unknown

    /// Text for the interface, or nil when there is nothing to explain.
    var problem: String? {
        switch self {
        case .on:           return nil
        case .off:          return L("Bluetooth is turned off.")
        case .unauthorized: return L("Bluetooth permission missing: Settings › Privacy & Security › Bluetooth.")
        case .unsupported:  return L("This Mac does not support Bluetooth LE.")
        case .unknown:      return L("Bluetooth state unknown.")
        }
    }
}

struct DeviceStatus: Codable, Equatable, Identifiable {
    var address: String
    var name: String
    var kind: DeviceKind
    /// Present means visible right now. An absent device stays in the configuration.
    var present: Bool
    var boosted: Bool
    var id: String { address }
}

struct AgentStatus: Codable, Equatable {
    var bluetooth: BluetoothState = .unknown
    /// There has been recent input activity, so we are boosting.
    var active: Bool = false
    /// Whether the private selector exists on this version of macOS.
    var apiAvailable: Bool = true
    var devices: [DeviceStatus] = []
    var updated: Date = .init()

    static func load() -> AgentStatus {
        JSONStore.read(AgentStatus.self, from: Paths.status) ?? AgentStatus()
    }

    func save() {
        JSONStore.write(self, to: Paths.status)
        IPC.post(.statusChanged)
    }

    /// The engine writes every few seconds; a long silence means it is not running.
    var agentAlive: Bool { Date().timeIntervalSince(updated) < 15 }
}
