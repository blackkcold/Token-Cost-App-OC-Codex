import XCTest
import SQLite3
@testable import CodexTokenCostCore

final class TokenDatabaseV2Tests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opencode_v2_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeDatabase(named name: String = "opencode.db", configure: (OpaquePointer) -> Void) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            XCTFail("Cannot open test database")
            throw TokenDatabaseError.cannotOpenDatabase(url.path)
        }
        defer { sqlite3_close(db) }
        configure(db)
        return url
    }

    private func exec(_ sql: String, in db: OpaquePointer) {
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, sqlite3_errmsg(db).map { String(cString: $0) } ?? "")
    }

    private func insert(_ json: String, sessionID: String, messageID: String, time: Int64 = 1_750_000_000_000, type: String = "assistant", in db: OpaquePointer) {
        let escaped = json.replacingOccurrences(of: "'", with: "''")
        if type == "assistant" {
            exec("INSERT INTO session_message (id, session_id, type, time_created, data) VALUES ('\(messageID)', '\(sessionID)', 'assistant', \(time), '\(escaped)');", in: db)
        } else {
            exec("INSERT INTO session_message (id, session_id, type, time_created, data) VALUES ('\(messageID)', '\(sessionID)', '\(type)', \(time), '\(escaped)');", in: db)
        }
    }

    private func v2Message(model: String, provider: String, input: Int, output: Int = 0, cacheRead: Int = 0) -> String {
        #"{"model":{"providerID":"\#(provider)","id":"\#(model)"},"tokens":{"input":\#(input),"output":\#(output),"reasoning":0,"cache":{"read":\#(cacheRead),"write":0}},"cost":0}"#
    }

    func testReadsV2SessionMessageWithNestedModel() throws {
        let url = try makeDatabase { db in
            exec("CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT, type TEXT, time_created INTEGER, data TEXT);", in: db)
            insert(v2Message(model: "deepseek-v4-flash", provider: "ollama-cloud", input: 100, output: 10, cacheRead: 40), sessionID: "ses_v2", messageID: "msg_1", in: db)
        }

        let payload = try TokenDatabaseClient().loadPayload(from: url)
        XCTAssertEqual(payload.rawData.count, 1)
        let row = try XCTUnwrap(payload.rawData.first)
        XCTAssertEqual(row.model, "deepseek-v4-flash")
        XCTAssertEqual(row.provider, "ollama-cloud")
        XCTAssertEqual(row.input, 100)
        XCTAssertEqual(row.output, 10)
        XCTAssertEqual(row.cacheRead, 40)
    }

    func testV2OwnsMigratedSessionsAndLegacyOnlySessionsStillCount() throws {
        let url = try makeDatabase { db in
            exec("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT);", in: db)
            exec("CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT, type TEXT, time_created INTEGER, data TEXT);", in: db)

            // Migrated session exists in both tables. V2 is authoritative even
            // when the legacy copy carries a different value.
            insert(v2Message(model: "deepseek-v4-flash", provider: "ollama-cloud", input: 100), sessionID: "ses_migrated", messageID: "msg_shared", time: 1_750_000_000_000, in: db)
            exec(#"INSERT INTO message (id, session_id, time_created, data) VALUES ('msg_shared', 'ses_migrated', 1750000000000, '{"modelID":"deepseek-v4-flash","providerID":"ollama-cloud","tokens":{"input":999}}');"#, in: db)

            // Session never migrated to V2: legacy rows must be preserved.
            exec(#"INSERT INTO message (id, session_id, time_created, data) VALUES ('msg_legacy', 'ses_legacy', 1750000100000, '{"modelID":"deepseek-v4-pro","providerID":"deepseek","tokens":{"input":50}}');"#, in: db)
        }

        let payload = try TokenDatabaseClient().loadPayload(from: url)
        XCTAssertEqual(payload.rawData.count, 2)
        let migrated = try XCTUnwrap(payload.rawData.first { $0.model == "deepseek-v4-flash" })
        XCTAssertEqual(migrated.input, 100, "legacy row must not be added on top of the V2 row")
        let legacy = try XCTUnwrap(payload.rawData.first { $0.model == "deepseek-v4-pro" })
        XCTAssertEqual(legacy.input, 50)
        XCTAssertEqual(payload.summary.totalTokens, 150)
    }

    func testV2SchemaIsAuthoritativeWhenEmpty() throws {
        let url = try makeDatabase { db in
            exec("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT);", in: db)
            exec("CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT, type TEXT, time_created INTEGER, data TEXT);", in: db)
            exec(#"INSERT INTO message (id, session_id, time_created, data) VALUES ('msg_legacy', 'ses_legacy', 1750000000000, '{"modelID":"deepseek-v4-pro","providerID":"deepseek","tokens":{"input":50}}');"#, in: db)
        }

        XCTAssertThrowsError(try TokenDatabaseClient().loadPayload(from: url)) { error in
            guard case TokenDatabaseError.noData = error else {
                return XCTFail("Expected noData, got \(error)")
            }
        }
    }

    func testCompactionUsageIsCountedOnceAlongsideAssistant() throws {
        let url = try makeDatabase { db in
            exec("CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT, type TEXT, time_created INTEGER, data TEXT);", in: db)
            insert(v2Message(model: "gpt-5.6-sol", provider: "openai", input: 100, output: 10), sessionID: "ses_v2", messageID: "msg_a", time: 1_750_000_000_000, in: db)
            insert(v2Message(model: "gpt-5.6-sol", provider: "openai", input: 60, output: 5), sessionID: "ses_v2", messageID: "msg_c", time: 1_750_000_100_000, type: "compaction", in: db)
        }

        let payload = try TokenDatabaseClient().loadPayload(from: url)
        XCTAssertEqual(payload.rawData.count, 1, "same day/model/provider aggregates together")
        XCTAssertEqual(payload.rawData.first?.input, 160)
        XCTAssertEqual(payload.rawData.first?.output, 15)
        XCTAssertEqual(payload.summary.totalMessages, 2)
    }
}
