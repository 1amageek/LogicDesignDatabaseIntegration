import CircuiteFoundation

public enum LogicDatabaseSchemaError: Error, Sendable, Hashable {
    case invalidDesign(facet: LogicDatabaseFacet, diagnostics: [DesignDiagnostic])
    case encodingFailed(facet: LogicDatabaseFacet, reason: String)
    case decodingFailed(facet: LogicDatabaseFacet, reason: String)
    case unsupportedDomainSchema(facet: LogicDatabaseFacet, version: Int)
    case nonCanonicalPayload(facet: LogicDatabaseFacet)
    case invalidSourceBinding(reason: String)
    case invalidObjectIdentity(facet: LogicDatabaseFacet, reason: String)
    case invalidProjectionRecord(reason: String)
    case projectionReadBudgetExceeded(limit: UInt64)
    case invalidPageByteCount(Int)
    case pageCountOverflow
}
