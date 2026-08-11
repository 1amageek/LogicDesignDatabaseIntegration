import DesignDatabaseCore

public protocol LogicDesignDatabaseReading: Sendable {
    func readState(
        from snapshot: any DesignReadSnapshot,
        budget: LogicDatabaseReadBudget
    ) async throws -> LogicDesignDatabaseState
}
