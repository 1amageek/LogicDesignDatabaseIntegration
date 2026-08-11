import CircuiteFoundation
import LogicDesignDatabaseSchema

public enum LogicDatabaseReadError: Error, Sendable, Hashable {
    case unsupportedSnapshotImplementation
    case invalidBudget
    case pageBudgetExceeded(limit: Int)
    case missingFacetPages(LogicDatabaseFacet)
    case inconsistentPageMetadata(LogicDatabaseFacet)
    case nonContiguousPages(LogicDatabaseFacet)
    case byteCountMismatch(expected: UInt64, actual: UInt64)
    case facetRootMismatch(expected: ContentDigest, actual: ContentDigest)
    case decodeFailed(LogicDatabaseSchemaError)
}
