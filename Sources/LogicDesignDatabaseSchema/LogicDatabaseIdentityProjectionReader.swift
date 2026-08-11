import DesignDatabaseCore

public struct LogicDatabaseIdentityProjectionReader: Sendable {
    public typealias Query = @Sendable (DesignQueryRequest) async throws -> DesignQueryPage

    public let maximumRecordCount: UInt64
    public let pageRecordCount: UInt64

    public init() {
        maximumRecordCount = 100_000
        pageRecordCount = 256
    }

    public init(
        maximumRecordCount: UInt64,
        pageRecordCount: UInt64
    ) throws(LogicDatabaseSchemaError) {
        guard maximumRecordCount > 0,
              pageRecordCount > 0,
              pageRecordCount <= maximumRecordCount,
              maximumRecordCount <= UInt64(Int.max),
              pageRecordCount <= UInt64(Int.max) else {
            throw .invalidProjectionRecord(
                reason: "Logic identity projection budgets must be positive, ordered, and representable by the host."
            )
        }
        self.maximumRecordCount = maximumRecordCount
        self.pageRecordCount = pageRecordCount
    }

    public func read(
        facet: LogicDatabaseFacet,
        query: Query
    ) async throws -> [LogicDatabaseProjectionIdentityRecord] {
        let budget = try queryBudget()
        let prefix = try LogicDatabaseProjectionIdentityRecord.keyPrefix(
            for: facet
        )
        var continuation: DesignQueryContinuation?
        var records: [LogicDatabaseProjectionIdentityRecord] = []
        records.reserveCapacity(
            min(Int(maximumRecordCount), Int(pageRecordCount))
        )
        repeat {
            let page: DesignQueryPage
            do {
                page = try await query(
                    DesignQueryRequest(
                        family: .name,
                        keyPrefix: prefix,
                        maximumPageResultCount: pageRecordCount,
                        budget: budget,
                        continuation: continuation
                    )
                )
            } catch DesignDatabaseError.projectionUnavailable(let family)
                where family == .name {
                return []
            }
            for entry in page.rows {
                records.append(
                    try LogicDatabaseProjectionIdentityRecord(
                        nameProjectionEntry: entry
                    )
                )
            }
            switch page.completion {
            case .sourceExhausted:
                continuation = nil
            case .pageLimitReached:
                guard let next = page.continuation else {
                    throw LogicDatabaseSchemaError.invalidProjectionRecord(
                        reason: "A paged logic identity query omitted its continuation."
                    )
                }
                continuation = next
            case .queryBudgetExhausted:
                throw LogicDatabaseSchemaError.projectionReadBudgetExceeded(
                    limit: maximumRecordCount
                )
            }
        } while continuation != nil

        let objectKeys = records.compactMap { record -> LogicDatabaseStableObjectKey? in
            guard case .object(let object) = record else { return nil }
            return object.stableKey
        }
        let relationKeys = records.compactMap { record -> LogicDatabaseStableObjectKey? in
            guard case .relation(let relation) = record else { return nil }
            return relation.stableKey
        }
        guard Set(objectKeys).count == objectKeys.count,
              Set(relationKeys).count == relationKeys.count else {
            throw LogicDatabaseSchemaError.invalidProjectionRecord(
                reason: "The exact base contains duplicate logic identity records."
            )
        }
        return records
    }

    private func queryBudget() throws -> DesignQueryBudget {
        let (byteLimit, byteOverflow) = maximumRecordCount.multipliedReportingOverflow(
            by: 8_192
        )
        let (workLimit, workOverflow) = maximumRecordCount.multipliedReportingOverflow(
            by: 32
        )
        guard !byteOverflow, !workOverflow else {
            throw LogicDatabaseSchemaError.invalidProjectionRecord(
                reason: "The logic identity projection budget overflows UInt64."
            )
        }
        return try DesignQueryBudget(
            maximumResultCount: maximumRecordCount,
            maximumNodeFetchCount: max(maximumRecordCount, 1_024),
            maximumEncodedReadByteCount: byteLimit,
            maximumDecodedByteCount: byteLimit,
            maximumOutputByteCount: byteLimit,
            maximumWorkCount: workLimit
        )
    }
}
