enum LogicDatabasePreparedMutationError: Error, Sendable, Hashable {
    case contentAddressCollision(
        facetID: String,
        documentDigest: String,
        ordinal: UInt64
    )
}
