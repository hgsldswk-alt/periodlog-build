import Foundation
import CryptoKit

enum CloudBackup {
    static let chunkSize = 800000
    static let maxSize = 950000
    static let manifestKey = "periodlog.backup.manifest"
    struct Manifest: Codable { var version = 1; var generation: String; var count: Int; var digest: String; var trimmed: Bool }
    struct Snapshot { var manifest: Manifest; var chunks: [Data] }
    static func makeSnapshot(_ original: AppData, today: Day) throws -> Snapshot {
        var data = original
        data.entitlement.purchasedPro = false
        func packed(_ data: AppData) throws -> Data {
            guard let result = Zlib.pack(try JSONEncoder().encode(data)) else { throw DataError.tooLarge }; return result
        }
        var bytes = try packed(data); var trimmed = false
        if bytes.count > maxSize {
            let cutoff = today.addingYears(-5)
            data.logs.removeAll { $0.day < cutoff }; bytes = try packed(data); trimmed = true
        }
        guard bytes.count <= maxSize else { throw DataError.tooLarge }
        let chunks = stride(from: 0, to: bytes.count, by: chunkSize).map { Data(bytes[$0..<min($0 + chunkSize, bytes.count)]) }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return Snapshot(manifest: Manifest(generation: UUID().uuidString, count: chunks.count, digest: digest, trimmed: trimmed), chunks: chunks)
    }
    static func decode(_ snapshot: Snapshot) throws -> AppData {
        guard snapshot.manifest.version == 1, (1...2).contains(snapshot.manifest.count), snapshot.chunks.count == snapshot.manifest.count,
              snapshot.chunks.allSatisfy({ $0.count <= chunkSize }) else { throw DataError.corrupt }
        let bytes = snapshot.chunks.reduce(Data(), +)
        guard bytes.count <= maxSize,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == snapshot.manifest.digest,
              let json = Zlib.unpack(bytes) else { throw DataError.corrupt }
        return try JSONDecoder().decode(AppData.self, from: json)
    }
    static func write(_ data: AppData, today: Day, store: NSUbiquitousKeyValueStore = .default) throws -> Bool {
        let snapshot = try makeSnapshot(data, today: today)
        clear(store: store)
        for (i, chunk) in snapshot.chunks.enumerated() { store.set(chunk, forKey: "periodlog.backup.chunk.\(i)") }
        store.set(try JSONEncoder().encode(snapshot.manifest), forKey: manifestKey)
        store.synchronize()
        return snapshot.manifest.trimmed
    }
    static func read(store: NSUbiquitousKeyValueStore = .default) throws -> AppData? {
        guard let bytes = store.data(forKey: manifestKey) else { return nil }
        let manifest = try JSONDecoder().decode(Manifest.self, from: bytes)
        guard (1...2).contains(manifest.count) else { throw DataError.corrupt }
        let chunks = (0..<manifest.count).compactMap { store.data(forKey: "periodlog.backup.chunk.\($0)") }
        return try decode(Snapshot(manifest: manifest, chunks: chunks))
    }
    static func clear(store: NSUbiquitousKeyValueStore = .default) {
        store.removeObject(forKey: manifestKey)
        for i in 0..<2 { store.removeObject(forKey: "periodlog.backup.chunk.\(i)") }
        store.synchronize()
    }
}
