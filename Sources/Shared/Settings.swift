import Foundation

struct Settings: Codable, Equatable {
    /// Interruptor maestro. Apagado, el motor no toca ningun enlace.
    var enabled: Bool = true
    /// El icono de la barra lo crea el motor. Apagado por defecto: el usuario no quiere saturarla.
    var showMenuBarIcon: Bool = false
    /// Segundos sin actividad antes de soltar el enlace. 0 = no soltar nunca.
    var idleReleaseSeconds: Int = 180
    /// Direcciones fisicas (no UUID) de los dispositivos a acelerar.
    var boostedAddresses: [String] = []
    /// Nivel de `CBConnectionLatency`: 0 = low, 1 = medium, 2 = high.
    /// Subirlo ahorra batería a costa de retardo. Ver `latencyChoices`.
    var latencyLevel: Int = 0

    /// Medido en macOS 27.2 sobre un AK832 Pro: son los parámetros que negocia
    /// `bluetoothd` para cada nivel, no estimaciones.
    struct LatencyChoice {
        let level: Int
        let label: String
        let detail: String
        /// Peor caso aproximado: intervalo máximo × (1 + peripheralLatency).
        let worstCaseMs: Int
        var isSafe: Bool { level == 0 }
    }

    static let latencyChoices: [LatencyChoice] = [
        .init(level: 0, label: "Máxima respuesta",
              detail: "intervalo 10–30 ms, sin saltos", worstCaseMs: 30),
        .init(level: 1, label: "Equilibrada",
              detail: "intervalo 100–120 ms, 1 salto", worstCaseMs: 240),
        .init(level: 2, label: "Mínimo consumo",
              detail: "intervalo 290–320 ms, 1 salto", worstCaseMs: 640),
    ]

    static let idleChoices: [(label: String, seconds: Int)] = [
        ("30 segundos", 30), ("1 minuto", 60), ("3 minutos", 180),
        ("10 minutos", 600), ("Nunca soltar", 0),
    ]

    static func load() -> Settings {
        JSONStore.read(Settings.self, from: Paths.settings) ?? Settings()
    }

    func save() {
        JSONStore.write(self, to: Paths.settings)
        IPC.post(.settingsChanged)
    }

    func boosts(_ address: String) -> Bool {
        boostedAddresses.contains { $0.caseInsensitiveCompare(address) == .orderedSame }
    }
}
