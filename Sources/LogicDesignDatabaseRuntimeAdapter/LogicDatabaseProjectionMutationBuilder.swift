import CircuiteFoundation
import DesignDatabaseCore
import DesignDatabaseRuntime
import LogicDesignDatabaseSchema

struct LogicDatabaseProjectionMutationBuilder: Sendable {
    func validate(
        payload: LogicDatabaseMutationPayload,
        graph: LogicDatabaseObjectGraph,
        context: DesignDatabaseRuntimeMutationValidation
    ) async throws {
        guard payload.facet == graph.facet,
              payload.objects.map(\.descriptor) == graph.objects,
              payload.relations.map(\.descriptor) == graph.relations else {
            throw LogicDatabaseSchemaError.invalidProjectionRecord(
                reason: "The planned object projection does not match the canonical logic document."
            )
        }
        let exactPrior = try await LogicDatabaseIdentityProjectionReader().read(
            facet: payload.facet
        ) { request in
            try await context.query(request)
        }
        guard exactPrior == payload.priorIdentities else {
            throw LogicDatabaseSchemaError.invalidProjectionRecord(
                reason: "The planned before state does not match the exact base projection."
            )
        }
    }

    func materialize(
        payload: LogicDatabaseMutationPayload,
        segmentID: DesignMutationPlanSegmentID,
        context: DesignDatabaseRuntimeMutationRestoration
    ) throws -> [DesignProjectionChange] {
        let exactPrior = payload.priorIdentities
        guard let assignments = context.identityAssignments(for: segmentID) else {
            throw LogicDatabaseSchemaError.invalidProjectionRecord(
                reason: "The Runtime did not provide identity assignments for the logic segment."
            )
        }

        var priorObjects: [
            LogicDatabaseStableObjectKey: LogicDatabaseObjectIdentityRecord
        ] = [:]
        var priorRelations: [
            LogicDatabaseStableObjectKey: LogicDatabaseRelationIdentityRecord
        ] = [:]
        for record in exactPrior {
            switch record {
            case .object(let object):
                priorObjects[object.stableKey] = object
            case .relation(let relation):
                priorRelations[relation.stableKey] = relation
            }
        }

        var desiredObjects: [LogicDatabaseObjectIdentityRecord] = []
        var entityIDsByStableKey: [LogicDatabaseStableObjectKey: DesignEntityID] = [:]
        var consumedEntityAssignments: Set<DesignProvisionalEntityID> = []
        for planned in payload.objects {
            let entityID: DesignEntityID
            switch planned.identity {
            case .existing(let existingID):
                guard priorObjects[planned.descriptor.stableKey]?.entityID
                    == existingID else {
                    throw LogicDatabaseSchemaError.invalidProjectionRecord(
                        reason: "An existing logic object identity is absent from the exact base."
                    )
                }
                entityID = existingID
            case .provisional(let provisionalID):
                guard priorObjects[planned.descriptor.stableKey] == nil,
                      consumedEntityAssignments.insert(provisionalID).inserted,
                      let assigned = assignments.entityID(for: provisionalID) else {
                    throw LogicDatabaseSchemaError.invalidProjectionRecord(
                        reason: "A new logic object lacks a unique reserved identity assignment."
                    )
                }
                entityID = assigned
            }
            guard entityIDsByStableKey.updateValue(
                entityID,
                forKey: planned.descriptor.stableKey
            ) == nil else {
                throw LogicDatabaseSchemaError.invalidProjectionRecord(
                    reason: "The planned logic graph contains a duplicate object identity."
                )
            }
            desiredObjects.append(
                LogicDatabaseObjectIdentityRecord(
                    facet: payload.facet,
                    stableKey: planned.descriptor.stableKey,
                    entityID: entityID,
                    kindID: planned.descriptor.kindID,
                    contentDigest: planned.descriptor.contentDigest
                )
            )
        }
        guard consumedEntityAssignments
            == Set(assignments.entities.map(\.provisionalID)) else {
            throw LogicDatabaseSchemaError.invalidProjectionRecord(
                reason: "The logic payload does not consume its exact entity identity plan."
            )
        }

        var desiredRelations: [LogicDatabaseRelationIdentityRecord] = []
        var consumedRelationAssignments: Set<DesignProvisionalRelationOccurrenceID> = []
        for planned in payload.relations {
            let occurrenceID: DesignRelationOccurrenceID
            switch planned.identity {
            case .existing(let existingID):
                guard priorRelations[planned.descriptor.stableKey]?.occurrenceID
                    == existingID else {
                    throw LogicDatabaseSchemaError.invalidProjectionRecord(
                        reason: "An existing logic relation identity is absent from the exact base."
                    )
                }
                occurrenceID = existingID
            case .provisional(let provisionalID):
                guard priorRelations[planned.descriptor.stableKey] == nil,
                      consumedRelationAssignments.insert(provisionalID).inserted,
                      let assigned = assignments.relationOccurrenceID(
                        for: provisionalID
                      ) else {
                    throw LogicDatabaseSchemaError.invalidProjectionRecord(
                        reason: "A new logic relation lacks a unique reserved identity assignment."
                    )
                }
                occurrenceID = assigned
            }
            guard let ownerEntityID = entityIDsByStableKey[
                planned.descriptor.ownerKey
            ], let targetEntityID = entityIDsByStableKey[
                planned.descriptor.targetKey
            ] else {
                throw LogicDatabaseSchemaError.invalidProjectionRecord(
                    reason: "A planned logic relation references an unresolved object identity."
                )
            }
            desiredRelations.append(
                LogicDatabaseRelationIdentityRecord(
                    facet: payload.facet,
                    stableKey: planned.descriptor.stableKey,
                    occurrenceID: occurrenceID,
                    ownerEntityID: ownerEntityID,
                    family: planned.descriptor.family,
                    relationKindID: planned.descriptor.relationKindID,
                    targetEntityID: targetEntityID,
                    orderKey: planned.descriptor.orderKey,
                    attributesDigest: planned.descriptor.attributesDigest
                )
            )
        }
        guard consumedRelationAssignments
            == Set(assignments.relationOccurrences.map(\.provisionalID)) else {
            throw LogicDatabaseSchemaError.invalidProjectionRecord(
                reason: "The logic payload does not consume its exact relation identity plan."
            )
        }

        let desiredIdentities: [LogicDatabaseProjectionIdentityRecord]
            = desiredObjects.map(LogicDatabaseProjectionIdentityRecord.object)
            + desiredRelations.map(LogicDatabaseProjectionIdentityRecord.relation)
        var changes: [DesignProjectionChange] = []
        try appendChanges(
            family: .name,
            before: try exactPrior.map { try $0.nameProjectionEntry() },
            after: try desiredIdentities.map { try $0.nameProjectionEntry() },
            to: &changes
        )
        try appendChanges(
            family: .entity,
            before: try priorObjects.values.map {
                try $0.entityProjectionEntry()
            },
            after: try desiredObjects.map {
                try $0.entityProjectionEntry()
            },
            to: &changes
        )

        let relationFamilies = Set(priorRelations.values.map(\.family))
            .union(desiredRelations.map(\.family))
        for family in relationFamilies.sorted() {
            let before = try priorRelations.values
                .filter { $0.family == family }
                .flatMap { try $0.relationProjectionEntries() }
            let after = try desiredRelations
                .filter { $0.family == family }
                .flatMap { try $0.relationProjectionEntries() }
            try appendChanges(
                family: family,
                before: before,
                after: after,
                to: &changes
            )
        }
        return changes.sorted()
    }

    private func appendChanges(
        family: DesignProjectionFamily,
        before: [DesignProjectionEntry],
        after: [DesignProjectionEntry],
        to changes: inout [DesignProjectionChange]
    ) throws {
        let beforeByKey = try uniqueEntries(before)
        let afterByKey = try uniqueEntries(after)
        for key in Set(beforeByKey.keys).union(afterByKey.keys).sorted() {
            let beforeEntry = beforeByKey[key]
            let afterEntry = afterByKey[key]
            guard beforeEntry != afterEntry else { continue }
            changes.append(
                try DesignProjectionChange(
                    family: family,
                    before: beforeEntry,
                    after: afterEntry
                )
            )
        }
    }

    private func uniqueEntries(
        _ entries: [DesignProjectionEntry]
    ) throws -> [DesignCanonicalKey: DesignProjectionEntry] {
        var result: [DesignCanonicalKey: DesignProjectionEntry] = [:]
        result.reserveCapacity(entries.count)
        for entry in entries {
            guard result.updateValue(entry, forKey: entry.key) == nil else {
                throw LogicDatabaseSchemaError.invalidProjectionRecord(
                    reason: "A logic projection contains duplicate canonical keys."
                )
            }
        }
        return result
    }
}
