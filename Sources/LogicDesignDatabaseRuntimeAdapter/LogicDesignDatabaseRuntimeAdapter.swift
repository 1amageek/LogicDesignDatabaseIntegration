import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore
import DesignDatabaseRuntime
import Foundation
import LogicDesignDatabaseSchema

public struct LogicDesignDatabaseRuntimeAdapter:
    DesignDatabaseRuntimeMutationAdapter,
    Sendable
{
    public let schemaID: DesignSchemaID
    public let schemaVersion = SchemaVersion.v1
    public let adapterVersion = LogicDesignDatabaseSchema.adapterVersion
    public let supportedFacets: Set<DesignFacetID>

    public init() throws {
        schemaID = try LogicDesignDatabaseSchema.schemaID
        var facets = Set<DesignFacetID>()
        for facet in LogicDatabaseFacet.allCases {
            facets.insert(try facet.designFacetID)
        }
        supportedFacets = facets
    }

    public func contribution() throws -> DesignDatabaseRuntimeContribution {
        let bindingDigest = try SHA256ContentDigester().digest(
            data: Data(LogicDesignDatabaseSchema.bindingManifest.utf8)
        )
        return try DesignDatabaseRuntimeContribution(
            id: DesignDatabaseRuntimeContributionID(
                "lsi.logic-design-database"
            ),
            designSchemaMember: DesignSchemaBundleMember(
                schemaID: schemaID,
                version: schemaVersion,
                canonicalDigest: bindingDigest
            ),
            bindingDigest: bindingDigest,
            entities: [try LogicDatabaseFacetPage.schemaEntity],
            entityRuntimes: [
                try DatabaseFrameworkRuntime.entity(
                    LogicDatabaseFacetPage.self
                ),
            ],
            mutationAdapter: self,
            physicalWriteReclaimers: [self]
        )
    }

    public func validate(
        _ segment: DesignMutationPlanSegment,
        in context: DesignDatabaseRuntimeMutationValidation
    ) async throws(DesignDatabaseRuntimeMutationAdapterError)
        -> DesignDatabaseRuntimeValidatedMutation {
        guard segment.schemaID == schemaID,
              segment.schemaVersion == schemaVersion,
              segment.adapterVersion == adapterVersion,
              let facet = LogicDatabaseFacet(
                rawValue: segment.targetFacet.rawValue
              ) else {
            throw .invalidPayload(reason: "The logic segment binding is not registered.")
        }
        let payload: LogicDatabaseMutationPayload
        do {
            payload = try LogicDatabaseMutationPayloadCodec.decode(
                Data(segment.payload)
            )
        } catch {
            do {
                _ = try LogicDatabaseCanonicalCodec.decode(
                    Data(segment.payload),
                    facet: facet
                )
            } catch LogicDatabaseSchemaError.invalidDesign(_, let diagnostics) {
                throw .validationFailed(
                    diagnostics: diagnostics,
                    diagnosticsDigest: segment.payloadDigest
                )
            } catch {
                throw .invalidPayload(reason: String(describing: error))
            }
            throw .invalidPayload(
                reason: "A canonical logic document must be compiled with its exact object identity plan."
            )
        }
        guard payload.facet == facet else {
            throw .invalidPayload(
                reason: "The logic mutation payload facet does not match its segment."
            )
        }
        let importValue: LogicDatabaseImport
        do {
            importValue = try LogicDatabaseCanonicalCodec.decode(
                Data(payload.canonicalDocument),
                facet: facet
            )
        } catch LogicDatabaseSchemaError.invalidDesign(_, let diagnostics) {
            throw .validationFailed(
                diagnostics: diagnostics,
                diagnosticsDigest: segment.payloadDigest
            )
        } catch {
            throw .invalidPayload(reason: String(describing: error))
        }
        if let sourceRTL = importValue.sourceRTLBinding {
            try validateSourceRTLBinding(
                sourceRTL,
                targetFacet: facet,
                context: context,
                diagnosticsDigest: segment.payloadDigest
            )
        }
        let document: LogicDatabaseCanonicalDocument
        do {
            document = try LogicDatabaseCanonicalDocument(
                importValue: importValue
            )
        } catch LogicDatabaseSchemaError.invalidDesign(_, let diagnostics) {
            throw .validationFailed(
                diagnostics: diagnostics,
                diagnosticsDigest: segment.payloadDigest
            )
        } catch {
            throw .invalidPayload(reason: String(describing: error))
        }
        guard document.pages.count == segment.expectedWriteCount else {
            throw .invalidPayload(
                reason: "The declared write count does not match the canonical page count."
            )
        }
        let observedPayloadDigest: ContentDigest
        do {
            observedPayloadDigest = try DesignMutationPlanDigest.payload(
                segment.payload,
                using: SHA256ContentDigester()
            )
        } catch {
            throw .invalidPayload(reason: String(describing: error))
        }
        guard observedPayloadDigest == segment.payloadDigest else {
            throw .invalidPayload(
                reason: "The canonical logic mutation payload digest does not match the segment."
            )
        }
        let graph: LogicDatabaseObjectGraph
        do {
            graph = try LogicDatabaseObjectGraphBuilder().build(
                from: importValue,
                facetRootDigest: document.facetRootDigest
            )
            try await LogicDatabaseProjectionMutationBuilder().validate(
                payload: payload,
                graph: graph,
                context: context
            )
        } catch {
            throw .invalidPayload(reason: String(describing: error))
        }
        return DesignDatabaseRuntimeValidatedMutation(
            segmentID: segment.id,
            materializationPayload: segment.payload
        )
    }

    public func materializeValidatedMutation(
        _ validation: DesignDatabaseRuntimeValidatedMutationRecord,
        for segment: DesignMutationPlanSegment,
        in context: DesignDatabaseRuntimeMutationRestoration
    ) throws(DesignDatabaseRuntimeMutationAdapterError)
        -> any DesignDatabaseRuntimePreparedMutation {
        _ = context
        do {
            let payload = try LogicDatabaseMutationPayloadCodec.decode(
                Data(validation.materializationPayload)
            )
            let materialization = try LogicDatabaseCanonicalDocument
                .materializeValidated(
                    canonicalData: Data(payload.canonicalDocument),
                    facet: payload.facet
                )
            guard UInt64(materialization.pages.count)
                    == segment.expectedWriteCount else {
                throw DesignDatabaseRuntimeMutationAdapterError.invalidPayload(
                    reason: "The materialized logic page count does not match its segment."
                )
            }
            let projectionChanges = try LogicDatabaseProjectionMutationBuilder()
                .materialize(
                    payload: payload,
                    segmentID: validation.segmentID,
                    context: context
                )
            return LogicDatabasePreparedMutation(
                segmentID: validation.segmentID,
                pages: materialization.pages,
                facetRootDigest: materialization.facetRootDigest,
                changeContributionDigest: materialization.facetRootDigest,
                projectionChanges: projectionChanges
            )
        } catch let error as DesignDatabaseRuntimeMutationAdapterError {
            throw error
        } catch {
            throw .invalidPayload(
                reason: "The validated logic input could not be materialized: \(error)"
            )
        }
    }

    private func validateSourceRTLBinding(
        _ binding: LogicDatabaseFacetSourceBinding,
        targetFacet: LogicDatabaseFacet,
        context: DesignDatabaseRuntimeMutationValidation,
        diagnosticsDigest: ContentDigest
    ) throws(DesignDatabaseRuntimeMutationAdapterError) {
        guard binding.sourceRevision == context.baseRevision else {
            throw .validationFailed(
                diagnostics: [
                    DesignDiagnostic(
                        code: .trusted("LOGIC_SOURCE_RTL_REVISION_MISMATCH"),
                        severity: .error,
                        summary: "The derived logic facet is not bound to the exact base revision.",
                        detail: "Target \(targetFacet.rawValue) binds \(binding.sourceRevision.revisionID.description), but the exact base is \(context.baseRevision.revisionID.description)."
                    ),
                ],
                diagnosticsDigest: diagnosticsDigest
            )
        }
        let rtlFacetID: DesignFacetID
        do {
            rtlFacetID = try LogicDatabaseFacet.rtl.designFacetID
        } catch {
            throw .invalidPayload(reason: String(describing: error))
        }
        guard let actualRoot = context.baseFacetRoots.first(where: {
            $0.facetID == rtlFacetID
        })?.digest else {
            throw .validationFailed(
                diagnostics: [
                    DesignDiagnostic(
                        code: .trusted("LOGIC_SOURCE_RTL_MISSING"),
                        severity: .error,
                        summary: "The exact base revision has no canonical RTL facet.",
                        detail: "Target \(targetFacet.rawValue) requires an RTL source root."
                    ),
                ],
                diagnosticsDigest: diagnosticsDigest
            )
        }
        guard actualRoot == binding.sourceRootDigest else {
            throw .validationFailed(
                diagnostics: [
                    DesignDiagnostic(
                        code: .trusted("LOGIC_SOURCE_RTL_ROOT_MISMATCH"),
                        severity: .error,
                        summary: "The derived logic facet is stale for the exact RTL source root.",
                        detail: "Expected \(binding.sourceRootDigest.hexadecimalValue), actual \(actualRoot.hexadecimalValue)."
                    ),
                ],
                diagnosticsDigest: diagnosticsDigest
            )
        }
    }
}
