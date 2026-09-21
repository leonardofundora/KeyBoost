import Foundation

enum DeviceKind: String, Codable {
    case keyboard, pointing, other

    var label: String {
        switch self {
        case .keyboard: return "teclado"
        case .pointing: return "ratón"
        case .other:    return "—"
        }
    }
}

enum BluetoothState: String, Codable {
    case on, off, unauthorized, unsupported, unknown

    /// Texto para la interfaz, o nil si no hay nada que explicar.
    var problem: String? {
        switch self {
        case .on:           return nil
        case .off:          return "Bluetooth está apagado."
        case .unauthorized: return "Falta permiso de Bluetooth: Ajustes › Privacidad y seguridad › Bluetooth."
        case .unsupported:  return "Este Mac no soporta Bluetooth LE."
        case .unknown:      return "Estado de Bluetooth desconocido."
        }
    }
}

struct DeviceStatus: Codable, Equatable, Identifiable {
    var address: String
    var name: String
    var kind: DeviceKind
    /// Presente = visible ahora mismo. Un dispositivo ausente sigue en la configuración.
    var present: Bool
    var boosted: Bool
    var id: String { address }
}

struct AgentStatus: Codable, Equatable {
    var bluetooth: BluetoothState = .unknown
    /// Hay actividad de entrada reciente (estamos en turbo).
    var active: Bool = false
    /// El selector privado existe en esta version de macOS.
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

    /// El motor escribe cada pocos segundos; si lleva mucho callado, no esta vivo.
    var agentAlive: Bool { Date().timeIntervalSince(updated) < 15 }
}
