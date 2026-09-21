import Combine
import Foundation
import SwiftUI

/// Puente entre los ficheros compartidos y la vista.
final class Model: ObservableObject {
    @Published var settings: Settings = .load()
    @Published var status: AgentStatus = .load()
    @Published var launchAtLogin: Bool = LoginItem.isEnabled

    private var observer: NSObjectProtocol?
    private var timer: Timer?

    init() {
        observer = IPC.observe(.statusChanged) { [weak self] in
            self?.status = .load()
        }
        // Red de seguridad por si se pierde una notificación.
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.status = .load()
        }
    }

    func edit(_ mutate: (inout Settings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
        copy.save()
    }

    func setBoosted(_ address: String, _ on: Bool) {
        edit { settings in
            settings.boostedAddresses.removeAll { $0.caseInsensitiveCompare(address) == .orderedSame }
            if on { settings.boostedAddresses.append(address) }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        LoginItem.setEnabled(on)
        launchAtLogin = LoginItem.isEnabled
    }

    /// Qué hay que contarle al usuario, si es que hay algo.
    var problem: String? {
        if let issue = status.bluetooth.problem { return issue }
        if !status.agentAlive {
            return launchAtLogin
                ? "El motor no está respondiendo. Prueba a desactivar y reactivar el arranque automático."
                : "El motor no está corriendo. Activa «Arrancar al iniciar sesión» para ponerlo en marcha."
        }
        if !status.apiAvailable {
            return "Esta versión de macOS ya no expone el ajuste de latencia. KeyBoost no puede acelerar nada."
        }
        return nil
    }

    var latencyChoice: Settings.LatencyChoice? {
        Settings.latencyChoices.first { $0.level == settings.latencyLevel }
    }

    /// Advertencia proporcional: el nivel más alto es literalmente peor que no usar la app.
    var latencyWarning: String? {
        guard let choice = latencyChoice, !choice.isSafe else { return nil }
        let base = "Peor caso ~\(choice.worstCaseMs) ms en vez de 30. "
        return choice.level == 2
            ? base + "Es más lento que el fallo que KeyBoost corrige (345 ms): así el teclado irá peor que sin la app."
            : base + "Se nota al teclear, pero ahorra batería."
    }

    var headline: String {
        if !settings.enabled { return "Desactivado" }
        if problem != nil { return "Detenido" }
        return status.active ? "Turbo" : "En reposo"
    }

    var isBoosting: Bool { settings.enabled && problem == nil && status.active }

    var stateColor: Color {
        if !settings.enabled || problem != nil { return .secondary }
        return status.active ? .green : .orange
    }

    /// Texto de estado por dispositivo, en la columna derecha de la lista.
    func detail(for device: DeviceStatus) -> String {
        if !device.present { return "ausente" }
        if !settings.boosts(device.address) { return "—" }
        if !settings.enabled { return "desactivado" }
        return device.boosted ? "latency 0" : "en reposo"
    }
}
