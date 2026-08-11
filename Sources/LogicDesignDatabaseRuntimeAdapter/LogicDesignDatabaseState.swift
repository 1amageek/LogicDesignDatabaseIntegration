import LogicIR
import LogicDesignDatabaseSchema
import PowerIntent

public struct LogicDesignDatabaseState: Sendable, Hashable, Codable {
    public let rtl: RTLDesign?
    public let gate: GateDesign?
    public let powerIntent: PowerIntentDesign?
    public let gateSourceRTL: LogicDatabaseFacetSourceBinding?
    public let powerIntentSourceRTL: LogicDatabaseFacetSourceBinding?
    public let invalidations: [LogicDatabaseFacetInvalidation]

    public init(
        rtl: RTLDesign?,
        gate: GateDesign?,
        powerIntent: PowerIntentDesign?,
        gateSourceRTL: LogicDatabaseFacetSourceBinding? = nil,
        powerIntentSourceRTL: LogicDatabaseFacetSourceBinding? = nil,
        invalidations: [LogicDatabaseFacetInvalidation] = []
    ) {
        self.rtl = rtl
        self.gate = gate
        self.powerIntent = powerIntent
        self.gateSourceRTL = gateSourceRTL
        self.powerIntentSourceRTL = powerIntentSourceRTL
        self.invalidations = invalidations
    }

    public var isSemanticallyCurrent: Bool {
        invalidations.isEmpty
    }
}
