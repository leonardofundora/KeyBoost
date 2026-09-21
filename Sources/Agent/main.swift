import AppKit

/// Motor de KeyBoost. Sin Dock, sin ventanas. Ver el spec en docs/superpowers/specs/.
final class AgentAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AgentController()
    func applicationDidFinishLaunching(_ notification: Notification) { controller.start() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)     // nunca en el Dock
let delegate = AgentAppDelegate()
app.delegate = delegate
app.run()
