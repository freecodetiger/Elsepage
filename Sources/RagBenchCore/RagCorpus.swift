import CryptoKit
import Foundation
import LibraryCore
import ReaderCore
import RetrievalCore

/// The on-disk shape of the RAG corpus.
///
/// One definition, shared by the two halves of the pipeline that are otherwise
/// forced apart: the geometry snapshot runs inside the Xcode/iOS test bundle
/// (Readium only builds for iOS) and the ablation runs under `swift test`. Both
/// talk to this file, so the dump format cannot drift between producer and
/// consumer.
///
/// A corpus book is identified by a stable key ("book-01"), never by a fresh
/// UUID. `BookID` feeds the content-addressed block and chunk ids, so a random
/// book id would produce a different corpus on every run.
public enum RagCorpusBook {
    public static func bookID(for key: String) -> BookID {
        BookID(rawValue: uuid(from: "ragcorpus|book|\(key)"))
    }

    /// SHA-256 truncated to 16 bytes, with the RFC-4122 variant/version bits set
    /// so the result is a well-formed v5-shaped UUID rather than arbitrary bytes.
    public static func uuid(from seed: String) -> UUID {
        var digest = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }
}

/// A persisted chunk, verbatim. The Xcode snapshot writes these; the SPM side
/// reads them back without re-deriving any geometry.
public struct RagChunkRecord: Codable, Hashable, Sendable {
    public var id: String
    public var bookKey: String
    public var bookID: UUID
    public var resourceHref: String
    public var chapterID: String?
    public var chapterTitle: String?
    public var sectionID: String?
    public var sectionTitle: String?
    public var resourceOrdinal: Int
    public var ordinal: Int
    public var text: String
    public var normalizedText: String
    public var startLocator: BookLocator
    public var endLocator: BookLocator
    public var sourceBlockIDs: [String]
    public var role: String
    public var parentID: String?

    public init(
        id: String, bookKey: String, bookID: UUID, resourceHref: String,
        chapterID: String?, chapterTitle: String?, sectionID: String?, sectionTitle: String?,
        resourceOrdinal: Int, ordinal: Int, text: String, normalizedText: String,
        startLocator: BookLocator, endLocator: BookLocator, sourceBlockIDs: [String],
        role: String, parentID: String?
    ) {
        self.id = id; self.bookKey = bookKey; self.bookID = bookID
        self.resourceHref = resourceHref
        self.chapterID = chapterID; self.chapterTitle = chapterTitle
        self.sectionID = sectionID; self.sectionTitle = sectionTitle
        self.resourceOrdinal = resourceOrdinal; self.ordinal = ordinal
        self.text = text; self.normalizedText = normalizedText
        self.startLocator = startLocator; self.endLocator = endLocator
        self.sourceBlockIDs = sourceBlockIDs
        self.role = role; self.parentID = parentID
    }

    public func chunk() -> BookChunk {
        BookChunk(
            id: .init(rawValue: id), bookID: BookID(rawValue: bookID),
            resourceHref: resourceHref,
            chapterID: chapterID, chapterTitle: chapterTitle,
            sectionID: sectionID, sectionTitle: sectionTitle,
            resourceOrdinal: resourceOrdinal, ordinal: ordinal,
            text: text, normalizedText: normalizedText,
            startLocator: startLocator, endLocator: endLocator,
            sourceBlockIDs: sourceBlockIDs.map { .init(rawValue: $0) },
            role: BookChunkRole(rawValue: role) ?? .parent,
            parentID: parentID.map { .init(rawValue: $0) }
        )
    }
}

extension RagChunkRecord {
    public init(_ chunk: BookChunk, bookKey: String) {
        self.init(
            id: chunk.id.rawValue, bookKey: bookKey, bookID: chunk.bookID.rawValue,
            resourceHref: chunk.resourceHref,
            chapterID: chunk.chapterID, chapterTitle: chunk.chapterTitle,
            sectionID: chunk.sectionID, sectionTitle: chunk.sectionTitle,
            resourceOrdinal: chunk.resourceOrdinal, ordinal: chunk.ordinal,
            text: chunk.text, normalizedText: chunk.normalizedText,
            startLocator: chunk.startLocator, endLocator: chunk.endLocator,
            sourceBlockIDs: chunk.sourceBlockIDs.map(\.rawValue),
            role: chunk.role.rawValue, parentID: chunk.parentID?.rawValue
        )
    }
}

public enum RagCorpusIO {
    /// Sorted keys and no escaped slashes so two runs produce byte-identical
    /// files and a diff means a real change.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func encodeLines<T: Encodable>(_ records: [T]) throws -> Data {
        let encoder = encoder()
        var out = Data()
        for record in records {
            out.append(try encoder.encode(record))
            out.append(0x0A)
        }
        return out
    }

    public static func decodeLines<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        let decoder = JSONDecoder()
        return try data.split(separator: 0x0A).map { try decoder.decode(T.self, from: Data($0)) }
    }

    /// Content hash, so a report can name the exact corpus and query set it
    /// describes instead of trusting that they have not moved since.
    public static func sha256Hex(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
}
