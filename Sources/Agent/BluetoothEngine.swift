import CoreBluetooth
import Foundation

/// A device visible right now.
struct LiveDevice {
    let peripheral: CBPeripheral
    let address: String
    let name: String
}

/// Owns the `CBCentralManager`. Discovers devices and holds or releases the link.
///
/// Holding the connection is what sustains `peripheral latency: 0`; the moment it is
/// released, `bluetoothd` reverts to its `LEHID-15ms` profile with latency 22.
final class BluetoothEngine: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    /// Addresses we want kept boosted, and their peripherals.
    private var held: [String: CBPeripheral] = [:]
    /// When low latency was last requested, so it is not repeated every tick.
    private var lastRequest: [String: Date] = [:]
    private let requestInterval: TimeInterval = 30

    private(set) var state: BluetoothState = .unknown
    var onStateChange: (() -> Void)?
    /// The `CBConnectionLatency` level to request. Set by the controller from settings.
    var latencyLevel: Int = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var apiAvailable: Bool { central?.kbSupportsLowLatency ?? false }

    func liveDevices() -> [LiveDevice] {
        guard state == .on else { return [] }
        return central.kbConnectedPeripherals().compactMap { p in
            guard let address = central.kbAddress(of: p) else { return nil }
            return LiveDevice(peripheral: p, address: address,
                              name: p.name ?? "Dispositivo \(address.suffix(5))")
        }
    }

    func isBoosted(_ address: String) -> Bool {
        guard let p = held[address] else { return false }
        return p.state == .connected
    }

    /// Idempotent: safe to call on every tick.
    ///
    /// The latency request is only re-sent on (re)connect or every 30 s. Repeating it
    /// each tick worked, but sent bluetoothd one XPC message per second for nothing.
    func boost(_ device: LiveDevice) {
        guard state == .on else { return }
        held[device.address] = device.peripheral
        let connected = device.peripheral.state == .connected
        let due = Date().timeIntervalSince(lastRequest[device.address] ?? .distantPast) >= requestInterval
        if connected && due {
            central.kbRequestLatency(device.peripheral, level: latencyLevel)
            lastRequest[device.address] = Date()
        }
        if !connected && device.peripheral.state != .connecting {
            central.connect(device.peripheral, options: nil)
        }
    }

    func release(_ address: String) {
        lastRequest[address] = nil
        guard let p = held.removeValue(forKey: address) else { return }
        if p.state == .connected || p.state == .connecting {
            central.cancelPeripheralConnection(p)
        }
        Log.write("soltado \(address)")
    }

    /// Forgets the throttle so the next tick re-sends the request.
    /// Used when the level changes in settings; otherwise it could take 30 s to apply.
    func invalidateRequests() { lastRequest.removeAll() }

    func releaseAll() {
        for address in Array(held.keys) { release(address) }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        switch manager.state {
        case .poweredOn:     state = .on
        case .poweredOff:    state = .off
        case .unauthorized:  state = .unauthorized
        case .unsupported:   state = .unsupported
        default:             state = .unknown
        }
        Log.write("bluetooth: \(state.rawValue)")
        // The radio going down drops everything we were holding, and whatever we ask for
        // next has to be sent fresh rather than waiting out the throttle.
        if state != .on {
            held.removeAll()
            lastRequest.removeAll()
        }
        onStateChange?()
    }

    func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
        manager.kbRequestLatency(peripheral, level: latencyLevel)
        if let address = manager.kbAddress(of: peripheral) { lastRequest[address] = Date() }
        Log.write("turbo activo en \(peripheral.name ?? "?")")
        onStateChange?()
    }

    func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onStateChange?()
    }

    func centralManager(_ manager: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Log.write("fallo al conectar \(peripheral.name ?? "?"): \(error?.localizedDescription ?? "sin detalle")")
    }
}
