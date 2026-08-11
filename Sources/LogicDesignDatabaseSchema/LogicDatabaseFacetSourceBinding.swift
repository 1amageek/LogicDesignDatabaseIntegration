import CircuiteFoundation

public struct LogicDatabaseFacetSourceBinding: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let sourceRevision: DesignRevisionReference
    public let sourceFacet: LogicDatabaseFacet
    public let sourceRootDigest: ContentDigest

    public init(
        sourceRevision: DesignRevisionReference,
        sourceFacet: LogicDatabaseFacet,
        sourceRootDigest: ContentDigest
    ) throws(LogicDatabaseSchemaError) {
        guard sourceFacet == .rtl else {
            throw .invalidSourceBinding(
                reason: "Logic derived facets must bind the canonical RTL facet."
            )
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.sourceRevision = sourceRevision
        self.sourceFacet = sourceFacet
        self.sourceRootDigest = sourceRootDigest
    }

    public func validate() throws(LogicDatabaseSchemaError) {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw .invalidSourceBinding(
                reason: "Unsupported logic source-binding schema version \(schemaVersion)."
            )
        }
        guard sourceFacet == .rtl else {
            throw .invalidSourceBinding(
                reason: "Logic derived facets must bind the canonical RTL facet."
            )
        }
    }
}
