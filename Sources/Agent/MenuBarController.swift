import AppKit

/// El icono opcional de la barra. Lo crea el motor, no la interfaz: por eso sigue
/// ahí con la app cerrada, y por eso se puede quitar sin perder la aceleración.
final class MenuBarController {
    private let item: NSStatusItem
    private let onToggleEnabled: () -> Void
    private let onHideIcon: () -> Void

    init(onToggleEnabled: @escaping () -> Void, onHideIcon: @escaping () -> Void) {
        self.onToggleEnabled = onToggleEnabled
        self.onHideIcon = onHideIcon
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "bolt", accessibilityDescription: "KeyBoost")
        item.button?.image?.isTemplate = true
        item.menu = NSMenu()
    }

    deinit { NSStatusBar.system.removeStatusItem(item) }

    func update(status: AgentStatus, settings: Settings) {
        let symbol: String
        if !settings.enabled              { symbol = "bolt.slash" }
        else if status.bluetooth != .on   { symbol = "bolt.slash" }
        else if status.active             { symbol = "bolt.fill" }
        else                              { symbol = "bolt" }
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "KeyBoost")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        let headline: String
        if !settings.enabled                      { headline = L("KeyBoost — disabled") }
        else if let problem = status.bluetooth.problem { headline = problem }
        else if status.active                     { headline = L("KeyBoost — boosting") }
        else                                      { headline = L("KeyBoost — idle") }
        let header = NSMenuItem(title: headline, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let chosen = status.devices.filter { settings.boosts($0.address) }
        if !chosen.isEmpty {
            menu.addItem(.separator())
            for device in chosen {
                let detail = !device.present ? L("away") : (device.boosted ? L("latency 0") : L("idle"))
                let entry = NSMenuItem(title: "\(device.name) — \(detail)", action: nil, keyEquivalent: "")
                entry.isEnabled = false
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        let toggle = NSMenuItem(title: L("Enabled"), action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = settings.enabled ? .on : .off
        menu.addItem(toggle)

        let open = NSMenuItem(title: L("Open KeyBoost…"), action: #selector(openApp), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let hide = NSMenuItem(title: L("Hide this icon"), action: #selector(hideIcon), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)

        item.menu = menu
    }

    @objc private func toggleEnabled() { onToggleEnabled() }
    @objc private func hideIcon() { onHideIcon() }

    @objc private func openApp() {
        // .../KeyBoost.app/Contents/Library/LoginItems/KeyBoostAgent.app -> .../KeyBoost.app
        let app = Bundle.main.bundleURL
            .deletingLastPathComponent()   // LoginItems
            .deletingLastPathComponent()   // Library
            .deletingLastPathComponent()   // Contents
            .deletingLastPathComponent()   // KeyBoost.app
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
