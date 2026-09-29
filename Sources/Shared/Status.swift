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
    /// Signal strength of the boosted device, when we hold a connection to read it.
    var rssi: Int?
    /// Share of the keyboard's packets the Mac failed to receive, over the last minute.
    var lossPercent: Double?
    /// How often the radio went down in the last hour. A high count means the Mac is
    /// sleeping or cycling Bluetooth, which no amount of latency tuning can compensate for.
    var radioCyclesLastHour: Int = 0
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

    enum Health: String, Codable { case good, fair, poor, unknown }

    /// A verdict on the link, from the two numbers that actually predict how it feels.
    /// Thresholds come from measurements on a link that worked: -49 dBm with 0 % loss.
    var health: Health {
        if radioCyclesLastHour >= 10 { return .poor }
        guard let rssi else { return .unknown }
        let loss = lossPercent ?? 0
        if loss > 10 || rssi < -75 { return .poor }
        if loss > 2 || rssi < -65 { return .fair }
        return .good
    }

    /// What is wrong with the link, in one line, or nil when nothing is.
    var healthProblem: String? {
        if radioCyclesLastHour >= 10 {
            return L("The Bluetooth radio went down %d times in the last hour. Check whether the Mac keeps sleeping.", radioCyclesLastHour)
        }
        if let loss = lossPercent, loss > 10 {
            return L("%@ %% of the keyboard's packets are not reaching the Mac. Something nearby is transmitting on 2.4 GHz.", String(format: "%.0f", loss))
        }
        if let rssi, rssi < -75 {
            return L("Signal at %d dBm. The keyboard is too far away, or something is in the way.", rssi)
        }
        if let loss = lossPercent, loss > 2 {
            return L("%@ %% packet loss. Usable, but there is interference around.", String(format: "%.0f", loss))
        }
        if let rssi, rssi < -65 {
            return L("Signal at %d dBm, weaker than it should be.", rssi)
        }
        return nil
    }
}
