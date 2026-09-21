import CoreBluetooth
import Foundation

/// Private CoreBluetooth API, central role.
///
/// Verified on macOS 27.2 (26B5086k). All three selectors exist; every call is guarded
/// with `responds(to:)` so the app degrades instead of crashing if Apple removes them.
///
/// - `setDesiredConnectionLatency:forPeripheral:` is what forces `peripheral latency: 0`.
/// - `retrieveConnectedPeripheralsWithServices:allowAll:` with an empty service list and
///   allowAll:YES is the only way to see the system's HID devices: the public filter by
///   0x1812 returns 0, because macOS does not cache their GATT for third-party clients.
/// - `retrieveAddressForPeripheral:` gives the hardware address, which survives re-pairing
///   (the CoreBluetooth UUID does not).
@objc private protocol CBCentralPrivate {
    @objc(setDesiredConnectionLatency:forPeripheral:)
    func setDesiredConnectionLatency(_ latency: Int, forPeripheral peripheral: CBPeripheral)

    @objc(retrieveConnectedPeripheralsWithServices:allowAll:)
    func retrieveConnectedPeripherals(withServices services: [CBUUID], allowAll: Bool) -> [CBPeripheral]

    @objc(retrieveAddressForPeripheral:)
    func retrieveAddress(forPeripheral peripheral: CBPeripheral) -> NSData?
}

// NSSelectorFromString rather than #selector: these selectors are private and appear in
// no public header the compiler could check them against.
private let selSetLatency = NSSelectorFromString("setDesiredConnectionLatency:forPeripheral:")
private let selRetrieveAll = NSSelectorFromString("retrieveConnectedPeripheralsWithServices:allowAll:")
private let selAddress = NSSelectorFromString("retrieveAddressForPeripheral:")

extension CBCentralManager {
    private var priv: CBCentralPrivate { unsafeBitCast(self, to: CBCentralPrivate.self) }

    /// True when this version of macOS still exposes the selector that does the work.
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
