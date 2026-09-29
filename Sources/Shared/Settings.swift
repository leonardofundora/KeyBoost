import Foundation

/// A device the user asked to keep boosted, and every address it has been seen under.
///
/// Addresses looked like the stable key: unlike a CoreBluetooth UUID they survive
/// re-pairing. A keyboard tested here alternates between two across power cycles, so the
/// identity is really "this name, under any of these addresses". Keeping the aliases in
/// one record is what makes matching, forgetting and listing agree; two parallel arrays
/// made each of those re-derive the relationship its own way, and disagree.
struct BoostedDevice: Codable, Equatable {
    /// Empty when the device has only ever been seen without advertising a name.
    var name: String
    var addresses: [String]

    func matches(address: String) -> Bool {
        addresses.contains { $0.caseInsensitiveCompare(address) == .orderedSame }
    }

    func matches(name other: String) -> Bool {
        !name.isEmpty && !other.isEmpty && name.caseInsensitiveCompare(other) == .orderedSame
    }
}

struct Settings: Codable, Equatable {
    /// Master switch. When off, the engine leaves every link alone.
    var enabled: Bool = true
    /// The menu bar icon belongs to the engine. Off by default, to keep the bar uncluttered.
    var showMenuBarIcon: Bool = false
    /// Seconds of inactivity before releasing the link. 0 means never release.
    var idleReleaseSeconds: Int = 180
    /// `CBConnectionLatency` level: 0 = low, 1 = medium, 2 = high.
    /// Raising it trades responsiveness for battery. See `latencyChoices`.
    var latencyLevel: Int = 0
    /// The devices to boost.
    var boosted: [BoostedDevice] = []

    init() {}

    // MARK: - Decoding

    private enum CodingKeys: String, CodingKey {
        case enabled, showMenuBarIcon, idleReleaseSeconds, latencyLevel, boosted
        case boostedAddresses, boostedNames   // written by 1.0 and 1.1
    }

    /// Decoded field by field rather than by the synthesized initialiser.
    ///
    /// Swift's synthesized `init(from:)` calls `decode(_:forKey:)` even for properties that
    /// have a default, so a key added in a later version makes every older file throw. With
    /// `JSONStore.read` swallowing the error, that silently replaces the user's entire
    /// configuration with a fresh one — which for this app means the keyboard stops being
    /// boosted and drops back to the 345 ms fault, on upgrade, with no warning.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? false
        idleReleaseSeconds = try c.decodeIfPresent(Int.self, forKey: .idleReleaseSeconds) ?? 180
        latencyLevel = try c.decodeIfPresent(Int.self, forKey: .latencyLevel) ?? 0
        boosted = try c.decodeIfPresent([BoostedDevice].self, forKey: .boosted) ?? []

        guard boosted.isEmpty else { return }
        // Migrate the two flat lists 1.0 and 1.1 wrote. A single name means every address
        // belonged to it, which is the 1.1 shape; otherwise each address stands alone and
        // picks up its name the first time the engine sees it.
        let addresses = try c.decodeIfPresent([String].self, forKey: .boostedAddresses) ?? []
        let names = try c.decodeIfPresent([String].self, forKey: .boostedNames) ?? []
        if names.count == 1, !addresses.isEmpty {
            boosted = [BoostedDevice(name: names[0], addresses: addresses)]
        } else {
            boosted = addresses.map { BoostedDevice(name: "", addresses: [$0]) }
                   + names.filter { name in !boosted.contains { $0.matches(name: name) } }
                          .map { BoostedDevice(name: $0, addresses: []) }
        }
    }

    /// Written explicitly because the legacy keys in `CodingKeys` have no matching property,
    /// which blocks the synthesized encoder. Only the current shape is written out, so a file
    /// migrates itself the first time anything is saved.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try c.encode(idleReleaseSeconds, forKey: .idleReleaseSeconds)
        try c.encode(latencyLevel, forKey: .latencyLevel)
        try c.encode(boosted, forKey: .boosted)
    }

    // MARK: - Membership

    /// Whether this exact address is boosted. Name matching is deliberately not handled
    /// here: deciding that a name belongs to a device needs to know which devices are
    /// live, so the engine resolves it (see `AgentController.resolve`).
    func boosts(address: String) -> Bool {
        boosted.contains { $0.matches(address: address) }
    }

    func record(forName name: String) -> BoostedDevice? {
        boosted.first { $0.matches(name: name) }
    }

    /// Adds an address, or a name, to the record it belongs to. Returns true if anything changed.
    @discardableResult
    mutating func learn(address: String, name: String, nameIsReal: Bool) -> Bool {
        guard let index = boosted.firstIndex(where: { $0.matches(address: address) })
                       ?? (nameIsReal ? boosted.firstIndex(where: { $0.matches(name: name) }) : nil)
        else { return false }

        var changed = false
        if !boosted[index].matches(address: address) {
            boosted[index].addresses.append(address); changed = true
        }
        // Never store the placeholder the engine invents for a nameless device: it is derived
        // from the address, so it would change along with it and match nothing.
        if nameIsReal, boosted[index].name.isEmpty {
            boosted[index].name = name; changed = true
        }
        return changed
    }

    mutating func start(address: String, name: String, nameIsReal: Bool) {
        guard !boosts(address: address) else { return }
        boosted.append(BoostedDevice(name: nameIsReal ? name : "", addresses: [address]))
    }

    /// Removes the whole record, aliases included. Forgetting one address and leaving its
    /// siblings behind would let the device come back boosted on its next power cycle.
    mutating func forget(address: String, name: String) {
        boosted.removeAll { $0.matches(address: address) || $0.matches(name: name) }
    }

    // MARK: - Choices

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
}
