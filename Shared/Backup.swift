import Foundation
import CryptoKit
import CommonCrypto

enum Backup {
    struct Envelope: Codable {
        var version = 1
        var encrypted: Bool
        var salt: Data?
        var rounds: Int?
        var body: Data
    }
    struct Preview {
        var data: AppData
        var count: Int { data.logs.count }
        var start: Day? { data.logs.first?.day }
        var end: Day? { data.logs.last?.day }
    }
    static func readFile(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var bytes = Data()
        while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
            guard bytes.count + chunk.count <= 18000000 else { throw DataError.tooLarge }
            bytes.append(chunk)
        }
        return bytes
    }
    static func key(password: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        guard (100000...1000000).contains(rounds), salt.count == 16 else { throw DataError.corrupt }
        let passwordBytes = Array(password.utf8)
        var output = [UInt8](repeating: 0, count: 32)
        let status: Int32 = passwordBytes.withUnsafeBytes { p in
            salt.withUnsafeBytes { s in
                output.withUnsafeMutableBytes { result in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress!.assumingMemoryBound(to: Int8.self), passwordBytes.count, s.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds), result.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw DataError.corrupt }
        return SymmetricKey(data: output)
    }
    static func export(_ data: AppData, password: String = "") throws -> Data {
        let json = try JSONEncoder().encode(data)
        guard json.count <= Zlib.maxJSONLength else { throw DataError.tooLarge }
        if password.isEmpty { return try JSONEncoder().encode(Envelope(encrypted: false, body: json)) }
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let rounds = 210000
        let box = try AES.GCM.seal(json, using: key(password: password, salt: salt, rounds: rounds))
        guard let bytes = box.combined else { throw DataError.corrupt }
        return try JSONEncoder().encode(Envelope(encrypted: true, salt: salt, rounds: rounds, body: bytes))
    }
    static func preview(_ bytes: Data, password: String = "") throws -> Preview {
        guard bytes.count <= 18000000 else { throw DataError.tooLarge }
        let e = try JSONDecoder().decode(Envelope.self, from: bytes)
        guard e.version == 1 else { throw DataError.unsupportedVersion }
        let json: Data
        if e.encrypted {
            guard !password.isEmpty, let salt = e.salt, let rounds = e.rounds else { throw DataError.wrongPassword }
            let key = try key(password: password, salt: salt, rounds: rounds)
            do { json = try AES.GCM.open(AES.GCM.SealedBox(combined: e.body), using: key) }
            catch { throw DataError.wrongPassword }
        } else { json = e.body }
        guard json.count <= Zlib.maxJSONLength else { throw DataError.tooLarge }
        return Preview(data: try JSONDecoder().decode(AppData.self, from: json))
    }
    static func csv(_ data: AppData) -> Data {
        func field(_ s: String) -> String {
            let guarded = ["=", "+", "-", "@", "\t", "\r"].contains(where: { s.hasPrefix($0) }) ? "'" + s : s
            return "\"" + guarded.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = ["day,flow,symptoms,moods,discharge,bbt_celsius,ovulation_test,pregnancy_test,sex,pill_taken,note"]
        for log in data.logs.sorted(by: { $0.day < $1.day }) {
            var row: [String] = []
            row.append(log.day.description)
            row.append(log.flow?.rawValue ?? "")
            row.append(log.symptoms.sorted().joined(separator: ";"))
            row.append(log.moods.sorted().joined(separator: ";"))
            row.append(log.discharge?.rawValue ?? "")
            var bbtText = ""
            if let bbt = log.bbt { bbtText = String(format: "%.2f", Double(bbt) / 100.0) }
            row.append(bbtText)
            row.append(log.ovulationTest?.rawValue ?? "")
            row.append(log.pregnancyTest?.rawValue ?? "")
            row.append(log.sex?.rawValue ?? "")
            var pillText = ""
            if let pill = log.pillTaken { pillText = pill ? "true" : "false" }
            row.append(pillText)
            row.append(log.note)
            let fields: [String] = row.map { field($0) }
            lines.append(fields.joined(separator: ","))
        }
        return Data([0xef, 0xbb, 0xbf]) + Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }
}
