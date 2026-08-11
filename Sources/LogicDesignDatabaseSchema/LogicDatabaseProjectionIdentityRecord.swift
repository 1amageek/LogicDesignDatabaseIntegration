import CircuiteFoundation
import DesignDatabaseCore
import Foundation

public struct LogicDatabaseObjectIdentityRecord:
    Sendable,
    Hashable,
    Codable
{
    public let facet: LogicDatabaseFacet
    public let stableKey: LogicDatabaseStableObjectKey
    public let entityID: DesignEntityID
    public let kindID: DesignEntityKindID
    public let contentDigest: ContentDigest

    public init(
        facet: LogicDatabaseFacet,
        stableKey: LogicDatabaseStableObjectKey,
        entityID: DesignEntityID,
        kindID: DesignEntityKindID,
        contentDigest: ContentDigest
    ) {
        self.facet = facet
        self.stableKey = stableKey
        self.entityID = entityID
        self.kindID = kindID
        self.contentDigest = contentDigest
    }

    public func entityProjectionEntry() throws -> DesignProjectionEntry {
        try DesignEntityProjectionRecord(
            entityID: entityID,
            facetID: facet.designFacetID,
            kindID: kindID,
            contentDigest: contentDigest
        ).projectionEntry()
    }
}

public struct LogicDatabaseRelationIdentityRecord:
    Sendable,
    Hashable,
    Codable
{
    public let facet: LogicDatabaseFacet
    public let stableKey: LogicDatabaseStableObjectKey
    public let occurrenceID: DesignRelationOccurrenceID
    public let ownerEntityID: DesignEntityID
    public let family: DesignProjectionFamily
    public let relationKindID: DesignRelationKindID
    public let targetEntityID: DesignEntityID
    public let orderKey: DesignCanonicalKey
    public let attributesDigest: ContentDigest?

    public init(
        facet: LogicDatabaseFacet,
        stableKey: LogicDatabaseStableObjectKey,
        occurrenceID: DesignRelationOccurrenceID,
        ownerEntityID: DesignEntityID,
        family: DesignProjectionFamily,
        relationKindID: DesignRelationKindID,
        targetEntityID: DesignEntityID,
        orderKey: DesignCanonicalKey,
        attributesDigest: ContentDigest?
    ) {
        self.facet = facet
        self.stableKey = stableKey
        self.occurrenceID = occurrenceID
        self.ownerEntityID = ownerEntityID
        self.family = family
        self.relationKindID = relationKindID
        self.targetEntityID = targetEntityID
        self.orderKey = orderKey
        self.attributesDigest = attributesDigest
    }

    public func relationProjectionEntries() throws -> [DesignProjectionEntry] {
        try DesignRelationOccurrenceRecord(
            projectionFamily: family,
            occurrenceID: occurrenceID,
            ownerEntityID: ownerEntityID,
            relationKindID: relationKindID,
            target: .local(targetEntityID),
            orderKey: orderKey,
            attributesDigest: attributesDigest
        ).projectionEntries()
    }
}

public enum LogicDatabaseProjectionIdentityRecord:
    Sendable,
    Hashable,
    Codable
{
    case object(LogicDatabaseObjectIdentityRecord)
    case relation(LogicDatabaseRelationIdentityRecord)

    public var facet: LogicDatabaseFacet {
        switch self {
        case .object(let record):
            record.facet
        case .relation(let record):
            record.facet
        }
    }

    public var stableKey: LogicDatabaseStableObjectKey {
        switch self {
        case .object(let record):
            record.stableKey
        case .relation(let record):
            record.stableKey
        }
    }

    public func nameProjectionEntry() throws -> DesignProjectionEntry {
        let key = try LogicDatabaseProjectionIdentityKeyCodec.key(
            facet: facet,
            recordTag: recordTag,
            stableKey: stableKey
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try DesignProjectionEntry(
                key: key,
                value: Array(try encoder.encode(self))
            )
        } catch {
            throw LogicDatabaseSchemaError.invalidProjectionRecord(
                reason: String(describing: error)
            )
        }
    }

    public init(
        nameProjectionEntry entry: DesignProjectionEntry
    ) throws(LogicDatabaseSchemaError) {
        let decodedKey = try LogicDatabaseProjectionIdentityKeyCodec.decode(
            entry.key
        )
        let decoded: LogicDatabaseProjectionIdentityRecord
        do {
            decoded = try JSONDecoder().decode(
                LogicDatabaseProjectionIdentityRecord.self,
                from: Data(entry.value)
            )
        } catch {
            throw .invalidProjectionRecord(reason: String(describing: error))
        }
        guard decoded.facet == decodedKey.facet,
              decoded.stableKey == decodedKey.stableKey,
              decoded.recordTag == decodedKey.recordTag else {
            throw .invalidProjectionRecord(
                reason: "A logic identity projection key does not match its value."
            )
        }
        self = decoded
    }

    public static func keyPrefix(
        for facet: LogicDatabaseFacet
    ) throws(LogicDatabaseSchemaError) -> DesignCanonicalKey {
        try LogicDatabaseProjectionIdentityKeyCodec.prefix(facet: facet)
    }

    private var recordTag: UInt8 {
        switch self {
        case .object:
            1
        case .relation:
            2
        }
    }
}

private enum LogicDatabaseProjectionIdentityKeyCodec {
    struct DecodedKey {
        let facet: LogicDatabaseFacet
        let recordTag: UInt8
        let stableKey: LogicDatabaseStableObjectKey
    }

    static func prefix(
        facet: LogicDatabaseFacet
    ) throws(LogicDatabaseSchemaError) -> DesignCanonicalKey {
        var bytes = namespace
        do {
            try append(facet.rawValue, to: &bytes)
            return try DesignCanonicalKey(bytes: bytes)
        } catch let error as LogicDatabaseSchemaError {
            throw error
        } catch {
            throw .invalidProjectionRecord(reason: String(describing: error))
        }
    }

    static func key(
        facet: LogicDatabaseFacet,
        recordTag: UInt8,
        stableKey: LogicDatabaseStableObjectKey
    ) throws(LogicDatabaseSchemaError) -> DesignCanonicalKey {
        var bytes = try prefix(facet: facet).bytes
        bytes.append(recordTag)
        guard let componentCount = UInt16(exactly: stableKey.components.count) else {
            throw .invalidProjectionRecord(
                reason: "A stable object key has too many components."
            )
        }
        append(componentCount, to: &bytes)
        for component in stableKey.components {
            try append(component, to: &bytes)
        }
        do {
            return try DesignCanonicalKey(bytes: bytes)
        } catch {
            throw .invalidProjectionRecord(reason: String(describing: error))
        }
    }

    static func decode(
        _ key: DesignCanonicalKey
    ) throws(LogicDatabaseSchemaError) -> DecodedKey {
        var reader = Reader(bytes: key.bytes)
        guard reader.read(count: namespace.count) == namespace else {
            throw .invalidProjectionRecord(
                reason: "A name projection entry is outside the logic identity namespace."
            )
        }
        let facetValue = try reader.readString()
        guard let facet = LogicDatabaseFacet(rawValue: facetValue) else {
            throw .invalidProjectionRecord(reason: "A logic identity facet is unknown.")
        }
        let recordTag = try reader.readUInt8()
        guard recordTag == 1 || recordTag == 2 else {
            throw .invalidProjectionRecord(reason: "A logic identity record tag is unknown.")
        }
        let count = Int(try reader.readUInt16())
        var components: [String] = []
        components.reserveCapacity(count)
        for _ in 0..<count {
            components.append(try reader.readString())
        }
        guard reader.isExhausted else {
            throw .invalidProjectionRecord(
                reason: "A logic identity projection key contains trailing bytes."
            )
        }
        return DecodedKey(
            facet: facet,
            recordTag: recordTag,
            stableKey: try LogicDatabaseStableObjectKey(
                components: components,
                facet: facet
            )
        )
    }

    private static func append(
        _ value: UInt16,
        to bytes: inout [UInt8]
    ) {
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value))
    }

    private static func append(
        _ value: UInt32,
        to bytes: inout [UInt8]
    ) {
        bytes.append(UInt8(truncatingIfNeeded: value >> 24))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value))
    }

    private static func append(
        _ value: String,
        to bytes: inout [UInt8]
    ) throws(LogicDatabaseSchemaError) {
        let encoded = Array(value.utf8)
        guard let count = UInt32(exactly: encoded.count) else {
            throw .invalidProjectionRecord(
                reason: "A logic identity key component exceeds the encoded length limit."
            )
        }
        append(count, to: &bytes)
        bytes.append(contentsOf: encoded)
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0

        var isExhausted: Bool { index == bytes.count }

        mutating func read(count: Int) -> [UInt8]? {
            guard count >= 0, index <= bytes.count - count else { return nil }
            let result = Array(bytes[index..<(index + count)])
            index += count
            return result
        }

        mutating func readUInt8() throws(LogicDatabaseSchemaError) -> UInt8 {
            guard let value = read(count: 1)?.first else {
                throw .invalidProjectionRecord(reason: "A logic identity key is truncated.")
            }
            return value
        }

        mutating func readUInt16() throws(LogicDatabaseSchemaError) -> UInt16 {
            guard let value = read(count: 2) else {
                throw .invalidProjectionRecord(reason: "A logic identity key is truncated.")
            }
            return (UInt16(value[0]) << 8) | UInt16(value[1])
        }

        mutating func readUInt32() throws(LogicDatabaseSchemaError) -> UInt32 {
            guard let value = read(count: 4) else {
                throw .invalidProjectionRecord(reason: "A logic identity key is truncated.")
            }
            return (UInt32(value[0]) << 24)
                | (UInt32(value[1]) << 16)
                | (UInt32(value[2]) << 8)
                | UInt32(value[3])
        }

        mutating func readString() throws(LogicDatabaseSchemaError) -> String {
            let count = try readUInt32()
            guard let integerCount = Int(exactly: count),
                  let value = read(count: integerCount),
                  let result = String(bytes: value, encoding: .utf8) else {
                throw .invalidProjectionRecord(
                    reason: "A logic identity key contains an invalid string."
                )
            }
            return result
        }
    }

    private static let namespace = Array("lsi.logic.identity.v1\0".utf8)
}
