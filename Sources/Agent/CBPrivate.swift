import CoreBluetooth
import Foundation

/// API privada de CoreBluetooth en rol central.
///
/// Verificado en macOS 27.2 (26B5086k). Los tres selectores existen; cada llamada va
/// protegida por `responds(to:)` para degradar sin fallar si Apple los retira.
///
/// - `setDesiredConnectionLatency:forPeripheral:` es lo que fuerza `peripheral latency: 0`.
/// - `retrieveConnectedPeripheralsWithServices:allowAll:` con servicios vacios y allowAll:YES
///   es la unica forma de ver los HID del sistema: el filtro publico por 0x1812 devuelve 0
///   porque macOS no cachea su GATT para clientes de terceros.
/// - `retrieveAddressForPeripheral:` da la direccion fisica, que es estable frente a
///   re-emparejamientos (el UUID de CoreBluetooth no lo es).
@objc private protocol CBCentralPrivate {
    @objc(setDesiredConnectionLatency:forPeripheral:)
    func setDesiredConnectionLatency(_ latency: Int, forPeripheral peripheral: CBPeripheral)

    @objc(retrieveConnectedPeripheralsWithServices:allowAll:)
    func retrieveConnectedPeripherals(withServices services: [CBUUID], allowAll: Bool) -> [CBPeripheral]

    @objc(retrieveAddressForPeripheral:)
    func retrieveAddress(forPeripheral peripheral: CBPeripheral) -> NSData?
}

private let selSetLatency = Selector(("setDesiredConnectionLatency:forPeripheral:"))
private let selRetrieveAll = Selector(("retrieveConnectedPeripheralsWithServices:allowAll:"))
private let selAddress = Selector(("retrieveAddressForPeripheral:"))

extension CBCentralManager {
    private var priv: CBCentralPrivate { unsafeBitCast(self, to: CBCentralPrivate.self) }

    /// true si esta version de macOS expone el selector que hace el trabajo.
    var kbSupportsLowLatency: Bool { responds(to: selSetLatency) }

    /// `level`: 0 = low (10–30 ms), 1 = medium (100–120 ms), 2 = high (290–320 ms).
    @discardableResult
    func kbRequestLatency(_ peripheral: CBPeripheral, level: Int) -> Bool {
        guard responds(to: selSetLatency) else { return false }
        priv.setDesiredConnectionLatency(max(0, min(2, level)), forPeripheral: peripheral)
        return true
    }

    func kbConnectedPeripherals() -> [CBPeripheral] {
        guard responds(to: selRetrieveAll) else {
            return retrieveConnectedPeripherals(withServices: [CBUUID(string: "1812")])
        }
        return priv.retrieveConnectedPeripherals(withServices: [], allowAll: true)
    }

    /// Physical address, formatted as "AA:BB:CC:11:22:33".
    func kbAddress(of peripheral: CBPeripheral) -> String? {
        guard responds(to: selAddress),
              let data = priv.retrieveAddress(forPeripheral: peripheral) as Data?,
              data.count == 6 else { return nil }
        return data.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
