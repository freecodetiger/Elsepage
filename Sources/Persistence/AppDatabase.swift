import Foundation
import GRDB
import ReaderCore

public final class AppDatabase: @unchecked Sendable {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public convenience init(path: String) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }
        try self.init(writer: DatabaseQueue(path: path, configuration: configuration))
    }

    public static func inMemory() throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return try AppDatabase(writer: DatabaseQueue(configuration: configuration))
    }

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_reader_foundation") { db in
            try db.create(table: "books") { t in
                t.column("id", .text).primaryKey()
                t.column("fingerprint", .text).notNull().unique()
                t.column("title", .text).notNull()
                t.column("author", .text)
                t.column("fileName", .text).notNull().unique()
                t.column("fileSize", .integer).notNull()
                t.column("importedAt", .datetime).notNull()
                t.column("lastOpenedAt", .datetime)
            }
            try db.create(table: "readingPositions") { t in
                t.column("bookID", .text).primaryKey().references("books", onDelete: .cascade)
                Self.addLocatorColumns(to: t)
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "highlights") { t in
                t.column("id", .text).primaryKey()
                t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                Self.addLocatorColumns(to: t)
                t.column("color", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "notes") { t in
                t.column("id", .text).primaryKey()
                t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                t.column("highlightID", .text).references("highlights", onDelete: .setNull)
                Self.addLocatorColumns(to: t)
                t.column("body", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2_reader_preferences") { db in
            try db.create(table: "readerPreferences") { t in
                t.column("bookID", .text).primaryKey().references("books", onDelete: .cascade)
                t.column("theme", .text).notNull()
                t.column("fontSize", .double).notNull()
                t.column("lineHeight", .double).notNull()
                t.column("pageMargins", .double).notNull()
                t.column("readingMode", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v3_reflection_loop") { db in
            try db.create(table: "readingSessions") { t in
                t.column("id", .text).primaryKey()
                t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                Self.addLocatorColumns(to: t, prefix: "start")
                Self.addOptionalLocatorColumns(to: t, prefix: "end")
                t.column("highlightCount", .integer).notNull().defaults(to: 0)
                t.column("noteCount", .integer).notNull().defaults(to: 0)
                t.column("agentDiscussionCount", .integer).notNull().defaults(to: 0)
                t.check(sql: "highlightCount >= 0 AND noteCount >= 0 AND agentDiscussionCount >= 0")
                t.check(sql: "endedAt IS NULL OR endedAt >= startedAt")
            }
            try db.create(table: "reflections") { t in
                t.column("id", .text).primaryKey()
                t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                t.column("sessionID", .text).indexed().references("readingSessions", onDelete: .setNull)
                t.column("originalText", .text).notNull()
                t.column("inputKind", .text).notNull()
                t.column("audioFileName", .text)
                t.column("createdAt", .datetime).notNull().indexed()
                t.check(sql: "length(trim(originalText)) > 0")
                t.check(sql: "inputKind IN ('text', 'voiceTranscript')")
            }
            try db.create(table: "reflectionMessages") { t in
                t.column("id", .text).primaryKey()
                t.column("reflectionID", .text).notNull().indexed().references("reflections", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.check(sql: "role IN ('agent', 'userFollowUp')")
            }
            try db.create(table: "reflectionHighlights") { t in
                t.column("reflectionID", .text).notNull().references("reflections", onDelete: .cascade)
                t.column("highlightID", .text).notNull().references("highlights", onDelete: .cascade)
                t.primaryKey(["reflectionID", "highlightID"])
            }
        }
        migrator.registerMigration("v4_reflection_provenance") { db in
            try db.rename(table: "reflectionMessages", to: "reflectionMessagesV3")
            try db.drop(index: "reflectionMessages_on_reflectionID")
            try db.create(table: "reflectionMessages") { t in
                t.column("id", .text).primaryKey()
                t.column("reflectionID", .text).notNull().indexed().references("reflections", onDelete: .cascade)
                t.column("author", .text).notNull()
                t.column("source", .text).notNull()
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.check(sql: "(author = 'user' AND source = 'userInput') OR (author = 'agent' AND source = 'agentGenerated')")
            }
            try db.execute(sql: """
                INSERT INTO reflectionMessages (id, reflectionID, author, source, content, createdAt)
                SELECT id, reflectionID,
                       CASE role WHEN 'userFollowUp' THEN 'user' ELSE 'agent' END,
                       CASE role WHEN 'userFollowUp' THEN 'userInput' ELSE 'agentGenerated' END,
                       content, createdAt
                FROM reflectionMessagesV3
                """)
            try db.drop(table: "reflectionMessagesV3")

            try db.create(table: "reflectionEvidence") { t in
                t.column("id", .text).primaryKey()
                t.column("reflectionID", .text).notNull().indexed().references("reflections", onDelete: .cascade)
                t.column("sourceType", .text).notNull()
                t.column("sourceID", .text)
                Self.addOptionalLocatorColumns(to: t, prefix: "")
                t.column("createdAt", .datetime).notNull()
                t.check(sql: "sourceType IN ('bookLocator', 'highlight', 'note', 'readingSession')")
                t.check(sql: "sourceID IS NOT NULL OR locatorJSON IS NOT NULL")
                t.check(sql: "(locatorJSON IS NULL AND href IS NULL) OR (locatorJSON IS NOT NULL AND href IS NOT NULL)")
            }
        }
        migrator.registerMigration("v5_model_provider_configuration") { db in
            try db.create(table: "providerConfigurations") { t in
                t.column("id", .text).primaryKey()
                t.column("provider", .text).notNull()
                t.column("baseURL", .text).notNull()
                t.column("modelID", .text).notNull()
                t.column("secretReference", .text).notNull()
                t.column("streamingEnabled", .boolean).notNull()
                t.check(sql: "provider IN ('openAI', 'openAICompatible')")
                t.check(sql: "length(trim(modelID)) > 0")
            }
        }
        migrator.registerMigration("v6_reflection_connections") { db in
            try db.create(table: "reflectionConnections") { t in
                t.column("id", .text).primaryKey()
                t.column("reflectionID", .text).notNull().indexed().references("reflections", onDelete: .cascade)
                t.column("sourceReflectionID", .text).notNull().indexed().references("reflections", onDelete: .cascade)
                t.column("relevance", .double).notNull()
                t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["reflectionID", "sourceReflectionID"])
                t.check(sql: "reflectionID <> sourceReflectionID")
                t.check(sql: "relevance >= 0 AND relevance <= 1")
            }
        }
        migrator.registerMigration("v7_local_book_retrieval") { db in
            try db.create(table: "bookIndexJobs") { t in
                t.column("bookID", .text).notNull().references("books", onDelete: .cascade)
                t.column("indexVersion", .integer).notNull()
                t.column("state", .text).notNull()
                t.column("nextResourceOrdinal", .integer).notNull().defaults(to: 0)
                t.column("lastError", .text)
                t.column("updatedAt", .datetime).notNull()
                t.primaryKey(["bookID", "indexVersion"])
                t.check(sql: "state IN ('pending','extracting','lexicalReady','embedding','ready','failed')")
            }
            try db.create(table: "bookChunks") { t in
                t.column("id", .text).primaryKey()
                t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                t.column("indexVersion", .integer).notNull()
                t.column("resourceHref", .text).notNull()
                t.column("chapterID", .text); t.column("chapterTitle", .text)
                t.column("sectionID", .text); t.column("sectionTitle", .text)
                t.column("resourceOrdinal", .integer).notNull()
                t.column("ordinal", .integer).notNull()
                t.column("text", .text).notNull()
                t.column("normalizedText", .text).notNull()
                t.column("startLocatorJSON", .blob).notNull(); t.column("endLocatorJSON", .blob).notNull()
                t.column("startHref", .text).notNull(); t.column("endHref", .text).notNull()
                t.column("startProgression", .double); t.column("endProgression", .double)
                t.column("startTotalProgression", .double); t.column("endTotalProgression", .double)
                t.column("sourceBlockIDsJSON", .blob).notNull()
                t.uniqueKey(["bookID", "indexVersion", "resourceOrdinal", "ordinal"])
            }
            try db.create(table: "bookChapters") { t in
                t.column("bookID", .text).notNull().references("books", onDelete: .cascade)
                t.column("indexVersion", .integer).notNull(); t.column("id", .text).notNull()
                t.column("title", .text); t.column("resourceHref", .text).notNull(); t.column("ordinal", .integer).notNull()
                t.primaryKey(["bookID", "indexVersion", "id"])
            }
            try db.create(table: "bookSections") { t in
                t.column("bookID", .text).notNull().references("books", onDelete: .cascade)
                t.column("indexVersion", .integer).notNull(); t.column("id", .text).notNull()
                t.column("chapterID", .text); t.column("title", .text); t.column("ordinal", .integer).notNull()
                t.primaryKey(["bookID", "indexVersion", "id"])
            }
            try db.create(table: "bookTextBlocks") { t in
                t.column("id", .text).primaryKey(); t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                t.column("indexVersion", .integer).notNull(); t.column("resourceHref", .text).notNull()
                t.column("chapterID", .text); t.column("sectionID", .text)
                t.column("resourceOrdinal", .integer).notNull(); t.column("ordinal", .integer).notNull(); t.column("text", .text).notNull()
                t.column("startLocatorJSON", .blob).notNull(); t.column("endLocatorJSON", .blob).notNull()
                t.column("startHref", .text).notNull(); t.column("endHref", .text).notNull()
                t.column("startProgression", .double); t.column("endProgression", .double)
                t.uniqueKey(["bookID", "indexVersion", "resourceOrdinal", "ordinal"])
            }
            // Trigram supports CJK substring search while remaining useful for exact
            // English phrases. Query construction falls back for very short terms.
            try db.execute(sql: "CREATE VIRTUAL TABLE bookChunksFTS USING fts5(chunkID UNINDEXED, bookID UNINDEXED, normalizedText, tokenize='trigram')")
            try db.execute(sql: """
                CREATE TRIGGER bookChunks_after_delete AFTER DELETE ON bookChunks BEGIN
                    DELETE FROM bookChunksFTS WHERE chunkID = old.id;
                END
                """)
            try db.create(table: "bookChunkEmbeddings") { t in
                t.column("chunkID", .text).notNull().references("bookChunks", onDelete: .cascade)
                t.column("model", .text).notNull()
                t.column("dimensions", .integer).notNull()
                t.column("vector", .blob).notNull()
                t.primaryKey(["chunkID", "model"])
                t.check(sql: "dimensions > 0")
            }
        }
        migrator.registerMigration("v8_agent_citations") { db in
            // ifNotExists keeps the migration safe to re-run after the v8_pending_*
            // → v8/v9/v10 renumbering, so databases created during development upgrade
            // instead of needing to be deleted.
            try db.create(table: "agentResponseEvidence", ifNotExists: true) { t in
                t.column("messageID", .text).notNull().references("reflectionMessages", onDelete: .cascade)
                t.column("id", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("sourceID", .text).notNull()
                t.column("bookID", .text).notNull().references("books", onDelete: .cascade)
                t.column("title", .text)
                t.column("excerpt", .text).notNull()
                Self.addOptionalLocatorColumns(to: t, prefix: "")
                t.primaryKey(["messageID", "id"])
                t.check(sql: "kind IN ('nearbyPassage','bookPassage','pastReflection')")
                t.check(sql: "length(trim(excerpt)) > 0")
                t.check(sql: "(locatorJSON IS NULL AND href IS NULL) OR (locatorJSON IS NOT NULL AND href IS NOT NULL)")
            }
            try db.create(table: "agentCitations", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("messageID", .text).notNull().references("reflectionMessages", onDelete: .cascade)
                t.column("evidenceID", .text).notNull()
                t.column("marker", .text).notNull()
                t.foreignKey(["messageID", "evidenceID"], references: "agentResponseEvidence", columns: ["messageID", "id"], onDelete: .cascade)
                t.uniqueKey(["messageID", "evidenceID"])
            }
        }

        // P0-3 Router observability. Derives only: plan summary, statistics,
        // durations, evidence IDs, token usage and fallback cause live inside
        // the encoded `ContextPlanTrace`; no raw user text or Reflection body.
        // Numbering is re-sequenced by the coordinator at merge time.
        migrator.registerMigration("v9_routing_trace") { db in
            try db.create(table: "routingTraces", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("reflectionID", .text).notNull().indexed().references("reflections", onDelete: .cascade)
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("traceJSON", .blob).notNull()
            }
        }

        // P0-5 Journal. Stores derived journal snapshots (thoughts, agent
        // questions, citations, memory-change summaries) keyed by reflection.
        // Numbering is re-sequenced by the coordinator at merge time.
        migrator.registerMigration("v10_journal") { db in
            try db.create(table: "journalThoughts", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("reflectionID", .text).notNull().indexed().references("reflections", onDelete: .cascade)
                t.column("messageID", .text).notNull()
                t.column("thought", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.check(sql: "length(trim(thought)) > 0")
            }
            try db.create(table: "agentQuestions", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("reflectionID", .text).notNull().indexed().references("reflections", onDelete: .cascade)
                t.column("messageID", .text).notNull()
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("status", .text).notNull().defaults(to: "open")
                t.column("answeredByMessageID", .text)
                t.check(sql: "status IN ('open', 'answered')")
                t.check(sql: "length(trim(text)) > 0")
            }
            try db.create(table: "reflectionCitations", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("reflectionID", .text).notNull().indexed().references("reflections", onDelete: .cascade)
                t.column("messageID", .text).notNull()
                t.column("sourceType", .text).notNull()
                t.column("sourceID", .text)
                t.column("bookID", .text).notNull().references("books", onDelete: .cascade)
                Self.addOptionalLocatorColumns(to: t, prefix: "")
                t.column("title", .text)
                t.column("excerpt", .text)
                t.column("createdAt", .datetime).notNull()
                t.check(sql: "sourceType IN ('bookLocator', 'highlight', 'note', 'readingSession')")
                t.check(sql: "(locatorJSON IS NULL AND href IS NULL) OR (locatorJSON IS NOT NULL AND href IS NOT NULL)")
            }
            try db.create(table: "journalMemoryChanges", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("journalID", .text).notNull().indexed().references("reflections", onDelete: .cascade)
                t.column("changeType", .text).notNull()
                t.column("memoryID", .text)
                t.column("summary", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.check(sql: "changeType IN ('store', 'reinforce', 'revise')")
                t.check(sql: "length(trim(summary)) > 0")
            }
        }

        // P0 voice polish. Optional AI-tidied version of the user's own words;
        // `originalText` remains the raw source of truth.
        migrator.registerMigration("v11_polished_text") { db in
            try db.alter(table: "reflections") { t in
                t.add(column: "polishedText", .text)
            }
        }

        // WS1 Memory. Long-term derived memories, evidence-backed and
        // cascade-deleted with their source Reflection (PRD §19). ifNotExists
        // keeps v1–v11 installs upgradeable without deletion.
        migrator.registerMigration("v12_memory") { db in
            try db.create(table: "memories", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("sourceReflectionID", .text).references("reflections", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("claim", .text).notNull()
                t.column("confidence", .double).notNull()
                t.column("status", .text).notNull()
                t.column("userEdited", .boolean).notNull().defaults(to: false)
                t.column("evidenceIDsJSON", .blob).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.check(sql: "kind IN ('episodic', 'semantic', 'preference', 'openQuestion', 'profileTrait')")
                t.check(sql: "length(trim(claim)) > 0")
                t.check(sql: "status IN ('provisional', 'active', 'superseded')")
            }
        }

        // RAG semantic layer. A separate, user-configured embedding model on the
        // provider config (nil = lexical-only), and a per-job record of which
        // model the book was embedded with (drives re-embed on model switch and
        // the per-book RAG progress page). Additive: old installs upgrade intact.
        migrator.registerMigration("v13_embedding_config") { db in
            try db.alter(table: "providerConfigurations") { t in
                t.add(column: "embeddingModelID", .text)
            }
            try db.alter(table: "bookIndexJobs") { t in
                t.add(column: "embeddingModel", .text)
            }
        }

        // RAG precision gate. A separate, user-configured cross-encoder rerank
        // model (nil = no reranking; retrieval falls back to fused results).
        migrator.registerMigration("v14_reranker_config") { db in
            try db.alter(table: "providerConfigurations") { t in
                t.add(column: "rerankerModelID", .text)
            }
        }

        // Per-role RAG endpoints/keys. Each of embedding/reranker may carry its
        // own base URL + keychain reference (e.g. SiliconFlow Qwen models while
        // chat runs elsewhere). Nil = fall back to the chat provider's values.
        migrator.registerMigration("v15_rag_role_endpoints") { db in
            try db.alter(table: "providerConfigurations") { t in
                t.add(column: "embeddingBaseURL", .text)
                t.add(column: "embeddingSecretReference", .text)
                t.add(column: "rerankerBaseURL", .text)
                t.add(column: "rerankerSecretReference", .text)
            }
        }

        // Small-to-big retrieval. `bookChunks` becomes the single chunk table with
        // a role: parents (the existing large structural chunks, 900–1400 chars)
        // remain the context/evidence unit; children (≈350 chars, `parentID` set)
        // become the FTS + embedding retrieval unit. Additive — old rows default
        // to 'parent' and stay valid. The indexVersion bump (BookIndexPipeline v3)
        // triggers a re-index that repopulates children.
        migrator.registerMigration("v16_parent_child_retrieval") { db in
            try db.alter(table: "bookChunks") { t in
                t.add(column: "role", .text).notNull().defaults(to: "parent")
                t.add(column: "parentID", .text).references("bookChunks", onDelete: .cascade)
            }
            try db.create(index: "bookChunks_onParentID", on: "bookChunks", columns: ["parentID"])
        }

        // V1 achievements (PRD F13, low-key badges). Unlock-once records for
        // meaningful thinking behaviors; deliberately no locked/progress rows.
        migrator.registerMigration("v17_achievements") { db in
            try db.create(table: "achievements", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("unlockedAt", .datetime).notNull()
                t.column("sourceReflectionID", .text)
                t.column("bookID", .text)
            }
        }
        migrator.registerMigration("v18_reader_highlight_color_preference") { db in
            try db.alter(table: "readerPreferences") { t in
                t.add(column: "lastUsedHighlightColor", .text).notNull().defaults(to: HighlightColor.yellow.rawValue)
            }
        }

        // JRNL-01/02 Journal user sovereignty (PRD F9: 忠于用户). A "What I think"
        // bullet the user has edited is flagged `userEdited` and keeps the Agent's
        // original draft in `agentOriginalText`, so later re-materialization of
        // Agent output can never silently overwrite the user's words. The backfill
        // gives every pre-existing row its (still-Agent) text as the original, so
        // old rows are protected the moment they are first edited. Additive: old
        // installs upgrade intact.
        migrator.registerMigration("v19_journal_user_edited_thoughts") { db in
            try db.alter(table: "journalThoughts") { t in
                t.add(column: "userEdited", .boolean).notNull().defaults(to: false)
                t.add(column: "agentOriginalText", .text)
            }
            try db.execute(sql: "UPDATE journalThoughts SET agentOriginalText = thought")
        }

        // FIX-02 (PRD §21.3): the streaming toggle is gone. The request path always
        // sends `stream: false`, so the persisted flag only promised what never
        // existed. The column is dropped cleanly; no table (and thus no wipe-order
        // entry) is affected.
        migrator.registerMigration("v20_drop_streaming_flag") { db in
            try db.alter(table: "providerConfigurations") { t in
                t.drop(column: "streamingEnabled")
            }
        }

        // Brain domain (docs/brain.md, phase 12): one table for the three
        // first-class objects (thought/question/memory) with per-kind state
        // CHECKs — illegal states are unrepresentable at the storage layer too.
        // The one-time backfill carries existing `memories` rows over unchanged
        // in meaning: status→state and confidence→level are deterministic, and
        // the old table keeps working (MyMind UI switches in phase 13).
        migrator.registerMigration("v21_brain") { db in
            try db.create(table: "brainItems", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("title", .text)
                t.column("content", .text).notNull()
                t.column("state", .text).notNull()
                t.column("origin", .text)
                t.column("confidence", .text)
                // Memory-backfill only: mirrors the legacy memories.sourceReflectionID
                // cascade. Thought/Question provenance moves to brainItemEvidence
                // in phase 14 and must not use this column.
                t.column("sourceReflectionID", .text).references("reflections", onDelete: .cascade)
                t.column("contentHash", .text)
                t.column("schemaVersion", .integer).notNull().defaults(to: 1)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.check(sql: "kind IN ('thought', 'question', 'memory')")
                t.check(sql: "length(trim(content)) > 0")
                t.check(sql: """
                    (kind = 'memory' AND state IN ('active', 'needsReview', 'superseded', 'forgotten') \
                    AND origin IS NOT NULL AND confidence IS NOT NULL AND title IS NULL) \
                    OR (kind = 'thought' AND state IN ('emerging', 'evolving', 'stable', 'reconsidering', 'archived') \
                    AND origin IS NULL AND confidence IS NULL AND title IS NOT NULL) \
                    OR (kind = 'question' AND state IN ('open', 'exploring', 'partiallyResolved', 'resolved', 'dormant') \
                    AND origin IS NULL AND confidence IS NULL)
                    """)
            }
            try Self.backfillBrainItems(db)
        }

        // Brain evidence & relations (docs/brain.md §4-5, phase 14). Evidence is
        // fact, brain items are interpretation; identity is (item, source,
        // relation) / (source, target, relation) so attaching is idempotent.
        // Reflection-sourced evidence has no SQLite FK (the source columns are
        // generic strings) — GRDBReflectionRepository.delete cleans those rows
        // in the same transaction; item deletion cascades via FK.
        migrator.registerMigration("v22_brain_evidence_relations") { db in
            try db.create(table: "brainItemEvidence", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("brainItemID", .text).notNull().references("brainItems", onDelete: .cascade)
                t.column("sourceType", .text).notNull()
                t.column("sourceID", .text).notNull()
                t.column("relation", .text).notNull()
                t.column("weight", .double).notNull().defaults(to: 1)
                t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["brainItemID", "sourceType", "sourceID", "relation"])
                t.check(sql: "sourceType IN ('reflection', 'bookChunk', 'message')")
                t.check(sql: "relation IN ('origin', 'supports', 'contradicts', 'revises', 'raises', 'answers')")
                t.check(sql: "weight >= 0 AND weight <= 1")
            }
            try db.create(table: "brainItemRelations", ifNotExists: true) { t in
                t.column("sourceItemID", .text).notNull().references("brainItems", onDelete: .cascade)
                t.column("targetItemID", .text).notNull().references("brainItems", onDelete: .cascade)
                t.column("relation", .text).notNull()
                t.column("weight", .double).notNull().defaults(to: 1)
                t.column("createdAt", .datetime).notNull()
                t.primaryKey(["sourceItemID", "targetItemID", "relation"])
                t.check(sql: "sourceItemID != targetItemID")
                t.check(sql: "relation IN ('related', 'supports', 'contradicts', 'evolvesFrom', 'raises', 'addresses', 'derivedMemory')")
                t.check(sql: "weight >= 0 AND weight <= 1")
            }
            try db.create(index: "brainItemEvidence_onItem", on: "brainItemEvidence", columns: ["brainItemID"])
            try db.create(index: "brainItemRelations_onTarget", on: "brainItemRelations", columns: ["targetItemID"])
        }

        // Persistent brain-item embeddings (docs/brain.md §6, phase 15): created
        // once, reused across queries. PK (item, model) keeps old-model rows on
        // a model switch (same policy as bookChunkEmbeddings); item deletion
        // cascades its vectors, so there is no manual GC.
        migrator.registerMigration("v23_brain_item_embeddings") { db in
            try db.create(table: "brainItemEmbeddings", ifNotExists: true) { t in
                t.column("brainItemID", .text).notNull().references("brainItems", onDelete: .cascade)
                t.column("model", .text).notNull()
                t.column("dimensions", .integer).notNull()
                t.column("contentHash", .text).notNull()
                t.column("vector", .blob).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.primaryKey(["brainItemID", "model"])
            }
        }
        return migrator
    }

    /// One-time, idempotent carry-over of legacy `memories` rows into
    /// `brainItems` (kind = memory). Deterministic mapping: provisional→needsReview,
    /// active→active, superseded→superseded; confidence ≥0.8→high, ≥0.5→medium,
    /// else low; origin agentInferred (every legacy memory came from the journal
    /// agent pipeline). Internal so tests can re-run it against seeded rows.
    public static func backfillBrainItems(_ db: Database) throws {
        try db.execute(sql: """
            INSERT OR IGNORE INTO brainItems
                (id, kind, title, content, state, origin, confidence, sourceReflectionID, contentHash, schemaVersion, createdAt, updatedAt)
            SELECT id, 'memory', NULL, claim,
                   CASE status WHEN 'provisional' THEN 'needsReview' WHEN 'active' THEN 'active' ELSE 'superseded' END,
                   'agentInferred',
                   CASE WHEN confidence >= 0.8 THEN 'high' WHEN confidence >= 0.5 THEN 'medium' ELSE 'low' END,
                   sourceReflectionID, NULL, 1, createdAt, updatedAt
            FROM memories
            """)
    }

    /// Every user-data table in child-before-parent order, so the wipe succeeds
    /// with or without foreign-key enforcement on the writer. `books` sits last:
    /// its cascade would reach most tables, but memories (nullable source),
    /// providerConfigurations and achievements carry no foreign key and are
    /// therefore listed explicitly. Public so tests can assert the wipe leaves
    /// zero rows in every table — new user-data tables must be added here.
    public static let userDataTableOrder: [String] = [
        "routingTraces",
        "journalMemoryChanges",
        "journalThoughts",
        "agentQuestions",
        "reflectionCitations",
        "agentCitations",
        "agentResponseEvidence",
        "reflectionMessages",
        "reflectionHighlights",
        "reflectionConnections",
        "reflectionEvidence",
        "memories",
        "brainItemEmbeddings",
        "brainItemEvidence",
        "brainItemRelations",
        "brainItems",
        "reflections",
        "readingSessions",
        "readingPositions",
        "readerPreferences",
        "notes",
        "highlights",
        "bookChunkEmbeddings",
        "bookChunksFTS",
        "bookChunks",
        "bookTextBlocks",
        "bookChapters",
        "bookSections",
        "bookIndexJobs",
        "achievements",
        "providerConfigurations",
        "books",
    ]

    /// "清除所有本地数据" (PRD §13.3): deletes every row of user data — books and
    /// their EPUB-derived index, reading positions, highlights, notes, sessions,
    /// reflections (with journal tables, evidence, citations, connections),
    /// memories, achievements, provider configurations and preferences — in one
    /// transaction, leaving the schema (and every migration) intact. App
    /// Keychain secrets and UserDefaults are cleared by the caller, and the
    /// sandbox container structure itself is untouched.
    public func wipeAllUserData() async throws {
        try await writer.write { db in
            // Children before parents inside bookChunks (self-referencing
            // parentID): deleting a parent row while its child row still exists
            // would violate the immediate foreign key.
            try db.execute(sql: "DELETE FROM bookChunks WHERE parentID IS NOT NULL")
            for table in Self.userDataTableOrder {
                // Table names are compile-time literals above, never user input.
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }

    private static func addLocatorColumns(to t: TableDefinition) {
        t.column("locatorJSON", .blob).notNull()
        t.column("href", .text).notNull()
        t.column("progression", .double)
        t.column("totalProgression", .double)
        t.column("textBefore", .text)
        t.column("textHighlight", .text)
        t.column("textAfter", .text)
    }

    private static func addLocatorColumns(to t: TableDefinition, prefix: String) {
        t.column("\(prefix)LocatorJSON", .blob).notNull()
        t.column("\(prefix)Href", .text).notNull()
        t.column("\(prefix)Progression", .double)
        t.column("\(prefix)TotalProgression", .double)
        t.column("\(prefix)TextBefore", .text)
        t.column("\(prefix)TextHighlight", .text)
        t.column("\(prefix)TextAfter", .text)
    }

    private static func addOptionalLocatorColumns(to t: TableDefinition, prefix: String) {
        t.column("\(prefix)LocatorJSON", .blob)
        t.column("\(prefix)Href", .text)
        t.column("\(prefix)Progression", .double)
        t.column("\(prefix)TotalProgression", .double)
        t.column("\(prefix)TextBefore", .text)
        t.column("\(prefix)TextHighlight", .text)
        t.column("\(prefix)TextAfter", .text)
    }
}
