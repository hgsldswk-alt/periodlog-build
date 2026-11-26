import Foundation

enum ShareKind: String, Codable { case friend, partner }
struct Friend: Codable, Equatable, Identifiable {
    var id = UUID()
    var sourceID: UUID
    var nickname: String
    var kind: ShareKind
    var generated: Day
    var predictions: [Forecast]
    var partnerTips: Bool
    var remindDaysBefore: Int?
    var importedAt: Date
    init(id: UUID = UUID(), sourceID: UUID, nickname: String, kind: ShareKind, generated: Day, predictions: [Forecast], partnerTips: Bool = false, remindDaysBefore: Int? = nil, importedAt: Date = Date()) {
        self.id = id; self.sourceID = sourceID; self.nickname = nickname; self.kind = kind
        self.generated = generated; self.predictions = predictions; self.partnerTips = partnerTips
        self.remindDaysBefore = remindDaysBefore; self.importedAt = importedAt
    }
    enum CodingKeys: String, CodingKey { case id, sourceID, nickname, kind, generated, predictions, partnerTips, remindDaysBefore, importedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sourceID = try c.decode(UUID.self, forKey: .sourceID)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? L.t("朋友")
        kind = try c.decodeIfPresent(ShareKind.self, forKey: .kind) ?? .friend
        generated = try c.decode(Day.self, forKey: .generated)
        predictions = try c.decodeIfPresent([Forecast].self, forKey: .predictions) ?? []
        partnerTips = try c.decodeIfPresent(Bool.self, forKey: .partnerTips) ?? false
        remindDaysBefore = try c.decodeIfPresent(Int.self, forKey: .remindDaysBefore).map { max(0, min(7, $0)) }
        importedAt = try c.decodeIfPresent(Date.self, forKey: .importedAt) ?? Date()
    }
    func isStale(on today: Day) -> Bool {
        guard let last = predictions.last else { return true }
        return today > last.rangeEnd.adding(last.duration ?? 0)
    }
    func next(on today: Day) -> Forecast? { predictions.first { $0.rangeEnd >= today } }
}
enum ShareCode {
    static let prefixes = ["经期记录·姐妹口令", "經期記錄·姐妹口令", "Period · Friend code", "经期记录·伴侣口令", "經期記錄·伴侶口令", "Period · Partner code"]
    struct Payload: Codable, Equatable {
        var v = 1
        var kind: ShareKind
        var nickname: String?
        var generated: Day
        var predictions: [Forecast]
        var partnerTips: Bool
        var sourceID: UUID
        var wantsReply = true
        enum CodingKeys: String, CodingKey { case v, kind = "k", nickname = "n", generated = "g", predictions = "p", partnerTips = "t", sourceID = "s", wantsReply = "r" }
        init(v: Int = 1, kind: ShareKind, nickname: String?, generated: Day, predictions: [Forecast], partnerTips: Bool, sourceID: UUID, wantsReply: Bool = true) {
            self.v = v; self.kind = kind; self.nickname = nickname; self.generated = generated
            self.predictions = predictions; self.partnerTips = partnerTips; self.sourceID = sourceID; self.wantsReply = wantsReply
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            v = try c.decode(Int.self, forKey: .v); kind = try c.decode(ShareKind.self, forKey: .kind)
            nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
            generated = try c.decode(Day.self, forKey: .generated); predictions = try c.decode([Forecast].self, forKey: .predictions)
            partnerTips = try c.decodeIfPresent(Bool.self, forKey: .partnerTips) ?? false
            sourceID = try c.decode(UUID.self, forKey: .sourceID)
            wantsReply = try c.decodeIfPresent(Bool.self, forKey: .wantsReply) ?? true
        }
    }
    static func prefix(kind: ShareKind, language: String = Locale.preferredLanguages.first ?? "en") -> String {
        let index = language.hasPrefix("zh-Hant") || language.hasPrefix("zh-TW") || language.hasPrefix("zh-HK") ? 1 : language.hasPrefix("zh") ? 0 : 2
        return prefixes[index + (kind == .partner ? 3 : 0)]
    }
    static func encode(_ payload: Payload, language: String = Locale.preferredLanguages.first ?? "en") throws -> String {
        try validate(payload)
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        guard let packed = Zlib.pack(try e.encode(payload)), packed.count < 16000 else { throw DataError.tooLarge }
        let token = packed.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return prefix(kind: payload.kind, language: language) + " " + token + "."
    }
    static func decode(_ text: String) throws -> Payload {
        guard text.utf8.count <= 60000 else { throw DataError.tooLarge }
        let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
        let markers = prefixes.map { $0.components(separatedBy: .whitespacesAndNewlines).joined() }
        guard let found = markers.compactMap({ compact.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else { throw DataError.corrupt }
        let tail = compact[found.upperBound...]
        var token = ""
        let alphabet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-=+/")
        for scalar in tail.unicodeScalars {
            if alphabet.contains(scalar) { token.unicodeScalars.append(scalar) }
            else if CharacterSet.whitespacesAndNewlines.contains(scalar) { continue }
            else { break }
        }
        guard !token.isEmpty, token.count <= 22000 else { throw DataError.corrupt }
        token = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        token += String(repeating: "=", count: (4 - token.count % 4) % 4)
        guard let bytes = Data(base64Encoded: token), let json = Zlib.unpack(bytes), json.count < 30000 else { throw DataError.corrupt }
        let p = try JSONDecoder().decode(Payload.self, from: json); try validate(p)
        return p
    }
    static func validate(_ p: Payload) throws {
        guard p.v == 1 else { throw DataError.unsupportedVersion }
        guard p.predictions.count == 3, (p.nickname?.count ?? 0) <= 40,
              p.predictions.allSatisfy({ $0.rangeStart <= $0.start && $0.start <= $0.rangeEnd && $0.rangeStart.distance(to: $0.rangeEnd) <= 180 && ($0.duration == nil || (1...14).contains($0.duration!)) }) else { throw DataError.corrupt }
        guard p.predictions[0].start < p.predictions[1].start, p.predictions[1].start < p.predictions[2].start else { throw DataError.corrupt }
    }
    @discardableResult static func importCode(_ p: Payload, into data: inout AppData, now: Date = Date()) throws -> UUID {
        try validate(p)
        guard p.sourceID != data.settings.sourceID else { throw DataError.ownCode }
        let i = data.friends.firstIndex { $0.sourceID == p.sourceID }
        let f = Friend(id: i.map { data.friends[$0].id } ?? UUID(), sourceID: p.sourceID, nickname: p.nickname ?? L.t(p.kind == .friend ? "朋友" : "伴侣"), kind: p.kind, generated: p.generated, predictions: p.predictions, partnerTips: p.partnerTips, remindDaysBefore: i.flatMap { data.friends[$0].remindDaysBefore }, importedAt: now)
        if let i = i { data.friends[i] = f } else { data.friends.append(f) }
        return f.id
    }
}
