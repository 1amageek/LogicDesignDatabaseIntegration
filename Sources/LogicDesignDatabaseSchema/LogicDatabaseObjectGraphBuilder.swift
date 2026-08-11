import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignDatabaseCore
import Foundation
import LogicIR
import PowerIntent

public struct LogicDatabaseObjectGraphBuilder: Sendable {
    public init() {}

    public func build(
        from importValue: LogicDatabaseImport,
        facetRootDigest: ContentDigest
    ) throws(LogicDatabaseSchemaError) -> LogicDatabaseObjectGraph {
        var builder = try Builder(
            facet: importValue.facet,
            facetRootDigest: facetRootDigest
        )
        switch importValue {
        case .rtl(let design):
            try builder.appendRTL(design)
        case .gate(let design, _):
            try builder.appendGate(design)
        case .powerIntent(let design, _):
            try builder.appendPowerIntent(design)
        }
        return try builder.finish()
    }
}

private extension LogicDatabaseObjectGraphBuilder {
    struct Builder {
        let facet: LogicDatabaseFacet
        let rootKey: LogicDatabaseStableObjectKey
        var objects: [LogicDatabaseObjectDescriptor]
        var relations: [LogicDatabaseRelationDescriptor] = []

        init(
            facet: LogicDatabaseFacet,
            facetRootDigest: ContentDigest
        ) throws(LogicDatabaseSchemaError) {
            self.facet = facet
            rootKey = try LogicDatabaseStableObjectKey(
                components: ["design"],
                facet: facet
            )
            do {
                objects = [
                    LogicDatabaseObjectDescriptor(
                        stableKey: rootKey,
                        kindID: try DesignEntityKindID(
                            rawValue: "\(facet.rawValue).design"
                        ),
                        contentDigest: facetRootDigest
                    ),
                ]
            } catch {
                throw .invalidObjectIdentity(
                    facet: facet,
                    reason: String(describing: error)
                )
            }
        }

        mutating func appendRTL(
            _ design: RTLDesign
        ) throws(LogicDatabaseSchemaError) {
            for (moduleIndex, module) in design.modules.enumerated() {
                let moduleKey = try appendObject(
                    module,
                    kind: "logic.rtl.module",
                    components: ["module", module.id],
                    parent: rootKey,
                    category: 1,
                    ordinal: moduleIndex
                )
                for (index, parameter) in module.parameters.enumerated() {
                    _ = try appendObject(
                        parameter,
                        kind: "logic.rtl.parameter",
                        components: moduleKey.components + ["parameter", parameter.id],
                        parent: moduleKey,
                        category: 1,
                        ordinal: index
                    )
                }
                for (index, port) in module.ports.enumerated() {
                    _ = try appendObject(
                        port,
                        kind: "logic.rtl.port",
                        components: moduleKey.components + ["port", port.id],
                        parent: moduleKey,
                        category: 2,
                        ordinal: index
                    )
                }
                for (index, signal) in module.signals.enumerated() {
                    _ = try appendObject(
                        signal,
                        kind: "logic.rtl.signal",
                        components: moduleKey.components + ["signal", signal.id],
                        parent: moduleKey,
                        category: 3,
                        ordinal: index
                    )
                }
                for (index, memory) in module.memories.enumerated() {
                    _ = try appendObject(
                        memory,
                        kind: "logic.rtl.memory",
                        components: moduleKey.components + ["memory", memory.id],
                        parent: moduleKey,
                        category: 4,
                        ordinal: index
                    )
                }
                for (index, assignment) in module.assignments.enumerated() {
                    _ = try appendObject(
                        assignment,
                        kind: "logic.rtl.assignment",
                        components: moduleKey.components + ["assignment", assignment.id],
                        parent: moduleKey,
                        category: 5,
                        ordinal: index
                    )
                }
                for (index, process) in module.processes.enumerated() {
                    _ = try appendObject(
                        process,
                        kind: "logic.rtl.process",
                        components: moduleKey.components + ["process", process.id],
                        parent: moduleKey,
                        category: 6,
                        ordinal: index
                    )
                }
                for (index, instance) in module.instances.enumerated() {
                    _ = try appendObject(
                        instance,
                        kind: "logic.rtl.instance",
                        components: moduleKey.components + ["instance", instance.id],
                        parent: moduleKey,
                        category: 7,
                        ordinal: index
                    )
                }
                for (index, generate) in module.generateBlocks.enumerated() {
                    let generateKey = try appendObject(
                        generate,
                        kind: "logic.rtl.generate-block",
                        components: moduleKey.components + ["generate", generate.id],
                        parent: moduleKey,
                        category: 8,
                        ordinal: index
                    )
                    for (childIndex, instance) in generate.instances.enumerated() {
                        _ = try appendObject(
                            instance,
                            kind: "logic.rtl.generate-instance",
                            components: generateKey.components + ["instance", instance.id],
                            parent: generateKey,
                            category: 1,
                            ordinal: childIndex
                        )
                    }
                    for (childIndex, assignment) in generate.assignments.enumerated() {
                        _ = try appendObject(
                            assignment,
                            kind: "logic.rtl.generate-assignment",
                            components: generateKey.components + ["assignment", assignment.id],
                            parent: generateKey,
                            category: 2,
                            ordinal: childIndex
                        )
                    }
                }
            }
        }

        mutating func appendGate(
            _ design: GateDesign
        ) throws(LogicDatabaseSchemaError) {
            for (moduleIndex, module) in design.modules.enumerated() {
                let moduleKey = try appendObject(
                    module,
                    kind: "logic.gate.module",
                    components: ["module", module.id],
                    parent: rootKey,
                    category: 1,
                    ordinal: moduleIndex
                )
                for (index, port) in module.ports.enumerated() {
                    _ = try appendObject(
                        port,
                        kind: "logic.gate.port",
                        components: moduleKey.components + ["port", port.id],
                        parent: moduleKey,
                        category: 1,
                        ordinal: index
                    )
                }
                for (index, cell) in module.cells.enumerated() {
                    let cellKey = try appendObject(
                        cell,
                        kind: "logic.gate.cell",
                        components: moduleKey.components + ["cell", cell.id],
                        parent: moduleKey,
                        category: 2,
                        ordinal: index
                    )
                    for (pinIndex, pin) in cell.pins.enumerated() {
                        _ = try appendObject(
                            pin,
                            kind: "logic.gate.pin",
                            components: cellKey.components + ["pin", pin.id],
                            parent: cellKey,
                            category: 1,
                            ordinal: pinIndex
                        )
                    }
                }
                for (index, net) in module.nets.enumerated() {
                    _ = try appendObject(
                        net,
                        kind: "logic.gate.net",
                        components: moduleKey.components + ["net", net.id],
                        parent: moduleKey,
                        category: 3,
                        ordinal: index
                    )
                }
            }
        }

        mutating func appendPowerIntent(
            _ design: PowerIntentDesign
        ) throws(LogicDatabaseSchemaError) {
            for (index, domain) in design.domains.enumerated() {
                _ = try appendObject(
                    domain,
                    kind: "logic.power-intent.domain",
                    components: ["domain", domain.id],
                    parent: rootKey,
                    category: 1,
                    ordinal: index
                )
            }
            for (index, supplySet) in design.supplySets.enumerated() {
                _ = try appendObject(
                    supplySet,
                    kind: "logic.power-intent.supply-set",
                    components: ["supply-set", supplySet.id],
                    parent: rootKey,
                    category: 2,
                    ordinal: index
                )
            }
            for (index, isolation) in design.isolationPolicies.enumerated() {
                _ = try appendObject(
                    isolation,
                    kind: "logic.power-intent.isolation",
                    components: ["isolation", isolation.id],
                    parent: rootKey,
                    category: 3,
                    ordinal: index
                )
            }
            for (index, levelShifter) in design.levelShifters.enumerated() {
                _ = try appendObject(
                    levelShifter,
                    kind: "logic.power-intent.level-shifter",
                    components: ["level-shifter", levelShifter.id],
                    parent: rootKey,
                    category: 4,
                    ordinal: index
                )
            }
            for (index, retention) in design.retentionPolicies.enumerated() {
                _ = try appendObject(
                    retention,
                    kind: "logic.power-intent.retention",
                    components: ["retention", retention.id],
                    parent: rootKey,
                    category: 5,
                    ordinal: index
                )
            }
            for (index, directive) in design.structuredDirectives.enumerated() {
                _ = try appendObject(
                    directive,
                    kind: "logic.power-intent.directive",
                    components: ["directive", directive.id],
                    parent: rootKey,
                    category: 6,
                    ordinal: index
                )
            }
        }

        mutating func appendObject<Value: Encodable>(
            _ value: Value,
            kind: String,
            components: [String],
            parent: LogicDatabaseStableObjectKey,
            category: UInt8,
            ordinal: Int
        ) throws(LogicDatabaseSchemaError) -> LogicDatabaseStableObjectKey {
            let key = try LogicDatabaseStableObjectKey(
                components: components,
                facet: facet
            )
            let kindID: DesignEntityKindID
            do {
                kindID = try DesignEntityKindID(rawValue: kind)
            } catch {
                throw .invalidObjectIdentity(
                    facet: facet,
                    reason: String(describing: error)
                )
            }
            objects.append(
                LogicDatabaseObjectDescriptor(
                    stableKey: key,
                    kindID: kindID,
                    contentDigest: try digest(value)
                )
            )
            try appendContainment(
                parent: parent,
                child: key,
                category: category,
                ordinal: ordinal
            )
            return key
        }

        mutating func appendContainment(
            parent: LogicDatabaseStableObjectKey,
            child: LogicDatabaseStableObjectKey,
            category: UInt8,
            ordinal: Int
        ) throws(LogicDatabaseSchemaError) {
            guard let persistedOrdinal = UInt64(exactly: ordinal) else {
                throw .invalidObjectIdentity(
                    facet: facet,
                    reason: "A hierarchy ordinal exceeds the supported range."
                )
            }
            var orderBytes = [category]
            withUnsafeBytes(of: persistedOrdinal.bigEndian) {
                orderBytes.append(contentsOf: $0)
            }
            do {
                relations.append(
                    LogicDatabaseRelationDescriptor(
                        stableKey: try LogicDatabaseStableObjectKey(
                            components: ["contains"] + child.components,
                            facet: facet
                        ),
                        family: .hierarchy,
                        ownerKey: parent,
                        relationKindID: try DesignRelationKindID(
                            rawValue: "logic.contains"
                        ),
                        targetKey: child,
                        orderKey: try DesignCanonicalKey(bytes: orderBytes),
                        attributesDigest: nil
                    )
                )
            } catch let error as LogicDatabaseSchemaError {
                throw error
            } catch {
                throw .invalidObjectIdentity(
                    facet: facet,
                    reason: String(describing: error)
                )
            }
        }

        func finish() throws(LogicDatabaseSchemaError) -> LogicDatabaseObjectGraph {
            try LogicDatabaseObjectGraph(
                facet: facet,
                objects: objects,
                relations: relations
            )
        }

        func digest<Value: Encodable>(
            _ value: Value
        ) throws(LogicDatabaseSchemaError) -> ContentDigest {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            do {
                let data = try encoder.encode(value)
                return try SHA256ContentDigester().digest(data: data)
            } catch {
                throw .encodingFailed(
                    facet: facet,
                    reason: String(describing: error)
                )
            }
        }
    }
}
