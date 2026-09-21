import Foundation

/// Arranque automático del motor, vía LaunchAgent.
enum LoginItem {
    /// El motor va anidado en el bundle principal, como cualquier login item de macOS.
    /// Así la app se distribuye como una sola pieza que se arrastra a Aplicaciones.
    static var agentExecutable: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/KeyBoostAgent.app/Contents/MacOS/KeyBoostAgent")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: Paths.launchAgentPlist.path)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let plist = Paths.launchAgentPlist
        let uid = getuid()
        if enabled {
            let contents: [String: Any] = [
                "Label": Paths.launchAgentLabel,
                "ProgramArguments": [agentExecutable.path],
                "RunAtLoad": true,
                "KeepAlive": true,
                "ProcessType": "Interactive",
            ]
            try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            guard let data = try? PropertyListSerialization.data(fromPropertyList: contents,
                                                                 format: .xml, options: 0),
                  (try? data.write(to: plist, options: .atomic)) != nil else { return false }
            launchctl(["bootout", "gui/\(uid)/\(Paths.launchAgentLabel)"])   // por si ya estaba
            return launchctl(["bootstrap", "gui/\(uid)", plist.path])
        } else {
            launchctl(["bootout", "gui/\(uid)/\(Paths.launchAgentLabel)"])
            try? FileManager.default.removeItem(at: plist)
            return true
        }
    }

    /// Arranca el motor ahora mismo si no está corriendo (para no obligar a reiniciar sesión).
    static func startAgentIfNeeded() {
        guard isEnabled else { return }
        launchctl(["kickstart", "gui/\(getuid())/\(Paths.launchAgentLabel)"])
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
