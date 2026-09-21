import Foundation

/// Averigua si una dirección es un teclado o un ratón.
///
/// CoreBluetooth no lo dice (`retrievePairingInfoForPeripheral:` devuelve vacío), así que
/// se parsea `system_profiler`. Es lento (~1-2 s), por eso corre fuera del hilo principal
/// y con el resultado cacheado. Que falle no es grave: el dispositivo sigue siendo usable
/// como `.other`.
final class DeviceInventory {
    private var kinds: [String: DeviceKind] = [:]
    private var lastRefresh: Date = .distantPast
    private var refreshing = false
    private let queue = DispatchQueue(label: "keyboost.inventory")
    private let minimumInterval: TimeInterval = 60

    func kind(for address: String) -> DeviceKind {
        queue.sync { kinds[address.uppercased()] ?? .other }
    }

    /// Relanza el parseo si hay direcciones sin clasificar y ha pasado el intervalo mínimo.
    func refreshIfNeeded(addresses: [String]) {
        let unknown = queue.sync {
            addresses.filter { kinds[$0.uppercased()] == nil }
        }
        guard !unknown.isEmpty || Date().timeIntervalSince(lastRefresh) > 600 else { return }
        guard Date().timeIntervalSince(lastRefresh) > minimumInterval else { return }
        queue.sync {
            guard !refreshing else { return }
            refreshing = true
        }
        lastRefresh = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let parsed = Self.parseSystemProfiler()
            self?.queue.sync {
                for (k, v) in parsed { self?.kinds[k] = v }
                self?.refreshing = false
            }
        }
    }

    private static func parseSystemProfiler() -> [String: DeviceKind] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [:] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }

        // Dentro de cada bloque de dispositivo, "Address:" precede a "Minor Type:".
        var result: [String: DeviceKind] = [:]
        var current: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Address:") {
                current = line.dropFirst("Address:".count)
                    .trimmingCharacters(in: .whitespaces).uppercased()
            } else if line.hasPrefix("Minor Type:"), let address = current {
                let value = line.dropFirst("Minor Type:".count).trimmingCharacters(in: .whitespaces).lowercased()
                if value.contains("keyboard") {
                    result[address] = .keyboard
                } else if value.contains("mouse") || value.contains("trackpad") || value.contains("pointing") {
                    result[address] = .pointing
                } else {
                    result[address] = .other
                }
                current = nil
            }
        }
        return result
    }
}
