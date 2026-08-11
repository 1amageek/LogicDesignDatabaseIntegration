import CircuiteFoundation
import CircuiteFoundationCrypto
import DatabaseTypes
import DatabaseTypesFoundation
import Foundation

public struct LogicDatabaseCanonicalDocument: Sendable {
    public static let defaultPageByteCount = 64 * 1_024

    public let importValue: LogicDatabaseImport
    public let canonicalData: Data
    public let facetRootDigest: ContentDigest
    public let pages: [LogicDatabaseFacetPage]

    public init(
        importValue: LogicDatabaseImport,
        pageByteCount: Int = Self.defaultPageByteCount
    ) throws(LogicDatabaseSchemaError) {
        guard pageByteCount > 0 else {
            throw .invalidPageByteCount(pageByteCount)
        }
        let canonicalData = try LogicDatabaseCanonicalCodec.encode(importValue)
        let digest: ContentDigest
        do {
            digest = try SHA256ContentDigester().digest(data: canonicalData)
        } catch {
            throw .encodingFailed(
                facet: importValue.facet,
                reason: String(describing: error)
            )
        }
        let byteCount = canonicalData.count
        let pageCount = max(1, (byteCount + pageByteCount - 1) / pageByteCount)
        guard let persistedPageCount = UInt64(exactly: pageCount),
              let persistedByteCount = UInt64(exactly: byteCount) else {
            throw .pageCountOverflow
        }
        let owner = ByteString(retaining: canonicalData)
        var pages: [LogicDatabaseFacetPage] = []
        pages.reserveCapacity(pageCount)
        for pageIndex in 0..<pageCount {
            let lowerBound = pageIndex * pageByteCount
            let upperBound = min(byteCount, lowerBound + pageByteCount)
            guard let ordinal = UInt64(exactly: pageIndex) else {
                throw .pageCountOverflow
            }
            pages.append(
                LogicDatabaseFacetPage(
                    id: Self.pageID(ordinal),
                    facetID: importValue.facet.rawValue,
                    ordinal: ordinal,
                    pageCount: persistedPageCount,
                    documentByteCount: persistedByteCount,
                    documentDigest: digest.hexadecimalValue,
                    payload: owner[lowerBound..<upperBound]
                )
            )
        }
        self.importValue = importValue
        self.canonicalData = canonicalData
        self.facetRootDigest = digest
        self.pages = pages
    }

    public static func pageCount(
        forByteCount byteCount: Int,
        pageByteCount: Int = defaultPageByteCount
    ) throws(LogicDatabaseSchemaError) -> UInt64 {
        guard pageByteCount > 0 else {
            throw .invalidPageByteCount(pageByteCount)
        }
        let count = max(1, (byteCount + pageByteCount - 1) / pageByteCount)
        guard let result = UInt64(exactly: count) else {
            throw .pageCountOverflow
        }
        return result
    }

    /// Materializes pages from a Runtime-authenticated validation capsule.
    /// This method intentionally does not repeat domain semantic validation.
    public static func materializeValidated(
        canonicalData: Data,
        facet: LogicDatabaseFacet,
        pageByteCount: Int = defaultPageByteCount
    ) throws(LogicDatabaseSchemaError) -> (
        facetRootDigest: ContentDigest,
        pages: [LogicDatabaseFacetPage]
    ) {
        guard pageByteCount > 0 else {
            throw .invalidPageByteCount(pageByteCount)
        }
        let digest: ContentDigest
        do {
            digest = try SHA256ContentDigester().digest(data: canonicalData)
        } catch {
            throw .encodingFailed(
                facet: facet,
                reason: String(describing: error)
            )
        }
        let pageCount = max(
            1,
            (canonicalData.count + pageByteCount - 1) / pageByteCount
        )
        guard let persistedPageCount = UInt64(exactly: pageCount),
              let persistedByteCount = UInt64(exactly: canonicalData.count) else {
            throw .pageCountOverflow
        }
        let owner = ByteString(retaining: canonicalData)
        var pages: [LogicDatabaseFacetPage] = []
        pages.reserveCapacity(pageCount)
        for pageIndex in 0..<pageCount {
            guard let ordinal = UInt64(exactly: pageIndex) else {
                throw .pageCountOverflow
            }
            let lowerBound = pageIndex * pageByteCount
            let upperBound = min(canonicalData.count, lowerBound + pageByteCount)
            pages.append(
                LogicDatabaseFacetPage(
                    id: pageID(ordinal),
                    facetID: facet.rawValue,
                    ordinal: ordinal,
                    pageCount: persistedPageCount,
                    documentByteCount: persistedByteCount,
                    documentDigest: digest.hexadecimalValue,
                    payload: owner[lowerBound..<upperBound]
                )
            )
        }
        return (digest, pages)
    }

    private static func pageID(_ ordinal: UInt64) -> String {
        let rawValue = String(ordinal)
        return String(repeating: "0", count: 20 - rawValue.count) + rawValue
    }
}
