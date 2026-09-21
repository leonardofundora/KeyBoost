import Foundation

enum Paths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyBoost", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static var settings: URL { support.appendingPathComponent("settings.json") }
    static var status:   URL { support.appendingPathComponent("status.json") }
    static var log:      URL { support.appendingPathComponent("keyboost.log") }

    static let launchAgentLabel = "com.keyboost.agent"
    static var launchAgentPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }
}

/// Escritura atomica + lectura tolerante. Un JSON corrupto nunca debe tumbar un proceso.
enum JSONStore {
    static func write<T: Encodable>(_ value: T, to url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(type, from: data)
    }
}

enum Log {
    static func write(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp)  \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: Paths.log) {
            defer { try? h.close() }
            // Recorta si pasa de 1 MB, para que no crezca sin fin.
            if (try? h.seekToEnd()) ?? 0 > 1_000_000 {
                try? Data().write(to: Paths.log, options: .atomic)
                try? data.write(to: Paths.log, options: .atomic)
                return
            }
            h.write(data)
        } else {
            try? data.write(to: Paths.log, options: .atomic)
        }
    }
}
