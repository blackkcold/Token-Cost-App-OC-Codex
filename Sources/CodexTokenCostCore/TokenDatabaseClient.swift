import Foundation
import SQLite3

public enum TokenDatabaseError: LocalizedError {
    case cannotOpenDatabase(String)
    case unsupportedSchema(String)
    case locked(String)
    case queryFailed(String)
    case noData

    public var errorDescription: String? {
        switch self {
        case .cannotOpenDatabase(let message):
            return message
        case .unsupportedSchema(let message):
            return message
        case .locked(let message):
            return message
        case .queryFailed(let message):
            return message
        case .noData:
            return "No token usage data found in the selected database."
        }
    }
}

public final class TokenDatabaseClient {
    private let busyTimeoutMilliseconds: Int32 = 750

    public init() {}

    public func probe(at url: URL) -> TokenCostSourceStatus {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }

        do {
            let db = try openReadOnlyDatabase(url: url)
            defer { sqlite3_close(db) }

            guard try tableExists(named: "message", in: db) else {
                return .unsupported
            }
            guard try messageTableHasRequiredColumns(in: db) else {
                return .unsupported
            }

            _ = try executeSingleString(
                sql: "SELECT json_extract(data, '$.tokens.total') FROM message WHERE data IS NOT NULL LIMIT 1;",
                in: db
            )
            return .available
        } catch TokenDatabaseError.locked {
            return .locked
        } catch {
            return .unsupported
        }
    }

    public func loadPayload(from url: URL) throws -> DashboardPayload {
        let db = try openReadOnlyDatabase(url: url)
        defer { sqlite3_close(db) }

        let rows = try fetchUsageRows(in: db)
        if rows.isEmpty {
            throw TokenDatabaseError.noData
        }
        return Self.buildPayload(from: rows)
    }

    private func openReadOnlyDatabase(url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(url.path, &db, flags, nil)
        guard result == SQLITE_OK, let opened = db else {
            throw TokenDatabaseError.cannotOpenDatabase("Cannot open database at \(url.path)")
        }
        sqlite3_busy_timeout(opened, busyTimeoutMilliseconds)
        sqlite3_extended_result_codes(opened, 1)
        return opened
    }

    private func tableExists(named tableName: String, in db: OpaquePointer) throws -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        return try executeBoolean(sql: sql, in: db, bindText: tableName)
    }

    private func messageTableHasRequiredColumns(in db: OpaquePointer) throws -> Bool {
        let sql = "PRAGMA table_info(message);"
        let columns = try executeStatement(sql: sql, in: db) { statement -> String? in
            columnText(statement, 1)
        }
        let present = Set(columns)
        return present.contains("time_created") && present.contains("data")
    }

    private func fetchUsageRows(in db: OpaquePointer) throws -> [UsageAggregateRow] {
        let sql = buildUsageQuery(includeDate: true, dateFiltered: false, groupBy: "usage_date, model_id, provider_id", orderBy: "usage_date ASC, total_tokens DESC", includeCacheWriteStatus: true)
        return try executeStatement(sql: sql, in: db) { statement -> UsageAggregateRow? in
            guard let date = columnText(statement, 0) else {
                return nil
            }
            let model = columnText(statement, 1) ?? "unknown"
            let provider = columnText(statement, 2) ?? "unknown"
            return UsageAggregateRow(
                date: date,
                model: model,
                provider: provider,
                input: columnDouble(statement, 3),
                output: columnDouble(statement, 4),
                reasoning: columnDouble(statement, 5),
                cacheRead: columnDouble(statement, 6),
                cacheWrite: columnDouble(statement, 7),
                cacheWriteMissingCount: columnInt(statement, 8),
                cacheWriteReportedCount: columnInt(statement, 9),
                total: columnDouble(statement, 10),
                cost: columnDouble(statement, 11),
                msgCount: columnInt(statement, 12)
            )
        }
    }

    private func executeBoolean(sql: String, in db: OpaquePointer, bindText: String? = nil) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            throw databaseError(from: db, message: "Failed to prepare query.")
        }
        defer { sqlite3_finalize(stmt) }
        if let bindText {
            let bindResult = bindText.withCString { pointer -> Int32 in
                sqlite3_bind_text(stmt, 1, pointer, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard bindResult == SQLITE_OK else {
                throw databaseError(from: db, message: "Failed to bind query parameter.")
            }
        }
        let step = sqlite3_step(stmt)
        if step == SQLITE_ROW {
            return true
        }
        if step == SQLITE_BUSY || step == SQLITE_LOCKED {
            throw TokenDatabaseError.locked("The database is busy or locked.")
        }
        if step != SQLITE_DONE {
            throw databaseError(from: db, message: "Query failed while probing the database.")
        }
        return false
    }

    private func executeSingleString(sql: String, in db: OpaquePointer) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            throw databaseError(from: db, message: "Failed to prepare query.")
        }
        defer { sqlite3_finalize(stmt) }
        let step = sqlite3_step(stmt)
        if step == SQLITE_ROW {
            return columnText(stmt, 0)
        }
        if step == SQLITE_BUSY || step == SQLITE_LOCKED {
            throw TokenDatabaseError.locked("The database is busy or locked.")
        }
        if step != SQLITE_DONE {
            throw databaseError(from: db, message: "Query failed while probing the database.")
        }
        return nil
    }

    private func executeStatement<T>(sql: String, in db: OpaquePointer, map: (OpaquePointer) -> T?) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            throw databaseError(from: db, message: "Failed to prepare query.")
        }
        defer { sqlite3_finalize(stmt) }

        var results: [T] = []
        while true {
            let step = sqlite3_step(stmt)
            switch step {
            case SQLITE_ROW:
                if let value = map(stmt) {
                    results.append(value)
                }
            case SQLITE_DONE:
                return results
            case SQLITE_BUSY, SQLITE_LOCKED:
                throw TokenDatabaseError.locked("The database is busy or locked.")
            default:
                throw databaseError(from: db, message: "Database query failed.")
            }
        }
    }

    private func databaseError(from db: OpaquePointer, message: String) -> TokenDatabaseError {
        let details = String(cString: sqlite3_errmsg(db))
        return .queryFailed("\(message) \(details)")
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private func columnDouble(_ statement: OpaquePointer, _ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    private func columnInt(_ statement: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    private let allowedSqlIdentifiers: Set<String> = [
        "usage_date", "model_id", "provider_id", "input_tokens", "output_tokens",
        "reasoning_tokens", "cache_read", "cache_write", "total_tokens",
        "cache_write_missing_count", "cache_write_reported_count"
    ]

    private func isValidSqlIdentifierList(_ value: String) -> Bool {
        let entries = value
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !entries.isEmpty else { return false }

        for entry in entries {
            let parts = entry.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let first = parts.first,
                  allowedSqlIdentifiers.contains(first.lowercased()) else {
                return false
            }
            if parts.count > 2 { return false }
            if parts.count == 2 {
                let dir = parts[1].uppercased()
                guard dir == "ASC" || dir == "DESC" else { return false }
            }
        }
        return true
    }

    private func buildUsageQuery(includeDate: Bool, dateFiltered: Bool, groupBy: String, orderBy: String, includeCacheWriteStatus: Bool) -> String {
        let select = buildUsageSelect(includeDate: includeDate, includeCacheWriteStatus: includeCacheWriteStatus)
        guard isValidSqlIdentifierList(groupBy), isValidSqlIdentifierList(orderBy) else {
            assertionFailure("Invalid SQL identifiers — groupBy: \"\(groupBy)\", orderBy: \"\(orderBy)\"")
            return "SELECT \(select) FROM message WHERE \(tokenRowFilter) AND 1=0"
        }
        var query = """
        SELECT
            \(select)
        FROM message
        WHERE \(tokenRowFilter)
        """
        if dateFiltered {
            query += """

            AND datetime(time_created/1000, 'unixepoch', 'localtime') >= ?
            AND datetime(time_created/1000, 'unixepoch', 'localtime') < ?
            """
        }
        query += """

        GROUP BY \(groupBy)
        ORDER BY \(orderBy)
        """
        return query
    }

    private func buildUsageSelect(includeDate: Bool, includeCacheWriteStatus: Bool) -> String {
        var columns: [String] = []
        if includeDate {
            columns.append("date(time_created/1000, 'unixepoch', 'localtime') as usage_date")
        }
        columns.append(contentsOf: [
            "LOWER(TRIM(json_extract(data, '$.modelID'))) as model_id",
            "json_extract(data, '$.providerID') as provider_id",
            "SUM(COALESCE(CAST(json_extract(data, '$.tokens.input') AS INTEGER), 0)) as input_tokens",
            "SUM(COALESCE(CAST(json_extract(data, '$.tokens.output') AS INTEGER), 0)) as output_tokens",
            "SUM(COALESCE(CAST(json_extract(data, '$.tokens.reasoning') AS INTEGER), 0)) as reasoning_tokens",
            "SUM(COALESCE(CAST(json_extract(data, '$.tokens.cache.read') AS INTEGER), 0)) as cache_read",
            "SUM(COALESCE(CAST(json_extract(data, '$.tokens.cache.write') AS INTEGER), 0)) as cache_write"
        ])
        if includeCacheWriteStatus {
            columns.append("SUM(CASE WHEN json_type(data, '$.tokens.cache.write') IS NULL THEN 1 ELSE 0 END) as cache_write_missing_count")
            columns.append("SUM(CASE WHEN json_type(data, '$.tokens.cache.write') IS NOT NULL THEN 1 ELSE 0 END) as cache_write_reported_count")
        }
        columns.append(contentsOf: [
            "SUM(COALESCE(CAST(json_extract(data, '$.tokens.total') AS REAL), COALESCE(CAST(json_extract(data, '$.tokens.input') AS REAL), 0) + COALESCE(CAST(json_extract(data, '$.tokens.output') AS REAL), 0) + COALESCE(CAST(json_extract(data, '$.tokens.reasoning') AS REAL), 0) + COALESCE(CAST(json_extract(data, '$.tokens.cache.read') AS REAL), 0) + COALESCE(CAST(json_extract(data, '$.tokens.cache.write') AS REAL), 0))) as total_tokens",
            "SUM(COALESCE(CAST(json_extract(data, '$.cost') AS REAL), 0)) as cost",
            "COUNT(*) as message_count"
        ])
        return columns.joined(separator: ",\n        ")
    }

    private var tokenRowFilter: String {
        """
        (
            json_extract(data, '$.tokens.input') IS NOT NULL OR
            json_extract(data, '$.tokens.output') IS NOT NULL OR
            json_extract(data, '$.tokens.reasoning') IS NOT NULL OR
            json_extract(data, '$.tokens.cache.read') IS NOT NULL OR
            json_extract(data, '$.tokens.cache.write') IS NOT NULL OR
            json_extract(data, '$.tokens.total') IS NOT NULL
        )
        """
    }

    private static func buildPayload(from rows: [UsageAggregateRow]) -> DashboardPayload {
        var dailyTotals: [String: Double] = [:]
        var modelTotals: [String: Double] = [:]
        var providerCosts: [String: Double] = [:]
        var providerTotals: [String: DashboardPayload.ProviderTotals] = [:]
        var rawRows: [DashboardPayload.RawRow] = []
        var dates: [String] = []

        for row in rows {
            if dailyTotals[row.date] == nil {
                dates.append(row.date)
            }
            dailyTotals[row.date, default: 0] += row.total
            modelTotals[row.model, default: 0] += row.total
            providerCosts[row.provider, default: 0] += row.cost

            if providerTotals[row.provider] == nil {
                providerTotals[row.provider] = DashboardPayload.ProviderTotals(
                    input: 0,
                    output: 0,
                    cacheRead: 0,
                    cacheWrite: 0,
                    cacheWriteMissingCount: 0,
                    cacheWriteReportedCount: 0,
                    total: 0,
                    actualTokens: 0,
                    cost: 0,
                    messages: 0
                )
            }

            providerTotals[row.provider]?.input += row.input
            providerTotals[row.provider]?.output += row.output
            providerTotals[row.provider]?.cacheRead += row.cacheRead
            providerTotals[row.provider]?.cacheWrite += row.cacheWrite
            providerTotals[row.provider]?.cacheWriteMissingCount += row.cacheWriteMissingCount
            providerTotals[row.provider]?.cacheWriteReportedCount += row.cacheWriteReportedCount
            providerTotals[row.provider]?.total += row.total
            providerTotals[row.provider]?.actualTokens += row.input + row.output + row.reasoning
            providerTotals[row.provider]?.cost += row.cost
            providerTotals[row.provider]?.messages += row.msgCount

            rawRows.append(
                DashboardPayload.RawRow(
                    date: row.date,
                    model: row.model,
                    provider: row.provider,
                    input: row.input,
                    output: row.output,
                    reasoning: row.reasoning,
                    cacheRead: row.cacheRead,
                    cacheWrite: row.cacheWrite,
                    cacheWriteMissingCount: row.cacheWriteMissingCount,
                    cacheWriteReportedCount: row.cacheWriteReportedCount,
                    total: row.total,
                    cost: row.cost,
                    msgCount: row.msgCount
                )
            )
        }

        let totalTokens = dailyTotals.values.reduce(0, +)
        let totalCost = providerCosts.values.reduce(0, +)
        let totalMessages = rawRows.reduce(0) { $0 + $1.msgCount }
        let totalActualTokens = providerTotals.values.reduce(0) { $0 + $1.actualTokens }
        let totalCacheReadTokens = providerTotals.values.reduce(0) { $0 + $1.cacheRead }
        let totalCacheWriteTokens = providerTotals.values.reduce(0) { $0 + $1.cacheWrite }
        let totalCacheTokens = totalCacheReadTokens + totalCacheWriteTokens
        let sortedRows = rawRows.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                if lhs.total == rhs.total {
                    if lhs.model == rhs.model {
                        return lhs.provider.localizedCaseInsensitiveCompare(rhs.provider) == .orderedAscending
                    }
                    return lhs.model.localizedCaseInsensitiveCompare(rhs.model) == .orderedDescending
                }
                return lhs.total > rhs.total
            }
            return lhs.date > rhs.date
        }

        let summary = DashboardPayload.Summary(
            totalTokens: totalTokens,
            totalActualTokens: totalActualTokens,
            totalCacheReadTokens: totalCacheReadTokens,
            totalCacheWriteTokens: totalCacheWriteTokens,
            totalCacheTokens: totalCacheTokens,
            totalCost: totalCost,
            totalMessages: totalMessages,
            activeDays: dailyTotals.count,
            dateRange: .init(start: dates.min(), end: dates.max()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        return DashboardPayload(
            summary: summary,
            dailyTotals: dailyTotals,
            modelTotals: modelTotals,
            providerCosts: providerCosts,
            providerTotals: providerTotals,
            rawData: sortedRows
        )
    }
}
