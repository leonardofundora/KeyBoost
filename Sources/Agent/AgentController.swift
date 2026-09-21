import AppKit
import Foundation

/// Ties everything together: reads settings, decides boost or idle, publishes status.
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
        // Names of absent devices, so they are not shown as "unknown".
        for device in AgentStatus.load().devices { knownNames[device.address] = device.name }

        observers.append(IPC.observe(.settingsChanged) { [weak self] in
            self?.reloadSettings()
        })

        // Sleeping releases the links: boosting a closed laptop makes no sense.
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

    /// Re-reads settings and propagates whatever changed.
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

    /// Safety net: if the file changes without a notification (hand-edited, restored from
    /// a backup), the engine still notices on the next tick.
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

        // Configured but not visible right now: kept so they do not vanish from the list.
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

    /// Writes only when something changed, or every 5 s so the interface knows we are alive.
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
