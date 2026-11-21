import XCTest

final class SharingBackupTests: XCTestCase {
    func testCodeRoundTripAllPrefixesAndInsertedWhitespace() throws {
        var p = Demo.incoming()
        for kind in [ShareKind.friend, .partner] {
            p.kind = kind
            for language in ["zh-Hans", "zh-Hant", "en"] {
                let code = try ShareCode.encode(p, language: language)
                XCTAssertEqual(try ShareCode.decode("Forwarded:\n" + code + "\n复制整段"), p)
                XCTAssertEqual(try ShareCode.decode(code.map { String($0) }.joined(separator: " \n")), p)
                let prefix = ShareCode.prefix(kind: kind, language: language)
                let token = code.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                let wrapped = token.enumerated().map { $0.offset % 11 == 0 ? " \r\n" + String($0.element) : String($0.element) }.joined()
                XCTAssertEqual(try ShareCode.decode(prefix + wrapped), p)
            }
        }
    }
    func testCodeCannotContainHealthHistoryAndRejectsCorruption() throws {
        let p = Demo.incoming()
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        XCTAssertEqual(Set(json.keys), Set(["v", "k", "n", "g", "p", "t", "s", "r"]))
        for forbidden in ["logs", "symptoms", "bbt", "fertile", "ovulation", "sex", "history"] { XCTAssertNil(json[forbidden]) }
        XCTAssertNil(p.predictions.first?.duration)
        XCTAssertThrowsError(try ShareCode.decode("nonsense"))
        XCTAssertThrowsError(try ShareCode.decode(ShareCode.prefix(kind: .friend) + " ABCdef."))
        var bad = p; bad.v = 99; XCTAssertThrowsError(try ShareCode.encode(bad))
        bad = p; bad.predictions[0].rangeEnd = bad.predictions[0].rangeStart.adding(-1); XCTAssertThrowsError(try ShareCode.encode(bad))
    }
    func testOwnCodeSourceReplacementAndStaleDates() throws {
        var data = AppData(); var p = Demo.incoming(); data.settings.sourceID = p.sourceID
        XCTAssertThrowsError(try ShareCode.importCode(p, into: &data))
        data.settings.sourceID = UUID()
        let id = try ShareCode.importCode(p, into: &data)
        data.friends[0].remindDaysBefore = 2
        p.nickname = "Updated"; XCTAssertEqual(try ShareCode.importCode(p, into: &data), id)
        XCTAssertEqual(data.friends.count, 1); XCTAssertEqual(data.friends[0].nickname, "Updated"); XCTAssertEqual(data.friends[0].remindDaysBefore, 2)
        let friend = data.friends[0]
        XCTAssertFalse(friend.isStale(on: p.generated))
        XCTAssertTrue(friend.isStale(on: p.predictions.last!.rangeEnd.adding(1)))
        XCTAssertEqual(friend.next(on: p.predictions[0].rangeEnd.adding(1)), p.predictions[1])
    }
    func testZlibChecksumAndDecompressionLimits() throws {
        let original = Data("中文 abc def 123".utf8)
        var packed = try XCTUnwrap(Zlib.pack(original))
        XCTAssertEqual(Zlib.unpack(packed), original)
        packed[packed.count - 1] ^= 1; XCTAssertNil(Zlib.unpack(packed))
        XCTAssertNil(Zlib.unpack(Data([0x78])))
    }
    func testEncryptedBackupRoundTripAndWrongPassword() throws {
        var d = Demo.data(); d.settings.nickname = "Private"
        let bytes = try Backup.export(d, password: "secret中文!123")
        XCTAssertFalse(String(data: bytes, encoding: .utf8)!.contains("Private"))
        XCTAssertEqual(try Backup.preview(bytes, password: "secret中文!123").data, d)
        XCTAssertThrowsError(try Backup.preview(bytes, password: "wrong"))
        XCTAssertThrowsError(try Backup.preview(bytes))
        XCTAssertNotEqual(bytes, try Backup.export(d, password: "secret中文!123"))
    }
    func testPlainBackupPreviewAndMergeDoesNotImportEntitlements() throws {
        let incoming = Demo.data(); let preview = try Backup.preview(Backup.export(incoming))
        XCTAssertEqual(preview.count, incoming.logs.count); XCTAssertNotNil(preview.start); XCTAssertNotNil(preview.end)
        var local = AppData(); let identity = local.settings.sourceID
        var log = DayLog(day: incoming.logs[0].day); log.note = "old"; local.upsert(log)
        local.mergeBackup(preview.data)
        XCTAssertEqual(local.logs.first, incoming.logs.first)
        XCTAssertFalse(local.entitlement.purchasedPro); XCTAssertEqual(local.settings.sourceID, identity)
        XCTAssertFalse(local.reminders.pill)
        var empty = AppData(); empty.mergeBackup(incoming)
        XCTAssertTrue(empty.reminders.pill); XCTAssertEqual(empty.settings.purpose, incoming.settings.purpose)
        XCTAssertFalse(empty.entitlement.purchasedPro); XCTAssertFalse(empty.settings.healthEnabled)
    }
    func testCSVIncludesBOMOneDayPerRowAndEscapes() throws {
        var d = AppData(); var l = DayLog(day: Day(2026, 11, 15)); l.note = "=formula,\"quoted\"\r\nnext"; d.upsert(l)
        let csv = Backup.csv(d)
        XCTAssertEqual(Array(csv.prefix(3)), [0xef, 0xbb, 0xbf])
        let text = String(data: csv.dropFirst(3), encoding: .utf8)!
        XCTAssertTrue(text.contains("\"'=formula,\"\"quoted\"\"\r\nnext\"")); XCTAssertTrue(text.contains("2026-11-15"))
    }
    func randomNote(seed: inout UInt64, count: Int) -> String {
        var bytes: [UInt8] = []
        for _ in 0..<count { seed = seed &* 6364136223846793005 &+ 1; bytes.append(UInt8(33 + ((seed >> 32) % 90))) }
        return String(bytes: bytes, encoding: .utf8)!
    }
    func testCloudSnapshotChunkingAndFiveYearTrim() throws {
        var d = AppData(); var seed: UInt64 = 23
        for i in 0..<400 { var l = DayLog(day: Day(2000, 1, 1).adding(i)); l.note = randomNote(seed: &seed, count: 4000); d.logs.append(l) }
        let snapshot = try CloudBackup.makeSnapshot(d, today: Day(2026, 11, 15))
        XCTAssertTrue(snapshot.manifest.trimmed); XCTAssertTrue(snapshot.chunks.allSatisfy { $0.count < 900000 })
        XCTAssertTrue(try CloudBackup.decode(snapshot).logs.isEmpty); XCTAssertEqual(d.logs.count, 400)
        d.logs = Array(d.logs.prefix(275))
        let chunked = try CloudBackup.makeSnapshot(d, today: Day(2000, 12, 31))
        XCTAssertFalse(chunked.manifest.trimmed); XCTAssertEqual(chunked.chunks.count, 2)
        XCTAssertEqual(try CloudBackup.decode(chunked).logs.count, 275)
        var broken = chunked; broken.chunks[0][0] ^= 1; XCTAssertThrowsError(try CloudBackup.decode(broken))
        XCTAssertThrowsError(try CloudBackup.makeSnapshot({ var recent = d; recent.logs = Array(repeating: d.logs, count: 2).flatMap { $0 }; return recent }(), today: Day(2000, 12, 31)))
    }
}
