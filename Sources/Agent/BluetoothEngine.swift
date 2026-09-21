import CoreBluetooth
import Foundation

/// Un dispositivo visible ahora mismo.
struct LiveDevice {
    let peripheral: CBPeripheral
    let address: String
    let name: String
}

/// Dueño del `CBCentralManager`. Descubre dispositivos y mantiene o suelta el enlace.
///
/// Mantener la conexión es lo que sostiene `peripheral latency: 0`; en cuanto se suelta,
/// `bluetoothd` vuelve a su perfil `LEHID-15ms` con latency 22.
final class BluetoothEngine: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    /// Direcciones que queremos mantener aceleradas, y su periférico.
    private var held: [String: CBPeripheral] = [:]
    /// Cuándo se pidió latencia baja por última vez, para no repetirlo cada tick.
    private var lastRequest: [String: Date] = [:]
    private let requestInterval: TimeInterval = 30

    private(set) var state: BluetoothState = .unknown
    var onStateChange: (() -> Void)?
    /// Nivel de `CBConnectionLatency` que se pide. Lo fija el controlador desde los ajustes.
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

    /// Idempotente: se puede llamar en cada tick sin coste.
    ///
    /// La petición de latencia solo se reenvía al (re)conectar o cada 30 s. Repetirla
    /// en cada tick funcionaba, pero mandaba un XPC por segundo a bluetoothd para nada.
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

    /// Olvida el throttle para que el próximo tick reenvíe la petición.
    /// Se usa al cambiar el nivel en los ajustes: si no, tardaría hasta 30 s en aplicarse.
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
        if state != .on { held.removeAll() }
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
