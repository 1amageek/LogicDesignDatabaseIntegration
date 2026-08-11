import LogicIR
import PowerIntent

public enum LogicDatabaseImport: Sendable, Hashable {
    case rtl(RTLDesign)
    case gate(
        GateDesign,
        sourceRTL: LogicDatabaseFacetSourceBinding
    )
    case powerIntent(
        PowerIntentDesign,
        sourceRTL: LogicDatabaseFacetSourceBinding
    )

    public var facet: LogicDatabaseFacet {
        switch self {
        case .rtl:
            return .rtl
        case .gate:
            return .gate
        case .powerIntent:
            return .powerIntent
        }
    }

    public var sourceRTLBinding: LogicDatabaseFacetSourceBinding? {
        switch self {
        case .rtl:
            nil
        case .gate(_, let sourceRTL), .powerIntent(_, let sourceRTL):
            sourceRTL
        }
    }
}
