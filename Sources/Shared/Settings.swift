import Foundation

struct Settings: Codable, Equatable {
    /// Master switch. When off, the engine leaves every link alone.
    var enabled: Bool = true
    /// The menu bar icon belongs to the engine. Off by default, to keep the bar uncluttered.
    var showMenuBarIcon: Bool = false
    /// Seconds of inactivity before releasing the link. 0 means never release.
    var idleReleaseSeconds: Int = 180
    /// Hardware addresses (not UUIDs) of the devices to boost.
    var boostedAddresses: [String] = []
    /// `CBConnectionLatency` level: 0 = low, 1 = medium, 2 = high.
    /// Raising it trades responsiveness for battery. See `latencyChoices`.
    var latencyLevel: Int = 0

    /// Measured on macOS 27.2 with a BLE keyboard: these are the parameters
    /// `bluetoothd` actually negotiates for each level, not estimates.
    struct LatencyChoice {
        let level: Int
        let label: String
        let detail: String
        /// Rough worst case: maximum interval × (1 + peripheralLatency).
        let worstCaseMs: Int
        var isSafe: Bool { level == 0 }
    }

    static var latencyChoices: [LatencyChoice] {
        [
            .init(level: 0, label: L("Fastest"),
                  detail: L("10–30 ms interval, no skipping"), worstCaseMs: 30),
            .init(level: 1, label: L("Balanced"),
                  detail: L("100–120 ms interval, 1 skip"), worstCaseMs: 240),
            .init(level: 2, label: L("Lowest power"),
                  detail: L("290–320 ms interval, 1 skip"), worstCaseMs: 640),
        ]
    }

    static var idleChoices: [(label: String, seconds: Int)] {
        [(L("30 seconds"), 30), (L("1 minute"), 60), (L("3 minutes"), 180),
         (L("10 minutes"), 600), (L("Never release"), 0)]
    }

    static func load() -> Settings {
        JSONStore.read(Settings.self, from: Paths.settings) ?? Settings()
    }

    func save() {
        JSONStore.write(self, to: Paths.settings)
        IPC.post(.settingsChanged)
    }

    func boosts(_ address: String) -> Bool {
        boostedAddresses.contains { $0.caseInsensitiveCompare(address) == .orderedSame }
    }
}
