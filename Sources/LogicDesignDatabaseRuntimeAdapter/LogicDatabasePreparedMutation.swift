import CircuiteFoundation
import Database
import DesignDatabaseCore
import DesignDatabaseRuntime
import LogicDesignDatabaseSchema

struct LogicDatabasePreparedMutation: DesignDatabaseRuntimePreparedMutation {
    let segmentID: DesignMutationPlanSegmentID
    let pages: [LogicDatabaseFacetPage]
    let facetRootDigest: ContentDigest
    let changeContributionDigest: ContentDigest
    let projectionChanges: [DesignProjectionChange]

    var writeCount: UInt64 {
        UInt64(pages.count)
    }

    func immutableWriteIdentity(
        at index: UInt64
    ) throws(DesignDatabaseRuntimePreparedMutationError)
        -> DesignDatabaseRuntimeImmutableWriteIdentity {
        guard let pageIndex = Int(exactly: index),
              pages.indices.contains(pageIndex) else {
            throw .invalidImmutableWriteIndex(index: index, writeCount: writeCount)
        }
        let page = pages[pageIndex]
        return try LogicDesignDatabaseRuntimeAdapter.physicalWriteIdentity(page)
    }

    func stageImmutableWrite(
        at index: UInt64,
        to transaction: any DatabaseTransactionWriting
    ) async throws {
        guard let pageIndex = Int(exactly: index),
              pages.indices.contains(pageIndex) else {
            throw DesignDatabaseRuntimePreparedMutationError
                .invalidImmutableWriteIndex(index: index, writeCount: writeCount)
        }
        let page = pages[pageIndex]
        var partition = DirectoryPath<LogicDatabaseFacetPage>()
        partition.set(
            LogicDatabaseFacetPage.fields.facetID,
            to: page.facetID
        )
        partition.set(
            LogicDatabaseFacetPage.fields.documentDigest,
            to: page.documentDigest
        )
        if let existing = try await transaction.fetch(
            LogicDatabaseFacetPage.self,
            identifiedBy: page.id,
            in: partition
        ) {
            guard Self.matches(existing, page) else {
                throw LogicDatabasePreparedMutationError.contentAddressCollision(
                    facetID: page.facetID,
                    documentDigest: page.documentDigest,
                    ordinal: page.ordinal
                )
            }
            return
        }
        try await transaction.save(page, precondition: .none)
    }

    private static func matches(
        _ lhs: LogicDatabaseFacetPage,
        _ rhs: LogicDatabaseFacetPage
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.facetID == rhs.facetID
            && lhs.ordinal == rhs.ordinal
            && lhs.pageCount == rhs.pageCount
            && lhs.documentByteCount == rhs.documentByteCount
            && lhs.documentDigest == rhs.documentDigest
            && lhs.payload == rhs.payload
    }
}
