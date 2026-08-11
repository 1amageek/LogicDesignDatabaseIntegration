public struct LogicDatabaseReadBudget: Sendable, Hashable {
    public let maximumPageCount: Int
    public let pageFetchLimit: Int

    public init(
        maximumPageCount: Int = 4_096,
        pageFetchLimit: Int = 64
    ) throws(LogicDatabaseReadError) {
        guard maximumPageCount > 0 else {
            throw .invalidBudget
        }
        guard pageFetchLimit > 0, pageFetchLimit <= maximumPageCount else {
            throw .invalidBudget
        }
        self.maximumPageCount = maximumPageCount
        self.pageFetchLimit = pageFetchLimit
    }

    var runtimeReadCount: UInt64 {
        get throws {
            let (value, overflow) = maximumPageCount.addingReportingOverflow(
                pageFetchLimit
            )
            guard !overflow, let count = UInt64(exactly: value) else {
                throw LogicDatabaseReadError.invalidBudget
            }
            return count
        }
    }
}
