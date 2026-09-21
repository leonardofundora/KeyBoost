import AppKit
import Foundation

/// Orquesta todo: lee ajustes, decide turbo o reposo, publica estado.
final class AgentController {
    private let engine = BluetoothEngine()
    private let inventory = DeviceInventory()
    private var menuBar: MenuBarController?

    private var settings = Settings.load()
    private var lastPublished: AgentStatus?
    private var lastWrite: Date = .distantPast
    private var knownNames: [String: String] = [:]
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var settingsStamp: Date?

    func start() {
        // Nombres de dispositivos ausentes, para no mostrarlos como "desconocido".
        for device in AgentStatus.load().devices { knownNames[device.address] = device.name }

        observers.append(IPC.observe(.settingsChanged) { [weak self] in
            self?.reloadSettings()
        })

        // Dormir el Mac suelta los enlaces: no tiene sentido mantener turbo con la tapa cerrada.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Log.write("el Mac se duerme, soltando enlaces")
            self?.engine.releaseAll()
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.tick()
        })

        engine.latencyLevel = settings.latencyLevel
        settingsStamp = Self.settingsModified()
        engine.onStateChange = { [weak self] in self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        syncMenuBar()
        Log.write("motor arrancado")
    }

    /// Relee los ajustes y propaga lo que haya cambiado.
    private func reloadSettings() {
        let previousLevel = settings.latencyLevel
        settings = Settings.load()
        settingsStamp = Self.settingsModified()
        engine.latencyLevel = settings.latencyLevel
        if previousLevel != settings.latencyLevel { engine.invalidateRequests() }
        Log.write("ajustes: activado=\(settings.enabled) barra=\(settings.showMenuBarIcon) "
                  + "reposo=\(settings.idleReleaseSeconds)s latencia=\(settings.latencyLevel)")
        syncMenuBar()
        tick()
    }

    private static func settingsModified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Paths.settings.path))?[.modificationDate] as? Date
    }

    /// Red de seguridad: si el fichero cambia sin notificación (editado a mano, restaurado
    /// de una copia), el motor se entera igual en el siguiente tick.
    private func reloadSettingsIfFileChanged() {
        let stamp = Self.settingsModified()
        guard stamp != settingsStamp else { return }
        settingsStamp = stamp
        reloadSettings()
    }

    private func syncMenuBar() {
        if settings.showMenuBarIcon {
            if menuBar == nil {
                menuBar = MenuBarController(
                    onToggleEnabled: { [weak self] in
                        guard let self else { return }
                        self.settings.enabled.toggle()
                        self.settings.save()
                    },
                    onHideIcon: { [weak self] in
                        guard let self else { return }
                        self.settings.showMenuBarIcon = false
                        self.settings.save()
                    })
            }
        } else {
            menuBar = nil
        }
    }

    private func tick() {
        reloadSettingsIfFileChanged()
        let live = engine.liveDevices()
        inventory.refreshIfNeeded(addresses: live.map(\.address))
        for device in live { knownNames[device.address] = device.name }

        var devices: [DeviceStatus] = []
        var anyBoosted = false

        for device in live {
            let kind = inventory.kind(for: device.address)
            let wanted = settings.enabled && settings.boosts(device.address)
            if wanted {
                let idle = ActivityMonitor.idleSeconds(for: kind)
                let keepAwake = settings.idleReleaseSeconds == 0
                    || idle < Double(settings.idleReleaseSeconds)
                if keepAwake { engine.boost(device) } else { engine.release(device.address) }
            } else {
                engine.release(device.address)
            }
            let boosted = engine.isBoosted(device.address)
            anyBoosted = anyBoosted || boosted
            devices.append(DeviceStatus(address: device.address, name: device.name,
                                        kind: kind, present: true, boosted: boosted))
        }

        // Configurados pero no visibles ahora: se conservan para que no desaparezcan de la lista.
        let present = Set(live.map { $0.address.uppercased() })
        for address in settings.boostedAddresses where !present.contains(address.uppercased()) {
            devices.append(DeviceStatus(address: address,
                                        name: knownNames[address] ?? address,
                                        kind: inventory.kind(for: address),
                                        present: false, boosted: false))
        }
        devices.sort { ($0.present ? 0 : 1, $0.name.lowercased()) < ($1.present ? 0 : 1, $1.name.lowercased()) }

        publish(AgentStatus(bluetooth: engine.state, active: anyBoosted,
                            apiAvailable: engine.apiAvailable, devices: devices, updated: Date()))
    }

    /// Escribe solo si algo cambió, o cada 5 s para que la interfaz sepa que seguimos vivos.
    private func publish(_ status: AgentStatus) {
        var changed = true
        if var previous = lastPublished {
            previous.updated = status.updated
            changed = previous != status
        }
        guard changed || Date().timeIntervalSince(lastWrite) >= 5 else { return }
        status.save()
        lastPublished = status
        lastWrite = Date()
        menuBar?.update(status: status, settings: settings)
    }
}
