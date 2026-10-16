import XCTest
import SQLite3
@testable import VoiceType

final class DataTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testDictionaryRoundTripPreservesCommentsAndSeparators() {
        for text in ["# 常用詞\n 王大皓 \n\nVoiceType:Voice Type,Voice Tape\n品牌：品排、平排\n",
                     "# 註解\r\n詞語\r\n正確:誤聽,另一個", "", "# 只有註解"] {
            let document = DictionaryDocument(text: text)
            XCTAssertEqual(document.text, text)
        }
        let document = DictionaryDocument(text: "常用詞\n正確:誤聽,另一個\n正確二：誤聽二、其他")
        XCTAssertEqual(document.lines.filter { $0.kind == .word }.count, 1)
        XCTAssertEqual(document.lines.filter { $0.kind == .mapping }.count, 2)
    }

    func testDictionaryEditsPreserveUnrelatedLines() throws {
        let url = directory.appendingPathComponent("dictionary.txt")
        try "# 保留這行\n原詞\n品牌:品排,平排\n".write(to: url, atomically: true, encoding: .utf8)
        let store = DictionaryStore(url: url)
        store.load()
        let mapping = try XCTUnwrap(store.document.lines.first { $0.kind == .mapping })
        XCTAssertTrue(store.save(id: mapping.id, correct: "品牌", aliases: "品排, 平排、頻排", mapping: true))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# 保留這行\n原詞\n品牌：品排、平排、頻排\n")
        let word = try XCTUnwrap(store.document.lines.first { $0.kind == .word })
        store.delete(word.id)
        XCTAssertTrue(store.save(correct: "新詞", aliases: nil, mapping: false))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# 保留這行\n品牌：品排、平排、頻排\n新詞\n")
    }

    func testDictionaryRejectsExternalChangesAndInvalidInput() throws {
        let url = directory.appendingPathComponent("dictionary.txt")
        let store = DictionaryStore(url: url)
        store.load()
        XCTAssertFalse(store.save(correct: "# 註解", aliases: nil, mapping: false))
        XCTAssertFalse(store.save(correct: "兩\n行", aliases: nil, mapping: false))
        XCTAssertFalse(store.save(correct: "正確", aliases: " , 、 ", mapping: true))
        XCTAssertTrue(store.save(correct: "原詞", aliases: nil, mapping: false))
        try "# 外部修改\n外部詞".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertFalse(store.save(correct: "新詞", aliases: nil, mapping: false))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# 外部修改\n外部詞")
        store.load()
        XCTAssertTrue(store.save(correct: "新詞", aliases: nil, mapping: false))
    }

    func testDictionaryReadFailureCannotOverwriteFile() throws {
        let url = directory.appendingPathComponent("dictionary.txt")
        let invalid = Data([0xff, 0xfe, 0xff])
        try invalid.write(to: url)
        let store = DictionaryStore(url: url)
        store.load()
        XCTAssertFalse(store.loaded)
        XCTAssertFalse(store.save(correct: "新詞", aliases: nil, mapping: false))
        XCTAssertEqual(try Data(contentsOf: url), invalid)
    }

    func testMissingDatabaseIsNotCreated() {
        let url = directory.appendingPathComponent("missing.db")
        XCTAssertThrowsError(try HistoryReader.read(at: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testHistoryReadsDatesJSONAndNullsWithoutChangingDatabase() throws {
        let url = directory.appendingPathComponent("history.db")
        let database = try createDatabase(url)
        defer { sqlite3_close(database) }
        try execute(database, """
            INSERT INTO history VALUES ('a', '2026-10-14T01:02:03Z', 4.2, '原始 A', '原始 B', '你好 世界', 1,
                '{"app":"備忘錄"}', '{"asr_a":0.6,"llm":1.5,"total":2.2}');
            INSERT INTO history VALUES ('b', '2026-10-14T02:03:04.123Z', 1, NULL, NULL, NULL, 0, 'broken', 'broken');
            """)
        let before = try Data(contentsOf: url)
        let entries = try HistoryReader.read(at: url)
        XCTAssertEqual(entries.map(\.id), ["b", "a"])
        XCTAssertNotNil(entries[0].createdAt)
        XCTAssertNotNil(entries[1].createdAt)
        XCTAssertEqual(entries[0].rawA, "")
        XCTAssertEqual(entries[0].app, "未知 App")
        XCTAssertNil(entries[0].total)
        XCTAssertEqual(entries[1].app, "備忘錄")
        XCTAssertEqual(entries[1].total, 2.2)
        XCTAssertTrue(entries[1].usedFallback)
        XCTAssertEqual(entries[1].characterCount, 4)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testHistoryWhileWALWriterHasUncommittedChanges() throws {
        let url = directory.appendingPathComponent("history.db")
        let database = try createDatabase(url)
        defer { sqlite3_close(database) }
        try execute(database, "PRAGMA journal_mode=WAL; BEGIN IMMEDIATE;")
        try execute(database, "INSERT INTO history (id, created_at, final) VALUES ('a', '2026-10-14T00:00:00Z', '尚未提交');")
        XCTAssertTrue(try HistoryReader.read(at: url).isEmpty)
        try execute(database, "COMMIT;")
        XCTAssertEqual(try HistoryReader.read(at: url).first?.final, "尚未提交")
    }

    func testLockedDatabaseReturnsGracefulFailure() throws {
        let url = directory.appendingPathComponent("history.db")
        let database = try createDatabase(url)
        defer { sqlite3_close(database) }
        try execute(database, "BEGIN EXCLUSIVE;")
        XCTAssertThrowsError(try HistoryReader.read(at: url))
        try execute(database, "ROLLBACK;")
        XCTAssertTrue(try HistoryReader.read(at: url).isEmpty)
    }

    private func createDatabase(_ url: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        let connection = try XCTUnwrap(database)
        try execute(connection, "CREATE TABLE history (id TEXT PRIMARY KEY, created_at TEXT, duration REAL, raw_a TEXT, raw_b TEXT, final TEXT, used_fallback INT, context TEXT, timings TEXT);")
        return connection
    }

    private func execute(_ database: OpaquePointer, _ sql: String) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        if result != SQLITE_OK {
            throw NSError(domain: "SQLiteTests", code: Int(result), userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
        }
    }
}
