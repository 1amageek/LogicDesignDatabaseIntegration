import CircuiteFoundation
import LogicDesignDatabaseSchema

public struct LogicDatabaseFacetInvalidation: Sendable, Hashable, Codable {
    public enum Reason: String, Sendable, Hashable, Codable {
        case sourceFacetMissing
        case sourceRootChanged
    }

    public let targetFacet: LogicDatabaseFacet
    public let observedRevision: DesignRevisionReference
    public let sourceBinding: LogicDatabaseFacetSourceBinding
    public let actualSourceRootDigest: ContentDigest?
    public let reason: Reason

    public init(
        targetFacet: LogicDatabaseFacet,
        observedRevision: DesignRevisionReference,
        sourceBinding: LogicDatabaseFacetSourceBinding,
        actualSourceRootDigest: ContentDigest?,
        reason: Reason
    ) {
        self.targetFacet = targetFacet
        self.observedRevision = observedRevision
        self.sourceBinding = sourceBinding
        self.actualSourceRootDigest = actualSourceRootDigest
        self.reason = reason
    }
}
