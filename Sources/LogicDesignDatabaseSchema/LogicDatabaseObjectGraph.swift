import CircuiteFoundation
import DesignDatabaseCore

public struct LogicDatabaseObjectDescriptor:
    Sendable,
    Hashable,
    Codable,
    Comparable
{
    public let stableKey: LogicDatabaseStableObjectKey
    public let kindID: DesignEntityKindID
    public let contentDigest: ContentDigest

    public init(
        stableKey: LogicDatabaseStableObjectKey,
        kindID: DesignEntityKindID,
        contentDigest: ContentDigest
    ) {
        self.stableKey = stableKey
        self.kindID = kindID
        self.contentDigest = contentDigest
    }

    public static func < (
        lhs: LogicDatabaseObjectDescriptor,
        rhs: LogicDatabaseObjectDescriptor
    ) -> Bool {
        lhs.stableKey < rhs.stableKey
    }
}

public struct LogicDatabaseRelationDescriptor:
    Sendable,
    Hashable,
    Codable,
    Comparable
{
    public let stableKey: LogicDatabaseStableObjectKey
    public let family: DesignProjectionFamily
    public let ownerKey: LogicDatabaseStableObjectKey
    public let relationKindID: DesignRelationKindID
    public let targetKey: LogicDatabaseStableObjectKey
    public let orderKey: DesignCanonicalKey
    public let attributesDigest: ContentDigest?

    public init(
        stableKey: LogicDatabaseStableObjectKey,
        family: DesignProjectionFamily,
        ownerKey: LogicDatabaseStableObjectKey,
        relationKindID: DesignRelationKindID,
        targetKey: LogicDatabaseStableObjectKey,
        orderKey: DesignCanonicalKey,
        attributesDigest: ContentDigest?
    ) {
        self.stableKey = stableKey
        self.family = family
        self.ownerKey = ownerKey
        self.relationKindID = relationKindID
        self.targetKey = targetKey
        self.orderKey = orderKey
        self.attributesDigest = attributesDigest
    }

    public static func < (
        lhs: LogicDatabaseRelationDescriptor,
        rhs: LogicDatabaseRelationDescriptor
    ) -> Bool {
        lhs.stableKey < rhs.stableKey
    }
}

public struct LogicDatabaseObjectGraph: Sendable, Hashable, Codable {
    public let facet: LogicDatabaseFacet
    public let objects: [LogicDatabaseObjectDescriptor]
    public let relations: [LogicDatabaseRelationDescriptor]

    public init(
        facet: LogicDatabaseFacet,
        objects: [LogicDatabaseObjectDescriptor],
        relations: [LogicDatabaseRelationDescriptor]
    ) throws(LogicDatabaseSchemaError) {
        let orderedObjects = objects.sorted()
        let orderedRelations = relations.sorted()
        guard Set(orderedObjects.map(\.stableKey)).count == orderedObjects.count else {
            throw .invalidObjectIdentity(
                facet: facet,
                reason: "The canonical logic graph contains duplicate stable object keys."
            )
        }
        guard Set(orderedRelations.map(\.stableKey)).count == orderedRelations.count else {
            throw .invalidObjectIdentity(
                facet: facet,
                reason: "The canonical logic graph contains duplicate stable relation keys."
            )
        }
        let objectKeys = Set(orderedObjects.map(\.stableKey))
        guard orderedRelations.allSatisfy({
            objectKeys.contains($0.ownerKey) && objectKeys.contains($0.targetKey)
        }) else {
            throw .invalidObjectIdentity(
                facet: facet,
                reason: "A canonical logic relation references an object outside its facet graph."
            )
        }
        self.facet = facet
        self.objects = orderedObjects
        self.relations = orderedRelations
    }
}
