import CircuiteFoundation
import DesignDatabaseCore

public enum LogicDatabaseFacet: String, Sendable, Hashable, Codable, CaseIterable {
    case rtl = "logic.rtl"
    case gate = "logic.gate"
    case powerIntent = "logic.power-intent"

    public var designFacetID: DesignFacetID {
        get throws {
            try DesignFacetID(rawValue: rawValue)
        }
    }
}
