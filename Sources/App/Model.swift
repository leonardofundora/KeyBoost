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
                ? L("The engine is not responding. Try turning “Start at login” off and on again.")
                : L("The engine is not running. Turn on “Start at login” to start it.")
        }
        if !status.apiAvailable {
            return L("This version of macOS no longer exposes the latency setting. KeyBoost cannot help.")
        }
        return nil
    }

    var headline: String {
        if !settings.enabled { return L("Disabled") }
        if problem != nil { return L("Stopped") }
        return status.active ? L("Boosting") : L("Idle")
    }

    var isBoosting: Bool { settings.enabled && problem == nil && status.active }

    var stateColor: Color {
        if !settings.enabled || problem != nil { return .secondary }
        return status.active ? .green : .orange
    }

    var latencyChoice: Settings.LatencyChoice? {
        Settings.latencyChoices.first { $0.level == settings.latencyLevel }
    }

    /// Línea bajo el desplegable de latencia: "intervalo … · peor caso ~N ms".
    var latencyDetail: String? {
        guard let choice = latencyChoice else { return nil }
        return L("%@ · worst case ~%d ms", choice.detail, choice.worstCaseMs)
    }

    /// Advertencia proporcional: el nivel más alto es literalmente peor que no usar la app.
    var latencyWarning: String? {
        guard let choice = latencyChoice, !choice.isSafe else { return nil }
        return choice.level == 2
            ? L("Worst case ~%d ms instead of 30. That is slower than the bug KeyBoost fixes (345 ms), so your keyboard will be worse off than without the app.", choice.worstCaseMs)
            : L("Worst case ~%d ms instead of 30. Noticeable while typing, but easier on the battery.", choice.worstCaseMs)
    }

    /// Texto de estado por dispositivo, en la columna derecha de la lista.
    func detail(for device: DeviceStatus) -> String {
        if !device.present { return L("away") }
        if !settings.boosts(device.address) { return "—" }
        if !settings.enabled { return L("off") }
        return device.boosted ? L("latency 0") : L("idle")
    }
}
