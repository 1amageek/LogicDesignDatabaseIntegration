import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DatabaseTypesFoundation
import DesignDatabaseCore
import DesignDatabaseRuntime
import Foundation
import LogicDesignDatabaseSchema
import LogicIR
import PowerIntent

public struct LogicDesignDatabaseSnapshotReader:
    LogicDesignDatabaseReading,
    Sendable
{
    public init() {}

    public func readState(
        from snapshot: any DesignReadSnapshot,
        budget: LogicDatabaseReadBudget
    ) async throws -> LogicDesignDatabaseState {
        let rtlValue = try await readFacet(.rtl, from: snapshot, budget: budget)
        let gateValue = try await readFacet(.gate, from: snapshot, budget: budget)
        let powerValue = try await readFacet(
            .powerIntent,
            from: snapshot,
            budget: budget
        )
        let rtl: RTLDesign?
        if case .rtl(let design)? = rtlValue {
            rtl = design
        } else {
            rtl = nil
        }
        let gate: GateDesign?
        let gateSourceRTL: LogicDatabaseFacetSourceBinding?
        if case .gate(let design, let sourceRTL)? = gateValue {
            gate = design
            gateSourceRTL = sourceRTL
        } else {
            gate = nil
            gateSourceRTL = nil
        }
        let powerIntent: PowerIntentDesign?
        let powerIntentSourceRTL: LogicDatabaseFacetSourceBinding?
        if case .powerIntent(let design, let sourceRTL)? = powerValue {
            powerIntent = design
            powerIntentSourceRTL = sourceRTL
        } else {
            powerIntent = nil
            powerIntentSourceRTL = nil
        }
        let rtlRoot = try LogicDatabaseFacet.rtl.designFacetID
        let actualRTLRoot = snapshot.facetRoots.first(where: {
            $0.facetID == rtlRoot
        })?.digest
        var invalidations: [LogicDatabaseFacetInvalidation] = []
        if let gateSourceRTL,
           let invalidation = invalidation(
                targetFacet: .gate,
                binding: gateSourceRTL,
                actualRTLRoot: actualRTLRoot,
                observedRevision: snapshot.revision
           ) {
            invalidations.append(invalidation)
        }
        if let powerIntentSourceRTL,
           let invalidation = invalidation(
                targetFacet: .powerIntent,
                binding: powerIntentSourceRTL,
                actualRTLRoot: actualRTLRoot,
                observedRevision: snapshot.revision
           ) {
            invalidations.append(invalidation)
        }
        return LogicDesignDatabaseState(
            rtl: rtl,
            gate: gate,
            powerIntent: powerIntent,
            gateSourceRTL: gateSourceRTL,
            powerIntentSourceRTL: powerIntentSourceRTL,
            invalidations: invalidations
        )
    }

    public func readFacet(
        _ facet: LogicDatabaseFacet,
        from snapshot: any DesignReadSnapshot,
        budget: LogicDatabaseReadBudget
    ) async throws -> LogicDatabaseImport? {
        let facetID = try facet.designFacetID
        guard let expectedRoot = snapshot.facetRoots.first(where: {
            $0.facetID == facetID
        })?.digest else {
            return nil
        }
        guard let runtimeSnapshot = snapshot as? DesignDatabaseRuntimeSnapshot else {
            throw LogicDatabaseReadError.unsupportedSnapshotImplementation
        }
        return try await runtimeSnapshot.withRuntimeReads(
            maximumReadCount: try budget.runtimeReadCount
        ) { reads in
            var partition = DirectoryPath<LogicDatabaseFacetPage>()
            partition.set(
                LogicDatabaseFacetPage.fields.facetID,
                to: facet.rawValue
            )
            partition.set(
                LogicDatabaseFacetPage.fields.documentDigest,
                to: expectedRoot.hexadecimalValue
            )
            var pages: [LogicDatabaseFacetPage] = []
            pages.reserveCapacity(min(budget.maximumPageCount, budget.pageFetchLimit))
            var continuation: DatabaseScanContinuation?
            repeat {
                let page = try await reads.scan(
                    LogicDatabaseFacetPage.self,
                    in: partition,
                    after: continuation,
                    limit: budget.pageFetchLimit
                )
                pages.append(contentsOf: page.items)
                guard pages.count <= budget.maximumPageCount else {
                    throw LogicDatabaseReadError.pageBudgetExceeded(
                        limit: budget.maximumPageCount
                    )
                }
                continuation = page.continuation
            } while continuation != nil
            return try decode(
                pages: pages,
                facet: facet,
                expectedRoot: expectedRoot
            )
        }
    }

    private func decode(
        pages: [LogicDatabaseFacetPage],
        facet: LogicDatabaseFacet,
        expectedRoot: ContentDigest
    ) throws -> LogicDatabaseImport {
        guard let first = pages.first else {
            throw LogicDatabaseReadError.missingFacetPages(facet)
        }
        let ordered = pages.sorted { lhs, rhs in
            lhs.ordinal < rhs.ordinal
        }
        guard first.pageCount == UInt64(ordered.count),
            ordered.allSatisfy({ page in
                page.facetID == facet.rawValue
                    && page.pageCount == first.pageCount
                    && page.documentByteCount == first.documentByteCount
                    && page.documentDigest == first.documentDigest
              }) else {
            throw LogicDatabaseReadError.inconsistentPageMetadata(facet)
        }
        for (index, page) in ordered.enumerated() {
            guard page.ordinal == UInt64(index) else {
                throw LogicDatabaseReadError.nonContiguousPages(facet)
            }
        }
        guard let capacity = Int(exactly: first.documentByteCount) else {
            throw LogicDatabaseReadError.inconsistentPageMetadata(facet)
        }
        var data = Data()
        data.reserveCapacity(capacity)
        for page in ordered {
            page.payload.withUnsafeBytes { bytes in
                data.append(bytes.bindMemory(to: UInt8.self))
            }
        }
        guard let actualByteCount = UInt64(exactly: data.count),
              actualByteCount == first.documentByteCount else {
            throw LogicDatabaseReadError.byteCountMismatch(
                expected: first.documentByteCount,
                actual: UInt64(data.count)
            )
        }
        let actualRoot = try SHA256ContentDigester().digest(data: data)
        guard actualRoot == expectedRoot else {
            throw LogicDatabaseReadError.facetRootMismatch(
                expected: expectedRoot,
                actual: actualRoot
            )
        }
        do {
            return try LogicDatabaseCanonicalCodec.decode(data, facet: facet)
        } catch let error {
            throw LogicDatabaseReadError.decodeFailed(error)
        }
    }

    private func invalidation(
        targetFacet: LogicDatabaseFacet,
        binding: LogicDatabaseFacetSourceBinding,
        actualRTLRoot: ContentDigest?,
        observedRevision: DesignRevisionReference
    ) -> LogicDatabaseFacetInvalidation? {
        guard let actualRTLRoot else {
            return LogicDatabaseFacetInvalidation(
                targetFacet: targetFacet,
                observedRevision: observedRevision,
                sourceBinding: binding,
                actualSourceRootDigest: nil,
                reason: .sourceFacetMissing
            )
        }
        guard actualRTLRoot != binding.sourceRootDigest else {
            return nil
        }
        return LogicDatabaseFacetInvalidation(
            targetFacet: targetFacet,
            observedRevision: observedRevision,
            sourceBinding: binding,
            actualSourceRootDigest: actualRTLRoot,
            reason: .sourceRootChanged
        )
    }
}
