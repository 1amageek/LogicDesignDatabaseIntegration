import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignDatabaseCore
import Foundation

public struct LogicDatabaseMutationPlanCompiler: Sendable {
    private let identityReader: LogicDatabaseIdentityProjectionReader

    public init(
        identityReader: LogicDatabaseIdentityProjectionReader = .init()
    ) {
        self.identityReader = identityReader
    }

    public func compile(
        _ importValue: LogicDatabaseImport,
        segmentID: DesignMutationPlanSegmentID,
        baseSnapshot: any DesignReadSnapshotReading,
        sourceEvidenceDigest: ContentDigest
    ) async throws -> DesignMutationPlan {
        let document = try LogicDatabaseCanonicalDocument(
            importValue: importValue
        )
        let graph = try LogicDatabaseObjectGraphBuilder().build(
            from: importValue,
            facetRootDigest: document.facetRootDigest
        )
        let priorIdentities = try await identityReader.read(
            facet: importValue.facet
        ) { request in
            try await baseSnapshot.query(request)
        }
        var priorObjects: [
            LogicDatabaseStableObjectKey: LogicDatabaseObjectIdentityRecord
        ] = [:]
        var priorRelations: [
            LogicDatabaseStableObjectKey: LogicDatabaseRelationIdentityRecord
        ] = [:]
        for record in priorIdentities {
            switch record {
            case .object(let object):
                priorObjects[object.stableKey] = object
            case .relation(let relation):
                priorRelations[relation.stableKey] = relation
            }
        }

        var provisionalEntityIDs: [DesignProvisionalEntityID] = []
        var plannedObjects: [LogicDatabasePlannedObject] = []
        plannedObjects.reserveCapacity(graph.objects.count)
        for descriptor in graph.objects {
            let identity: LogicDatabasePlannedEntityIdentity
            if let existing = priorObjects[descriptor.stableKey] {
                identity = .existing(existing.entityID)
            } else {
                let provisional = try DesignProvisionalEntityID(
                    rawValue: "logic-object-\(provisionalEntityIDs.count)"
                )
                provisionalEntityIDs.append(provisional)
                identity = .provisional(provisional)
            }
            plannedObjects.append(
                LogicDatabasePlannedObject(
                    descriptor: descriptor,
                    identity: identity
                )
            )
        }

        var provisionalOccurrenceIDs: [DesignProvisionalRelationOccurrenceID] = []
        var plannedRelations: [LogicDatabasePlannedRelation] = []
        plannedRelations.reserveCapacity(graph.relations.count)
        for descriptor in graph.relations {
            let identity: LogicDatabasePlannedRelationIdentity
            if let existing = priorRelations[descriptor.stableKey] {
                identity = .existing(existing.occurrenceID)
            } else {
                let provisional = try DesignProvisionalRelationOccurrenceID(
                    rawValue: "logic-relation-\(provisionalOccurrenceIDs.count)"
                )
                provisionalOccurrenceIDs.append(provisional)
                identity = .provisional(provisional)
            }
            plannedRelations.append(
                LogicDatabasePlannedRelation(
                    descriptor: descriptor,
                    identity: identity
                )
            )
        }

        let mutationPayload = try LogicDatabaseMutationPayload(
            facet: importValue.facet,
            canonicalDocument: Array(document.canonicalData),
            priorIdentities: priorIdentities,
            objects: plannedObjects,
            relations: plannedRelations
        )
        let payload = Array(
            try LogicDatabaseMutationPayloadCodec.encode(mutationPayload)
        )
        let digester = SHA256ContentDigester()
        let payloadDigest = try DesignMutationPlanDigest.payload(
            payload,
            using: digester
        )
        let identityPlan = try DesignMutationIdentityPlan(
            provisionalEntityIDs: provisionalEntityIDs,
            provisionalRelationOccurrenceIDs: provisionalOccurrenceIDs
        )
        let segment = try DesignMutationPlanSegment(
            id: segmentID,
            schemaID: try LogicDesignDatabaseSchema.schemaID,
            schemaVersion: .v1,
            adapterVersion: LogicDesignDatabaseSchema.adapterVersion,
            targetFacet: try importValue.facet.designFacetID,
            identityPlan: identityPlan,
            payload: payload,
            payloadDigest: payloadDigest,
            expectedWriteCount: UInt64(document.pages.count)
        )
        let payloadByteCount = UInt64(payload.count)
        let maximumValidationReadCount = try validationReadBudget(
            for: baseSnapshot.projectionSemantics
        )
        let budget = try DesignMutationPlanBudget(
            maximumSegmentCount: 1,
            maximumPayloadByteCount: payloadByteCount,
            maximumPreparedWriteCount: UInt64(document.pages.count),
            maximumValidationReadCount: maximumValidationReadCount
        )
        let baseRevision = baseSnapshot.revision
        let planDigest = try DesignMutationPlanDigest.plan(
            databaseID: baseRevision.databaseID,
            baseRevision: baseRevision,
            designSchemaBundleDigest: baseSnapshot.designSchemaBundleDigest,
            dependencyRootDigest: baseSnapshot.dependencyRootDigest,
            semanticDependencyGraphDigest: baseSnapshot.semanticDependencyGraphDigest,
            sourceEvidenceDigest: sourceEvidenceDigest,
            budget: budget,
            segments: [segment],
            using: digester
        )
        return DesignMutationPlan(
            databaseID: baseRevision.databaseID,
            baseRevision: baseRevision,
            designSchemaBundleDigest: baseSnapshot.designSchemaBundleDigest,
            dependencyRootDigest: baseSnapshot.dependencyRootDigest,
            semanticDependencyGraphDigest: baseSnapshot.semanticDependencyGraphDigest,
            sourceEvidenceDigest: sourceEvidenceDigest,
            budget: budget,
            segments: [segment],
            planDigest: planDigest
        )
    }

    private func validationReadBudget(
        for descriptors: [DesignProjectionSemanticDescriptor]
    ) throws(LogicDatabaseSchemaError) -> UInt64 {
        let mutatedFamilies: Set<DesignProjectionFamily> = [
            .entity,
            .name,
            .hierarchy,
        ]
        var entryCount: UInt64 = 0
        var materializationCount: UInt64 = 0
        for descriptor in descriptors where mutatedFamilies.contains(
            descriptor.family
        ) {
            let (nextEntryCount, entryOverflow) = entryCount
                .addingReportingOverflow(descriptor.entryCount)
            let (nextMaterializationCount, materializationOverflow)
                = materializationCount.addingReportingOverflow(1)
            guard !entryOverflow, !materializationOverflow else {
                throw .invalidProjectionRecord(
                    reason: "The exact-base projection size exceeds the validation budget range."
                )
            }
            entryCount = nextEntryCount
            materializationCount = nextMaterializationCount
        }
        let (nodeBound, nodeOverflow) = entryCount.multipliedReportingOverflow(
            by: 2
        )
        let (readBound, readOverflow) = nodeBound.addingReportingOverflow(
            materializationCount
        )
        guard !nodeOverflow, !readOverflow else {
            throw .invalidProjectionRecord(
                reason: "The exact-base projection validation budget overflows UInt64."
            )
        }
        return max(readBound, 1)
    }
}
