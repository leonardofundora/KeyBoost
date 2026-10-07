import Foundation

/// Starting the engine automatically, via a LaunchAgent.
enum LoginItem {
    /// The engine is nested inside the main bundle, like any macOS login item, so the app
    /// ships as a single thing you drag to Applications.
    static var agentExecutable: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/KeyBoostAgent.app/Contents/MacOS/KeyBoostAgent")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: Paths.launchAgentPlist.path)
    }

    static func setEnabled(_ enabled: Bool) -> String? {
        if enabled { return install(using: Paths.launchAgentPlist) }
        _ = launchctl(["bootout", serviceTarget])
        if FileManager.default.fileExists(atPath: Paths.launchAgentPlist.path),
           (try? FileManager.default.removeItem(at: Paths.launchAgentPlist)) == nil {
            return failure("Could not remove the LaunchAgent plist.", plist: Paths.launchAgentPlist)
        }
        return install(using: sessionPlist)
    }

    /// Starts the engine for this session. `Start at login` controls only whether the plist lives
    /// in LaunchAgents and is loaded automatically on future logins.
    static func startAgentIfNeeded() -> String? {
        install(using: isEnabled ? Paths.launchAgentPlist : sessionPlist)
    }

    private static var serviceTarget: String {
        "gui/\(getuid())/\(Paths.launchAgentLabel)"
    }
    private static var sessionPlist: URL {
        Paths.support.appendingPathComponent("\(Paths.launchAgentLabel).plist")
    }

    private static func install(using plist: URL) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: agentExecutable.path),
              fm.isExecutableFile(atPath: agentExecutable.path) else {
            return failure("The nested engine executable is missing or is not executable.",
                           plist: plist)
        }

        do {
            try writePlist(to: plist)
        } catch {
            return failure("Could not write the LaunchAgent plist: \(error)",
                           plist: plist)
        }

        let registration = launchctl(["print", serviceTarget])
        let current = registration.succeeded && registration.output.contains(agentExecutable.path)
        if registration.succeeded && !current {
            let bootout = launchctl(["bootout", serviceTarget])
            guard bootout.succeeded else {
                return failure("The stale LaunchAgent registration could not be removed.",
                               plist: plist, command: bootout)
            }
        }

        if !current {
            let bootstrap = launchctl(["bootstrap", "gui/\(getuid())", plist.path])
            guard bootstrap.succeeded else {
                return failure("launchctl could not bootstrap the engine.",
                               plist: plist, command: bootstrap)
            }
        }

        let kickstart = launchctl(["kickstart", serviceTarget])
        guard kickstart.succeeded else {
            return failure("launchctl could not start the engine.",
                           plist: plist, command: kickstart)
        }

        var observation = registration
        for _ in 0..<20 {
            observation = launchctl(["print", serviceTarget])
            if observation.succeeded && observation.output.contains("state = running") { return nil }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return failure("The engine did not become observable as running.",
                       plist: plist, command: observation)
    }

    private static func writePlist(to plist: URL) throws {
        let contents: [String: Any] = [
            "Label": Paths.launchAgentLabel,
            "ProgramArguments": [agentExecutable.path],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
        ]
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: contents,
                                                      format: .xml, options: 0)
        try data.write(to: plist, options: .atomic)
    }

    private static func failure(_ reason: String, plist: URL,
                                command: CommandResult? = nil) -> String {
        let fm = FileManager.default
        let diagnostic = """
        KeyBoost engine startup failed: \(reason)
        service: \(serviceTarget)
        plist: \(plist.path)
        executable: \(agentExecutable.path)
        executable exists: \(fm.fileExists(atPath: agentExecutable.path))
        executable is executable: \(fm.isExecutableFile(atPath: agentExecutable.path))
        launchctl status: \(command.map { String($0.status) } ?? "not run")
        launchctl output: \(command?.output ?? "none")
        """
        NSLog("%@", diagnostic)
        return diagnostic
    }

    private struct CommandResult {
        let status: Int32
        let output: String
        var succeeded: Bool { status == 0 }
    }

    private static func launchctl(_ arguments: [String]) -> CommandResult {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            return CommandResult(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return CommandResult(status: task.terminationStatus,
                             output: String(decoding: data, as: UTF8.self))
    }
}
