import AppKit
import SwiftUI

/// The KeyBoost interface: a Dock icon and one window.
/// Closing the window quits the app and clears it from the Dock. The engine carries on.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let model = Model()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.startAgentIfNeeded()

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "KeyBoost"
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
