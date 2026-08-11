import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore
import DesignDatabaseRuntime
import Foundation
import LogicDesignDatabaseRuntimeAdapter
import LogicDesignDatabaseSchema
import LogicIR
import PowerIntent
import Testing

@Suite("LogicDesign database integration")
struct LogicDesignDatabaseIntegrationTests {
    @Test("RTL, gate, and power intent round-trip through exact candidate revisions")
    func exactCandidateRoundTrip() async throws {
        let harness = try await makeHarness()
        let handle = harness.handle
        let genesis = handle.genesisRevision
        let largeRTL = RTLDesign(
            topModuleName: "top",
            modules: [RTLModule(id: "module-top", name: "top")] +
                (0..<800).map { index in
                    RTLModule(
                        id: "module-\(index)",
                        name: "helper_\(index)"
                    )
                }
        )

        let rtlReceipt = try await commit(
            .rtl(largeRTL),
            operation: "import-rtl",
            segment: "rtl",
            base: genesis,
            handle: handle,
            evidence: try digest("rtl-evidence")
        )
        #expect(rtlReceipt.baseRevision == genesis)
        #expect(rtlReceipt.facetRoots.count == 1)
        let rtlPlan = try await plan(
            .rtl(largeRTL),
            segment: "rtl-page-count",
            base: genesis,
            handle: handle,
            evidence: try digest("rtl-page-evidence")
        )
        #expect(rtlPlan.segments[0].expectedWriteCount > 1)

        let gate = GateDesign(
            topModuleName: "top",
            modules: [GateModule(id: "gate-top", name: "top")]
        )
        let gateSourceRTL = try sourceRTLBinding(
            at: rtlReceipt.candidateRevision,
            facetRoots: rtlReceipt.facetRoots
        )
        let gateReceipt = try await commit(
            .gate(gate, sourceRTL: gateSourceRTL),
            operation: "import-gate",
            segment: "gate",
            base: rtlReceipt.candidateRevision,
            handle: handle,
            evidence: try digest("gate-evidence")
        )
        #expect(gateReceipt.facetRoots.count == 2)

        let powerIntent = PowerIntentDesign(
            format: .upf,
            domains: [
                PowerDomain(
                    id: "domain-core",
                    name: "PD_CORE",
                    elements: ["top"],
                    primarySupplySet: "SS_CORE"
                ),
            ],
            supplySets: [
                PowerSupplySet(
                    id: "supply-core",
                    name: "SS_CORE",
                    supplyNets: ["VDD", "VSS"]
                ),
            ]
        )
        let powerSourceRTL = try sourceRTLBinding(
            at: gateReceipt.candidateRevision,
            facetRoots: gateReceipt.facetRoots
        )
        let powerReceipt = try await commit(
            .powerIntent(powerIntent, sourceRTL: powerSourceRTL),
            operation: "import-power-intent",
            segment: "power-intent",
            base: gateReceipt.candidateRevision,
            handle: handle,
            evidence: try digest("power-evidence")
        )
        #expect(powerReceipt.facetRoots.count == 3)

        let snapshot = try await handle.openSnapshot(
            at: powerReceipt.candidateRevision
        )
        let state = try await LogicDesignDatabaseSnapshotReader().readState(
            from: snapshot,
            budget: LogicDatabaseReadBudget()
        )
        #expect(state.rtl == largeRTL)
        #expect(state.gate == gate)
        #expect(state.powerIntent == powerIntent)
        #expect(state.gateSourceRTL == gateSourceRTL)
        #expect(state.powerIntentSourceRTL == powerSourceRTL)
        #expect(state.invalidations.isEmpty)
        #expect(state.isSemanticallyCurrent)
        #expect(try await handle.resolve(.named(.main)) == genesis)

        #expect(await snapshot.close() == .closed)
        #expect(await handle.close() == .closed)
        #expect(await harness.provider.close() == .closed)
    }

    @Test("RTL object identities survive edits while hierarchy projections stay paired")
    func rtlObjectIdentityAndHierarchyEvolution() async throws {
        let harness = try await makeHarness()
        let handle = harness.handle
        let firstRTL = RTLDesign(
            topModuleName: "top",
            modules: [
                RTLModule(
                    id: "module-top",
                    name: "top",
                    ports: [
                        RTLPort(
                            id: "port-a",
                            name: "a",
                            direction: .input
                        ),
                    ],
                    signals: [
                        RTLSignal(id: "signal-survives", name: "survives"),
                        RTLSignal(id: "signal-remove", name: "remove"),
                    ]
                ),
            ]
        )
        let firstReceipt = try await commit(
            .rtl(firstRTL),
            operation: "identity-rtl-v1",
            segment: "identity-rtl-v1",
            base: handle.genesisRevision,
            handle: handle,
            evidence: try digest("identity-rtl-v1-evidence")
        )
        let firstSnapshot = try await handle.openSnapshot(
            at: firstReceipt.candidateRevision
        )
        let firstIdentities = try await readIdentities(
            facet: .rtl,
            snapshot: firstSnapshot
        )
        let firstObjects = objectIdentities(firstIdentities)
        let firstRelations = relationIdentities(firstIdentities)
        try await expectExactHierarchyProjection(
            firstRelations,
            snapshot: firstSnapshot
        )
        #expect(await firstSnapshot.close() == .closed)

        let secondRTL = RTLDesign(
            topModuleName: "top",
            modules: [
                RTLModule(
                    id: "module-top",
                    name: "top",
                    ports: [
                        RTLPort(
                            id: "port-a",
                            name: "renamed_a",
                            direction: .input
                        ),
                    ],
                    signals: [
                        RTLSignal(
                            id: "signal-survives",
                            name: "survives",
                            storage: .register
                        ),
                        RTLSignal(id: "signal-new", name: "new_signal"),
                    ]
                ),
            ]
        )
        let secondReceipt = try await commit(
            .rtl(secondRTL),
            operation: "identity-rtl-v2",
            segment: "identity-rtl-v2",
            base: firstReceipt.candidateRevision,
            handle: handle,
            evidence: try digest("identity-rtl-v2-evidence")
        )
        let secondSnapshot = try await handle.openSnapshot(
            at: secondReceipt.candidateRevision
        )
        let secondIdentities = try await readIdentities(
            facet: .rtl,
            snapshot: secondSnapshot
        )
        let secondObjects = objectIdentities(secondIdentities)
        let secondRelations = relationIdentities(secondIdentities)

        for components in [
            ["design"],
            ["module", "module-top"],
            ["module", "module-top", "port", "port-a"],
            ["module", "module-top", "signal", "signal-survives"],
        ] {
            let firstObject = try #require(firstObjects[components])
            let secondObject = try #require(secondObjects[components])
            #expect(firstObject.entityID == secondObject.entityID)
        }
        let removedKey = ["module", "module-top", "signal", "signal-remove"]
        let addedKey = ["module", "module-top", "signal", "signal-new"]
        #expect(firstObjects[removedKey] != nil)
        #expect(secondObjects[removedKey] == nil)
        #expect(firstObjects[addedKey] == nil)
        #expect(secondObjects[addedKey] != nil)
        #expect(
            firstObjects[removedKey]?.entityID
                != secondObjects[addedKey]?.entityID
        )

        let survivingRelationKey = [
            "contains", "module", "module-top", "port", "port-a",
        ]
        let firstRelation = try #require(firstRelations[survivingRelationKey])
        let secondRelation = try #require(secondRelations[survivingRelationKey])
        #expect(firstRelation.occurrenceID == secondRelation.occurrenceID)
        try await expectExactHierarchyProjection(
            secondRelations,
            snapshot: secondSnapshot
        )
        let state = try await LogicDesignDatabaseSnapshotReader().readState(
            from: secondSnapshot,
            budget: LogicDatabaseReadBudget()
        )
        #expect(state.rtl == secondRTL)
        #expect(await secondSnapshot.close() == .closed)
        #expect(await handle.close() == .closed)
        #expect(await harness.provider.close() == .closed)
    }

    @Test("Runtime rejects a mutation whose prior identity set omits exact base state")
    func omittedPriorIdentityPublishesNothing() async throws {
        let harness = try await makeHarness()
        let handle = harness.handle
        let rtl = RTLDesign(
            topModuleName: "top",
            modules: [
                RTLModule(
                    id: "module-top",
                    name: "top",
                    ports: [
                        RTLPort(
                            id: "port-a",
                            name: "a",
                            direction: .input
                        ),
                    ]
                ),
            ]
        )
        let firstReceipt = try await commit(
            .rtl(rtl),
            operation: "omitted-prior-v1",
            segment: "omitted-prior-v1",
            base: handle.genesisRevision,
            handle: handle,
            evidence: try digest("omitted-prior-v1-evidence")
        )
        let validPlan = try await plan(
            .rtl(rtl),
            segment: "omitted-prior-v2",
            base: firstReceipt.candidateRevision,
            handle: handle,
            evidence: try digest("omitted-prior-v2-evidence")
        )
        let validSegment = try #require(validPlan.segments.first)
        let validPayload = try LogicDatabaseMutationPayloadCodec.decode(
            Data(validSegment.payload)
        )
        #expect(!validPayload.priorIdentities.isEmpty)
        let incompletePayload = try LogicDatabaseMutationPayload(
            facet: validPayload.facet,
            canonicalDocument: validPayload.canonicalDocument,
            priorIdentities: Array(validPayload.priorIdentities.dropFirst()),
            objects: validPayload.objects,
            relations: validPayload.relations
        )
        let encodedPayload = Array(
            try LogicDatabaseMutationPayloadCodec.encode(incompletePayload)
        )
        let payloadDigest = try DesignMutationPlanDigest.payload(
            encodedPayload,
            using: SHA256ContentDigester()
        )
        let incompleteSegment = try DesignMutationPlanSegment(
            id: validSegment.id,
            schemaID: validSegment.schemaID,
            schemaVersion: validSegment.schemaVersion,
            adapterVersion: validSegment.adapterVersion,
            targetFacet: validSegment.targetFacet,
            identityPlan: validSegment.identityPlan,
            payload: encodedPayload,
            payloadDigest: payloadDigest,
            expectedWriteCount: validSegment.expectedWriteCount
        )
        let planDigest = try DesignMutationPlanDigest.plan(
            databaseID: validPlan.databaseID,
            baseRevision: validPlan.baseRevision,
            designSchemaBundleDigest: validPlan.designSchemaBundleDigest,
            dependencyRootDigest: validPlan.dependencyRootDigest,
            semanticDependencyGraphDigest: validPlan.semanticDependencyGraphDigest,
            sourceEvidenceDigest: validPlan.sourceEvidenceDigest,
            budget: validPlan.budget,
            segments: [incompleteSegment],
            using: SHA256ContentDigester()
        )
        let incompletePlan = DesignMutationPlan(
            databaseID: validPlan.databaseID,
            baseRevision: validPlan.baseRevision,
            designSchemaBundleDigest: validPlan.designSchemaBundleDigest,
            dependencyRootDigest: validPlan.dependencyRootDigest,
            semanticDependencyGraphDigest: validPlan.semanticDependencyGraphDigest,
            sourceEvidenceDigest: validPlan.sourceEvidenceDigest,
            budget: validPlan.budget,
            segments: [incompleteSegment],
            planDigest: planDigest
        )
        let operationID = try DesignDatabaseOperationID(
            rawValue: "omitted-prior-v2"
        )
        let submission = DesignCommitSubmission(
            operationID: operationID,
            plan: incompletePlan,
            requestDigest: try DesignMutationPlanDigest.request(
                operationID: operationID,
                planDigest: planDigest,
                using: SHA256ContentDigester()
            )
        )

        switch try await handle.submit(submission) {
        case .rejected(let rejection):
            guard case .invalidSegmentPayload(let segmentID, _) = rejection.reason else {
                Issue.record("The incomplete before state was rejected for the wrong reason.")
                break
            }
            #expect(segmentID == validSegment.id)
            #expect(
                try await handle.commitStatus(
                    operation: rejection.operation,
                    requestDigest: submission.requestDigest
                ) == .rejected(rejection)
            )
        case .committed:
            Issue.record("An incomplete before state published a candidate revision.")
        case .outcomeUnknown:
            Issue.record("The in-memory incomplete before-state outcome was unknown.")
        }
        let retainedSnapshot = try await handle.openSnapshot(
            at: firstReceipt.candidateRevision
        )
        let retainedState = try await LogicDesignDatabaseSnapshotReader().readState(
            from: retainedSnapshot,
            budget: LogicDatabaseReadBudget()
        )
        #expect(retainedState.rtl == rtl)
        #expect(await retainedSnapshot.close() == .closed)
        #expect(await handle.close() == .closed)
        #expect(await harness.provider.close() == .closed)
    }

    @Test("An RTL root change invalidates inherited derived facets and rejects stale imports")
    func rtlRootChangeInvalidatesDerivedFacets() async throws {
        let harness = try await makeHarness()
        let handle = harness.handle
        let genesis = handle.genesisRevision
        let firstRTL = RTLDesign(
            topModuleName: "top",
            modules: [RTLModule(id: "module-top-v1", name: "top")]
        )
        let firstRTLReceipt = try await commit(
            .rtl(firstRTL),
            operation: "import-rtl-v1",
            segment: "rtl-v1",
            base: genesis,
            handle: handle,
            evidence: try digest("rtl-v1-evidence")
        )
        let firstSourceRTL = try sourceRTLBinding(
            at: firstRTLReceipt.candidateRevision,
            facetRoots: firstRTLReceipt.facetRoots
        )
        let gate = GateDesign(
            topModuleName: "top",
            modules: [GateModule(id: "gate-top-v1", name: "top")]
        )
        let gateReceipt = try await commit(
            .gate(gate, sourceRTL: firstSourceRTL),
            operation: "import-gate-v1",
            segment: "gate-v1",
            base: firstRTLReceipt.candidateRevision,
            handle: handle,
            evidence: try digest("gate-v1-evidence")
        )
        let secondRTL = RTLDesign(
            topModuleName: "top",
            modules: [
                RTLModule(id: "module-top-v2", name: "top"),
                RTLModule(id: "module-helper-v2", name: "helper"),
            ]
        )
        let secondRTLReceipt = try await commit(
            .rtl(secondRTL),
            operation: "import-rtl-v2",
            segment: "rtl-v2",
            base: gateReceipt.candidateRevision,
            handle: handle,
            evidence: try digest("rtl-v2-evidence")
        )
        let secondRTLRoot = try sourceRTLBinding(
            at: secondRTLReceipt.candidateRevision,
            facetRoots: secondRTLReceipt.facetRoots
        ).sourceRootDigest

        let snapshot = try await handle.openSnapshot(
            at: secondRTLReceipt.candidateRevision
        )
        let state = try await LogicDesignDatabaseSnapshotReader().readState(
            from: snapshot,
            budget: LogicDatabaseReadBudget()
        )
        #expect(state.rtl == secondRTL)
        #expect(state.gate == gate)
        #expect(state.gateSourceRTL == firstSourceRTL)
        #expect(!state.isSemanticallyCurrent)
        #expect(state.invalidations.count == 1)
        #expect(state.invalidations.first?.targetFacet == .gate)
        #expect(state.invalidations.first?.reason == .sourceRootChanged)
        #expect(state.invalidations.first?.sourceBinding == firstSourceRTL)
        #expect(state.invalidations.first?.actualSourceRootDigest == secondRTLRoot)
        #expect(await snapshot.close() == .closed)

        let staleBinding = try LogicDatabaseFacetSourceBinding(
            sourceRevision: secondRTLReceipt.candidateRevision,
            sourceFacet: .rtl,
            sourceRootDigest: firstSourceRTL.sourceRootDigest
        )
        let stalePlan = try await plan(
            .gate(gate, sourceRTL: staleBinding),
            segment: "stale-gate",
            base: secondRTLReceipt.candidateRevision,
            handle: handle,
            evidence: try digest("stale-gate-evidence")
        )
        let staleOperationID = try DesignDatabaseOperationID(
            rawValue: "import-stale-gate"
        )
        let staleSubmission = DesignCommitSubmission(
            operationID: staleOperationID,
            plan: stalePlan,
            requestDigest: try DesignMutationPlanDigest.request(
                operationID: staleOperationID,
                planDigest: stalePlan.planDigest,
                using: SHA256ContentDigester()
            )
        )
        switch try await handle.submit(staleSubmission) {
        case .rejected(let rejection):
            guard case .validationFailed(let diagnostics, _) = rejection.reason else {
                Issue.record("The stale gate import did not retain typed validation diagnostics.")
                break
            }
            #expect(
                diagnostics.contains {
                    $0.code.rawValue == "LOGIC_SOURCE_RTL_ROOT_MISMATCH"
                }
            )
            #expect(
                try await handle.commitStatus(
                    operation: rejection.operation,
                    requestDigest: staleSubmission.requestDigest
                ) == .rejected(rejection)
            )
        case .committed:
            Issue.record("The stale gate import published a candidate revision.")
        case .outcomeUnknown:
            Issue.record("The in-memory stale gate outcome was unknown.")
        }
        #expect(try await handle.resolve(.named(.main)) == genesis)
        let retainedSnapshot = try await handle.openSnapshot(
            at: secondRTLReceipt.candidateRevision
        )
        let retainedState = try await LogicDesignDatabaseSnapshotReader().readState(
            from: retainedSnapshot,
            budget: LogicDatabaseReadBudget()
        )
        #expect(retainedState.rtl == secondRTL)
        #expect(retainedState.gate == gate)
        #expect(retainedState.invalidations == state.invalidations)
        #expect(await retainedSnapshot.close() == .closed)
        #expect(await handle.close() == .closed)
        #expect(await harness.provider.close() == .closed)
    }

    @Test("Invalid RTL publishes no candidate revision")
    func invalidRTLPublishesNothing() async throws {
        let harness = try await makeHarness()
        let handle = harness.handle
        let genesis = handle.genesisRevision
        let invalidRTL = RTLDesign(
            topModuleName: "missing",
            modules: [RTLModule(id: "module-top", name: "top")]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = Array(try encoder.encode(invalidRTL))
        let submission = try await rawSubmission(
            payload: payload,
            operation: "invalid-rtl",
            segment: "invalid-rtl",
            facet: .rtl,
            base: genesis,
            handle: handle,
            evidence: try digest("invalid-evidence")
        )

        switch try await handle.submit(submission) {
        case .rejected(let rejection):
            guard case .validationFailed(let diagnostics, _) = rejection.reason else {
                Issue.record("Invalid RTL did not retain typed validation diagnostics.")
                return
            }
            #expect(
                diagnostics.contains {
                    $0.code.rawValue == "LOGIC_TOP_UNRESOLVED"
                }
            )
        case .committed:
            Issue.record("Invalid RTL published a candidate revision.")
        case .outcomeUnknown:
            Issue.record("The in-memory invalid RTL outcome was unknown.")
        }
        #expect(try await handle.resolve(.named(.main)) == genesis)
        let snapshot = try await handle.openSnapshot(at: genesis)
        #expect(snapshot.facetRoots.isEmpty)
        #expect(await snapshot.close() == .closed)
        #expect(await handle.close() == .closed)
        #expect(await harness.provider.close() == .closed)
    }

    @Test("Planner rejects invalid domain state before a mutation plan exists")
    func plannerRejectsInvalidDomainState() async throws {
        let invalid = RTLDesign(topModuleName: "missing", modules: [])
        let harness = try await makeHarness()
        let snapshot = try await harness.handle.openSnapshot(
            at: harness.handle.genesisRevision
        )
        await #expect(throws: LogicDatabaseSchemaError.self) {
            _ = try await LogicDatabaseMutationPlanCompiler().compile(
                .rtl(invalid),
                segmentID: DesignMutationPlanSegmentID(rawValue: "invalid"),
                baseSnapshot: snapshot,
                sourceEvidenceDigest: try digest("evidence")
            )
        }
        #expect(await snapshot.close() == .closed)
        #expect(await harness.handle.close() == .closed)
        #expect(await harness.provider.close() == .closed)
    }

    private func makeHarness() async throws -> (
        provider: DesignDatabaseRuntimeProvider,
        handle: any DesignDatabaseHandle
    ) {
        let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
            schemaVersion: Schema.Version(1, 0, 0),
            contributions: [try LogicDesignDatabaseRuntimeAdapter().contribution()]
        )
        let locator = try DesignDatabaseLocator(
            namespace: "tests",
            segments: ["logic-integration"]
        )
        let databaseID = try DesignDatabaseID(high: 1, low: 2)
        let genesisRevisionID = DesignRevisionID(high: 0, low: 1)
        let subjectScopeID = try DesignAuthorizationSubjectScopeID(high: 3, low: 4)
        let operationID = try DesignDatabaseOperationID(rawValue: "create-logic")
        let capabilities = try DesignCapabilitySet([])
        let canonical = try DesignDatabaseRuntimeGenesisRequest(
            locator: locator,
            databaseID: databaseID,
            genesisRevisionID: genesisRevisionID,
            authorizationSubjectScopeID: subjectScopeID,
            operationID: operationID,
            declaredFeatureCapabilities: capabilities,
            initialSchemaBundle: registration.designSchemaBundle,
            registrationDigest: registration.registrationDigest
        )
        let provider = DesignDatabaseRuntimeProvider(
            registration: registration,
            containerProvider: LogicDatabaseTestContainerProvider(),
            authorizationSubjectScopeID: subjectScopeID,
            creationRequestedAuthorization: DesignDatabaseAuthorizationGrantSet([
                .read,
                .proposeCandidate,
                .inspectOwnOperationOutcome,
            ]),
            authorizer: LogicDatabaseTestAuthorizer()
        )
        let handle = try await provider.create(
            DesignDatabaseCreateRequest(
                locator: locator,
                databaseID: databaseID,
                genesisRevisionID: genesisRevisionID,
                operationID: operationID,
                initialSchemaBundle: registration.designSchemaBundle,
                declaredFeatureCapabilities: capabilities,
                requestDigest: canonical.requestDigest
            )
        )
        return (provider, handle)
    }

    private func readIdentities(
        facet: LogicDatabaseFacet,
        snapshot: any DesignReadSnapshot
    ) async throws -> [LogicDatabaseProjectionIdentityRecord] {
        try await LogicDatabaseIdentityProjectionReader().read(facet: facet) {
            request in
            try await snapshot.query(request)
        }
    }

    private func objectIdentities(
        _ identities: [LogicDatabaseProjectionIdentityRecord]
    ) -> [[String]: LogicDatabaseObjectIdentityRecord] {
        Dictionary(uniqueKeysWithValues: identities.compactMap { identity in
            guard case .object(let object) = identity else { return nil }
            return (object.stableKey.components, object)
        })
    }

    private func relationIdentities(
        _ identities: [LogicDatabaseProjectionIdentityRecord]
    ) -> [[String]: LogicDatabaseRelationIdentityRecord] {
        Dictionary(uniqueKeysWithValues: identities.compactMap { identity in
            guard case .relation(let relation) = identity else { return nil }
            return (relation.stableKey.components, relation)
        })
    }

    private func expectExactHierarchyProjection(
        _ relations: [[String]: LogicDatabaseRelationIdentityRecord],
        snapshot: any DesignReadSnapshot
    ) async throws {
        let budget = try DesignQueryBudget(
            maximumResultCount: 10_000,
            maximumNodeFetchCount: 10_000,
            maximumEncodedReadByteCount: 16_777_216,
            maximumDecodedByteCount: 16_777_216,
            maximumOutputByteCount: 16_777_216,
            maximumWorkCount: 100_000
        )
        let page = try await snapshot.query(
            DesignQueryRequest(
                family: .hierarchy,
                maximumPageResultCount: 10_000,
                budget: budget
            )
        )
        #expect(page.completion == .sourceExhausted)
        let expected = try relations.values
            .filter { $0.family == .hierarchy }
            .flatMap { try $0.relationProjectionEntries() }
            .sorted()
        #expect(page.rows == expected)
        #expect(page.rows.count == relations.count * 2)
    }

    private func commit(
        _ importValue: LogicDatabaseImport,
        operation: String,
        segment: String,
        base: DesignRevisionReference,
        handle: any DesignDatabaseHandle,
        evidence: ContentDigest
    ) async throws -> DesignCommitReceipt {
        let mutationPlan = try await plan(
            importValue,
            segment: segment,
            base: base,
            handle: handle,
            evidence: evidence
        )
        let operationID = try DesignDatabaseOperationID(rawValue: operation)
        let submission = DesignCommitSubmission(
            operationID: operationID,
            plan: mutationPlan,
            requestDigest: try DesignMutationPlanDigest.request(
                operationID: operationID,
                planDigest: mutationPlan.planDigest,
                using: SHA256ContentDigester()
            )
        )
        switch try await handle.submit(submission) {
        case .committed(let receipt):
            return receipt
        case .rejected(let rejection):
            throw TestFailure("Candidate rejected: \(rejection)")
        case .outcomeUnknown:
            throw TestFailure("Candidate outcome was unknown.")
        }
    }

    private func plan(
        _ importValue: LogicDatabaseImport,
        segment: String,
        base: DesignRevisionReference,
        handle: any DesignDatabaseHandle,
        evidence: ContentDigest
    ) async throws -> DesignMutationPlan {
        let snapshot = try await handle.openSnapshot(at: base)
        do {
            let result = try await LogicDatabaseMutationPlanCompiler().compile(
                importValue,
                segmentID: DesignMutationPlanSegmentID(rawValue: segment),
                baseSnapshot: snapshot,
                sourceEvidenceDigest: evidence
            )
            _ = await snapshot.close()
            return result
        } catch {
            _ = await snapshot.close()
            throw error
        }
    }

    private func rawSubmission(
        payload: [UInt8],
        operation: String,
        segment: String,
        facet: LogicDatabaseFacet,
        base: DesignRevisionReference,
        handle: any DesignDatabaseHandle,
        evidence: ContentDigest
    ) async throws -> DesignCommitSubmission {
        let snapshot = try await handle.openSnapshot(at: base)
        do {
            let payloadDigest = try DesignMutationPlanDigest.payload(
                payload,
                using: SHA256ContentDigester()
            )
            let writeCount = try LogicDatabaseCanonicalDocument.pageCount(
                forByteCount: payload.count
            )
            let planSegment = try DesignMutationPlanSegment(
                id: DesignMutationPlanSegmentID(rawValue: segment),
                schemaID: try LogicDesignDatabaseSchema.schemaID,
                schemaVersion: .v1,
                adapterVersion: LogicDesignDatabaseSchema.adapterVersion,
                targetFacet: try facet.designFacetID,
                payload: payload,
                payloadDigest: payloadDigest,
                expectedWriteCount: writeCount
            )
            let budget = try DesignMutationPlanBudget(
                maximumSegmentCount: 1,
                maximumPayloadByteCount: UInt64(payload.count),
                maximumPreparedWriteCount: writeCount,
                maximumValidationReadCount: 1
            )
            let planDigest = try DesignMutationPlanDigest.plan(
                databaseID: handle.databaseID,
                baseRevision: base,
                designSchemaBundleDigest: snapshot.designSchemaBundleDigest,
                dependencyRootDigest: snapshot.dependencyRootDigest,
                semanticDependencyGraphDigest: snapshot.semanticDependencyGraphDigest,
                sourceEvidenceDigest: evidence,
                budget: budget,
                segments: [planSegment],
                using: SHA256ContentDigester()
            )
            let mutationPlan = DesignMutationPlan(
                databaseID: handle.databaseID,
                baseRevision: base,
                designSchemaBundleDigest: snapshot.designSchemaBundleDigest,
                dependencyRootDigest: snapshot.dependencyRootDigest,
                semanticDependencyGraphDigest: snapshot.semanticDependencyGraphDigest,
                sourceEvidenceDigest: evidence,
                budget: budget,
                segments: [planSegment],
                planDigest: planDigest
            )
            let operationID = try DesignDatabaseOperationID(rawValue: operation)
            let submission = DesignCommitSubmission(
                operationID: operationID,
                plan: mutationPlan,
                requestDigest: try DesignMutationPlanDigest.request(
                    operationID: operationID,
                    planDigest: planDigest,
                    using: SHA256ContentDigester()
                )
            )
            _ = await snapshot.close()
            return submission
        } catch {
            _ = await snapshot.close()
            throw error
        }
    }

    private func sourceRTLBinding(
        at revision: DesignRevisionReference,
        facetRoots: [DesignFacetRoot]
    ) throws -> LogicDatabaseFacetSourceBinding {
        let rtlFacetID = try LogicDatabaseFacet.rtl.designFacetID
        guard let root = facetRoots.first(where: {
            $0.facetID == rtlFacetID
        })?.digest else {
            throw TestFailure("The candidate revision has no RTL facet root.")
        }
        return try LogicDatabaseFacetSourceBinding(
            sourceRevision: revision,
            sourceFacet: .rtl,
            sourceRootDigest: root
        )
    }

    private func digest(_ value: String) throws -> ContentDigest {
        try SHA256ContentDigester().digest(data: Data(value.utf8))
    }
}

private struct TestFailure: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
