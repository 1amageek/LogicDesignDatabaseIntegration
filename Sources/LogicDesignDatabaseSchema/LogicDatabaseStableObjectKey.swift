public struct LogicDatabaseStableObjectKey:
    Sendable,
    Hashable,
    Codable,
    Comparable
{
    public let components: [String]

    public init(
        components: [String],
        facet: LogicDatabaseFacet
    ) throws(LogicDatabaseSchemaError) {
        guard !components.isEmpty,
              components.allSatisfy(Self.isValidComponent) else {
            throw .invalidObjectIdentity(
                facet: facet,
                reason: "A stable object key requires non-empty components without control characters."
            )
        }
        self.components = components
    }

    public static func < (
        lhs: LogicDatabaseStableObjectKey,
        rhs: LogicDatabaseStableObjectKey
    ) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }

    private static func isValidComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value.first?.isWhitespace != true
            && value.last?.isWhitespace != true
            && !value.unicodeScalars.contains {
                $0.value < 0x20 || (0x7f...0x9f).contains($0.value)
            }
    }
}
