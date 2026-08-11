import CircuiteFoundation
import DesignDatabaseCore
import Foundation

public enum LogicDatabasePlannedEntityIdentity:
    Sendable,
    Hashable,
    Codable
{
    case existing(DesignEntityID)
    case provisional(DesignProvisionalEntityID)
}

public enum LogicDatabasePlannedRelationIdentity:
    Sendable,
    Hashable,
    Codable
{
    case existing(DesignRelationOccurrenceID)
    case provisional(DesignProvisionalRelationOccurrenceID)
}

public struct LogicDatabasePlannedObject:
    Sendable,
    Hashable,
    Codable,
    Comparable
{
    public let descriptor: LogicDatabaseObjectDescriptor
    public let identity: LogicDatabasePlannedEntityIdentity

    public init(
        descriptor: LogicDatabaseObjectDescriptor,
        identity: LogicDatabasePlannedEntityIdentity
    ) {
        self.descriptor = descriptor
        self.identity = identity
    }

    public static func < (
        lhs: LogicDatabasePlannedObject,
        rhs: LogicDatabasePlannedObject
    ) -> Bool {
        lhs.descriptor < rhs.descriptor
    }
}

public struct LogicDatabasePlannedRelation:
    Sendable,
    Hashable,
    Codable,
    Comparable
{
    public let descriptor: LogicDatabaseRelationDescriptor
    public let identity: LogicDatabasePlannedRelationIdentity

    public init(
        descriptor: LogicDatabaseRelationDescriptor,
        identity: LogicDatabasePlannedRelationIdentity
    ) {
        self.descriptor = descriptor
        self.identity = identity
    }

    public static func < (
        lhs: LogicDatabasePlannedRelation,
        rhs: LogicDatabasePlannedRelation
    ) -> Bool {
        lhs.descriptor < rhs.descriptor
    }
}

public struct LogicDatabaseMutationPayload: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let facet: LogicDatabaseFacet
    public let canonicalDocument: [UInt8]
    public let priorIdentities: [LogicDatabaseProjectionIdentityRecord]
    public let objects: [LogicDatabasePlannedObject]
    public let relations: [LogicDatabasePlannedRelation]

    public init(
        facet: LogicDatabaseFacet,
        canonicalDocument: [UInt8],
        priorIdentities: [LogicDatabaseProjectionIdentityRecord],
        objects: [LogicDatabasePlannedObject],
        relations: [LogicDatabasePlannedRelation]
    ) throws(LogicDatabaseSchemaError) {
        guard !canonicalDocument.isEmpty else {
            throw .invalidProjectionRecord(
                reason: "A logic mutation payload requires a canonical document."
            )
        }
        let orderedPrior = priorIdentities.sorted(by: Self.identityPrecedes)
        let orderedObjects = objects.sorted()
        let orderedRelations = relations.sorted()
        guard orderedPrior.allSatisfy({ $0.facet == facet }),
              Set(orderedObjects.map { $0.descriptor.stableKey }).count
                == orderedObjects.count,
              Set(orderedRelations.map { $0.descriptor.stableKey }).count
                == orderedRelations.count else {
            throw .invalidProjectionRecord(
                reason: "A logic mutation payload contains duplicate or cross-facet identity state."
            )
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.facet = facet
        self.canonicalDocument = canonicalDocument
        self.priorIdentities = orderedPrior
        self.objects = orderedObjects
        self.relations = orderedRelations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "The logic mutation payload schema version is unsupported."
            )
        }
        do {
            try self.init(
                facet: container.decode(LogicDatabaseFacet.self, forKey: .facet),
                canonicalDocument: container.decode(
                    [UInt8].self,
                    forKey: .canonicalDocument
                ),
                priorIdentities: container.decode(
                    [LogicDatabaseProjectionIdentityRecord].self,
                    forKey: .priorIdentities
                ),
                objects: container.decode(
                    [LogicDatabasePlannedObject].self,
                    forKey: .objects
                ),
                relations: container.decode(
                    [LogicDatabasePlannedRelation].self,
                    forKey: .relations
                )
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: String(describing: error)
                )
            )
        }
    }

    private static func identityPrecedes(
        _ lhs: LogicDatabaseProjectionIdentityRecord,
        _ rhs: LogicDatabaseProjectionIdentityRecord
    ) -> Bool {
        if lhs.identityOrder != rhs.identityOrder {
            return lhs.identityOrder < rhs.identityOrder
        }
        return lhs.stableKey < rhs.stableKey
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case facet
        case canonicalDocument
        case priorIdentities
        case objects
        case relations
    }
}

public enum LogicDatabaseMutationPayloadCodec {
    public static func encode(
        _ payload: LogicDatabaseMutationPayload
    ) throws(LogicDatabaseSchemaError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(payload)
        } catch {
            throw .encodingFailed(
                facet: payload.facet,
                reason: String(describing: error)
            )
        }
    }

    public static func decode(
        _ data: Data,
        requireCanonicalEncoding: Bool = true
    ) throws(LogicDatabaseSchemaError) -> LogicDatabaseMutationPayload {
        let payload: LogicDatabaseMutationPayload
        do {
            payload = try JSONDecoder().decode(
                LogicDatabaseMutationPayload.self,
                from: data
            )
        } catch {
            throw .invalidProjectionRecord(reason: String(describing: error))
        }
        if requireCanonicalEncoding {
            let canonical = try encode(payload)
            guard canonical == data else {
                throw .nonCanonicalPayload(facet: payload.facet)
            }
        }
        return payload
    }
}

private extension LogicDatabaseProjectionIdentityRecord {
    var identityOrder: UInt8 {
        switch self {
        case .object:
            1
        case .relation:
            2
        }
    }
}
