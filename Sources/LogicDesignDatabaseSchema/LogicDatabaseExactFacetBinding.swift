import CircuiteFoundation

public struct LogicDatabaseExactFacetBinding: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let sourceRevision: DesignRevisionReference
    public let sourceFacet: LogicDatabaseFacet
    public let sourceRootDigest: ContentDigest

    public init(
        sourceRevision: DesignRevisionReference,
        sourceFacet: LogicDatabaseFacet,
        sourceRootDigest: ContentDigest
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.sourceRevision = sourceRevision
        self.sourceFacet = sourceFacet
        self.sourceRootDigest = sourceRootDigest
    }

    public func validate() throws(LogicDatabaseSchemaError) {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw .invalidSourceBinding(
                reason: "Unsupported exact logic facet-binding schema version \(schemaVersion)."
            )
        }
    }
}
