import Database
import DesignDatabaseRuntime
import LogicDesignDatabaseSchema

extension LogicDesignDatabaseRuntimeAdapter:
    DesignDatabaseRuntimePhysicalWriteReclaimer
{
    static let physicalStorageType =
        "LogicDesignDatabaseSchema.LogicDatabaseFacetPage.v1"

    public var storageType: String { Self.physicalStorageType }

    public func deleteImmutableWrite(
        _ identity: DesignDatabaseRuntimeImmutableWriteIdentity,
        from transaction: any DatabaseTransactionWriting
    ) async throws(DesignDatabaseRuntimePhysicalWriteReclaimerError) {
        let components = try DesignDatabaseRuntimePhysicalWriteDeletion
            .requirePartitionComponents(identity, storageType: storageType, count: 2)
        var partition = DirectoryPath<LogicDatabaseFacetPage>()
        partition.set(LogicDatabaseFacetPage.fields.facetID, to: components[0])
        partition.set(LogicDatabaseFacetPage.fields.documentDigest, to: components[1])
        try await DesignDatabaseRuntimePhysicalWriteDeletion.delete(
            identity,
            model: LogicDatabaseFacetPage.self,
            identifiedBy: identity.modelID,
            in: partition,
            expectedIdentity: Self.physicalWriteIdentity,
            from: transaction
        )
    }

    static func physicalWriteIdentity(
        _ page: LogicDatabaseFacetPage
    ) throws(DesignDatabaseRuntimePreparedMutationError)
        -> DesignDatabaseRuntimeImmutableWriteIdentity {
        try DesignDatabaseRuntimeImmutableWriteIdentity(
            storageType: physicalStorageType,
            partitionComponents: [page.facetID, page.documentDigest],
            modelID: page.id
        )
    }
}
