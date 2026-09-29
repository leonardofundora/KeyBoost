import AppKit
import Foundation

/// Ties everything together: reads settings, decides boost or idle, publishes status.
final class AgentController {
    private let engine = BluetoothEngine()
    private let inventory = DeviceInventory()
    private let monitor = LinkMonitor()
    private var menuBar: MenuBarController?

    private var settings = Settings.load()
    private var lastPublished: AgentStatus?
    private var lastWrite: Date = .distantPast
    private var knownNames: [String: String] = [:]
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var settingsStamp: Date?
    private var lastRSSISample: Date = .distantPast
    private var lastHistoryWrite: Date = .distantPast
    /// When the link last became continuously boosted. A loss figure measured across a
    /// reconnect counts the silence as lost packets and reports a fault that is not there.
    private var boostedSince: Date?

    func start() {
        // Names of absent devices, so they are not shown as "unknown".
        for device in AgentStatus.load().devices { knownNames[device.address.uppercased()] = device.name }

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
            // macOS reapplies its own LEHID profile across sleep, so the request has to go
            // out again at once. Without clearing the throttle the keyboard would sit on
            // latency 22 for up to 30 seconds after every wake.
            Log.write("el Mac despierta, reaplicando latencia")
            self?.engine.invalidateRequests()
            self?.tick()
        })

        engine.latencyLevel = settings.latencyLevel
        settingsStamp = Self.settingsModified()
        engine.onRSSI = { [weak self] value in self?.monitor.noteRSSI(value) }
        engine.onRadioStateChange = { [weak self] in self?.monitor.noteRadioStateChange() }
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

    /// Whether a live device is one the user asked for.
    ///
    /// An address match is definitive. A name match is a fallback for the one case it exists
    /// to cover — the device came back under a new address — so it only applies when none of
    /// that record's known addresses is currently live. Without that condition a second
    /// keyboard reporting the same name as the first would be adopted silently.
    private func isWanted(_ device: LiveDevice, live: [LiveDevice]) -> Bool {
        guard settings.enabled else { return false }
        if settings.boosts(address: device.address) { return true }
        guard device.hasRealName, let record = settings.record(forName: device.name) else { return false }
        return !record.addresses.contains { alias in
            live.contains { $0.address.caseInsensitiveCompare(alias) == .orderedSame }
        }
    }

    private func tick() {
        reloadSettingsIfFileChanged()
        let live = engine.liveDevices()
        inventory.refreshIfNeeded(addresses: live.map(\.address))
        for device in live { knownNames[device.address.uppercased()] = device.name }

        var devices: [DeviceStatus] = []
        var anyBoosted = false
        var learnedSomething = false

        for device in live {
            let kind = inventory.kind(for: device.address)
            let wanted = isWanted(device, live: live)
            if wanted {
                // Recognising a device by one identifier teaches us the other, so the next
                // power cycle cannot drop it out of the set.
                if settings.learn(address: device.address, name: device.name,
                                  nameIsReal: device.hasRealName) {
                    Log.write("aprendida identidad de \(device.name): \(device.address)")
                    learnedSomething = true
                }
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
                                        kind: kind, present: true, wanted: wanted, boosted: boosted))
        }

        // One write per tick, not one per device: each save costs a file write, a notification,
        // a reload and a recursive tick.
        if learnedSomething {
            settings.save()
            settingsStamp = Self.settingsModified()
        }

        // Configured but not visible: one row per record, so a device with several known
        // addresses cannot render twice.
        for record in settings.boosted {
            let liveHere = live.contains { device in
                record.matches(address: device.address)
                    || (device.hasRealName && record.matches(name: device.name))
            }
            guard !liveHere, let address = record.addresses.first ?? nil else { continue }
            let name = record.name.isEmpty ? (knownNames[address.uppercased()] ?? address) : record.name
            devices.append(DeviceStatus(address: address, name: name,
                                        kind: inventory.kind(for: address),
                                        present: false, wanted: true, boosted: false))
        }
        devices.sort { ($0.present ? 0 : 1, $0.name.lowercased()) < ($1.present ? 0 : 1, $1.name.lowercased()) }

        // Signal strength every 10 s, and a history row every minute. The history is the
        // whole point: an intermittent fault has to leave a trace, or the next time it shows
        // up all anyone can do is blame whatever changed since.
        let now = Date()
        if anyBoosted { if boostedSince == nil { boostedSince = now } } else { boostedSince = nil }

        if now.timeIntervalSince(lastRSSISample) >= 10 {
            lastRSSISample = now
            engine.sampleRSSI()
        }
        if now.timeIntervalSince(lastHistoryWrite) >= 60 {
            lastHistoryWrite = now
            // Only trust the loss figure once the link has been up for longer than the
            // window it is measured over. Otherwise the reconnect itself reads as a fault.
            let settled = boostedSince.map { now.timeIntervalSince($0) >= 70 } ?? false
            monitor.sampleAndRecord(boosted: anyBoosted, measureLoss: settled,
                                    bluetooth: engine.state.rawValue,
                                    deviceName: devices.first(where: \.boosted)?.name ?? "-")
        }

        publish(AgentStatus(bluetooth: engine.state, active: anyBoosted,
                            apiAvailable: engine.apiAvailable, devices: devices,
                            rssi: monitor.current.rssi,
                            lossPercent: monitor.current.lossPercent,
                            radioCyclesLastHour: monitor.current.radioCyclesLastHour,
                            updated: now))
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
