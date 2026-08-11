import CircuiteFoundation
import Foundation
import LogicIR
import PowerIntent

public enum LogicDatabaseCanonicalCodec {
    public static func encode(
        _ importValue: LogicDatabaseImport
    ) throws(LogicDatabaseSchemaError) -> Data {
        try validate(importValue)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            switch importValue {
            case .rtl(let design):
                return try encoder.encode(design)
            case .gate(let design, let sourceRTL):
                return try encoder.encode(
                    DerivedFacetDocument(
                        design: design,
                        sourceRTL: sourceRTL
                    )
                )
            case .powerIntent(let design, let sourceRTL):
                return try encoder.encode(
                    DerivedFacetDocument(
                        design: design,
                        sourceRTL: sourceRTL
                    )
                )
            }
        } catch {
            throw .encodingFailed(
                facet: importValue.facet,
                reason: String(describing: error)
            )
        }
    }

    public static func decode(
        _ data: Data,
        facet: LogicDatabaseFacet,
        requireCanonicalEncoding: Bool = true
    ) throws(LogicDatabaseSchemaError) -> LogicDatabaseImport {
        let decoder = JSONDecoder()
        let value: LogicDatabaseImport
        do {
            switch facet {
            case .rtl:
                let design = try decoder.decode(RTLDesign.self, from: data)
                guard design.schemaVersion == RTLDesign.currentSchemaVersion else {
                    throw LogicDatabaseSchemaError.unsupportedDomainSchema(
                        facet: facet,
                        version: design.schemaVersion
                    )
                }
                value = .rtl(design)
            case .gate:
                let document = try decoder.decode(
                    DerivedFacetDocument<GateDesign>.self,
                    from: data
                )
                let design = document.design
                guard design.schemaVersion == GateDesign.currentSchemaVersion else {
                    throw LogicDatabaseSchemaError.unsupportedDomainSchema(
                        facet: facet,
                        version: design.schemaVersion
                    )
                }
                value = .gate(design, sourceRTL: document.sourceRTL)
            case .powerIntent:
                let document = try decoder.decode(
                    DerivedFacetDocument<PowerIntentDesign>.self,
                    from: data
                )
                value = .powerIntent(
                    document.design,
                    sourceRTL: document.sourceRTL
                )
            }
        } catch let error as LogicDatabaseSchemaError {
            throw error
        } catch {
            throw .decodingFailed(facet: facet, reason: String(describing: error))
        }
        try validate(value)
        if requireCanonicalEncoding {
            let canonical = try encode(value)
            guard canonical == data else {
                throw .nonCanonicalPayload(facet: facet)
            }
        }
        return value
    }

    private static func validate(
        _ importValue: LogicDatabaseImport
    ) throws(LogicDatabaseSchemaError) {
        switch importValue {
        case .rtl(let design):
            let result = LogicDesignValidator().validate(design)
            guard result.isValid, !result.hasErrors else {
                throw .invalidDesign(
                    facet: .rtl,
                    diagnostics: result.diagnostics.map(\.engineDiagnostic)
                )
            }
        case .gate(let design, let sourceRTL):
            try sourceRTL.validate()
            let result = LogicDesignValidator().validate(design)
            guard result.isValid, !result.hasErrors else {
                throw .invalidDesign(
                    facet: .gate,
                    diagnostics: result.diagnostics.map(\.engineDiagnostic)
                )
            }
        case .powerIntent(let design, let sourceRTL):
            try sourceRTL.validate()
            let result = PowerIntentValidator().validate(design)
            guard result.isValid else {
                throw .invalidDesign(
                    facet: .powerIntent,
                    diagnostics: result.diagnostics.map(\.engineDiagnostic)
                )
            }
        }
    }

    private struct DerivedFacetDocument<Design>: Sendable, Codable
    where Design: Sendable & Codable {
        let design: Design
        let sourceRTL: LogicDatabaseFacetSourceBinding
    }
}
