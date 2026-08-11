import CircuiteFoundation
import DesignDatabaseCore

public enum LogicDesignDatabaseSchema {
    public static let adapterVersion = "3.0.0"
    public static let bindingManifest = """
    lsi.logic-design-database-schema/v3
    entity=LogicDatabaseFacetPage
    directory=design-database/logic-facets/{facetID}/{documentDigest}/pages
    fields=id,facetID,ordinal,pageCount,documentByteCount,documentDigest,payload
    facets=logic.rtl,logic.gate,logic.power-intent
    derivedFacetSourceBinding=exact-base-revision+logic.rtl+facet-root
    objectIdentity=exact-base-name-projection+runtime-reserved-identity
    objectKinds=rtl-design-objects,gate-design-objects,power-intent-objects
    relationKinds=logic.contains
    projectionFamilies=entity,name,hierarchy
    pageByteCount=65536
    """

    public static var schemaID: DesignSchemaID {
        get throws {
            try DesignSchemaID(rawValue: "lsi.logic-design")
        }
    }
}
