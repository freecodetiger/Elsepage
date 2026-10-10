import Foundation
import LibraryCore
import ModelProviders
import Persistence
import RagBenchCore
import RetrievalCore

// readloop-rag-bench — retrieval ablation over the RAG corpus.
//
// Usage:
//   swift run readloop-rag-bench [--corpus PATH] [--spec PATH] [--out PATH]
//                                [--k N] [--arms a,b,c]
//
// Reads `chunks.jsonl` (produced on device by RagCorpusSnapshotTests) and
// `queries.spec.json` (authored), rebuilds `queries.jsonl` from the spec, then
// runs each arm of `RagArm.ladder` through the production retriever.
//
// Environment:
//   SILICONFLOW_API_KEY        enables the semantic and rerank arms
//   SILICONFLOW_BASE_URL       default https://api.siliconflow.cn/v1
//   SILICONFLOW_EMBEDDING_MODEL default BAAI/bge-m3
//   SILICONFLOW_RERANK_MODEL    default BAAI/bge-reranker-v2-m3
//
// The key is read from the environment and never written to any report.

struct CLIError: Error { let message: String }

struct CLIArguments {
    var corpusURL = URL(fileURLWithPath: "Fixtures/RagCorpus/chunks.jsonl")
    var specURL = URL(fileURLWithPath: "Fixtures/RagCorpus/queries.spec.json")
    var outputURL = URL(fileURLWithPath: "Fixtures/RagCorpus/ablation.json")
    var queriesURL = URL(fileURLWithPath: "Fixtures/RagCorpus/queries.jsonl")
    var k = 5
    var armNames: [String]?
    /// Sweep the rerank relevance floor instead of using the ladder's default.
    /// Floor 0 keeps every scored candidate, so the sweep separates reordering
    /// from filtering.
    var rerankFloors: [Double]?

    static let helpText = """
    readloop-rag-bench [--corpus PATH] [--spec PATH] [--out PATH] [--queries PATH] [--k N] [--arms a,b,c]
    """

    static func parse(_ arguments: [String]) -> Result<CLIArguments, CLIError> {
        var parsed = CLIArguments()
        var index = 0
        func value(_ flag: String) -> String? {
            guard index + 1 < arguments.count else { return nil }
            index += 1
            return arguments[index]
        }
        while index < arguments.count {
            switch arguments[index] {
            case "--corpus":
                guard let raw = value("--corpus") else { return .failure(CLIError(message: "--corpus 需要一个路径参数")) }
                parsed.corpusURL = URL(fileURLWithPath: raw)
            case "--spec":
                guard let raw = value("--spec") else { return .failure(CLIError(message: "--spec 需要一个路径参数")) }
                parsed.specURL = URL(fileURLWithPath: raw)
            case "--out":
                guard let raw = value("--out") else { return .failure(CLIError(message: "--out 需要一个路径参数")) }
                parsed.outputURL = URL(fileURLWithPath: raw)
            case "--queries":
                guard let raw = value("--queries") else { return .failure(CLIError(message: "--queries 需要一个路径参数")) }
                parsed.queriesURL = URL(fileURLWithPath: raw)
            case "--k":
                guard let raw = value("--k"), let k = Int(raw), k > 0 else {
                    return .failure(CLIError(message: "--k 需要一个正整数参数"))
                }
                parsed.k = k
            case "--arms":
                guard let raw = value("--arms") else { return .failure(CLIError(message: "--arms 需要一个逗号分隔的参数")) }
                parsed.armNames = raw.split(separator: ",").map(String.init)
            case "--rerank-floors":
                guard let raw = value("--rerank-floors") else {
                    return .failure(CLIError(message: "--rerank-floors 需要一个逗号分隔的数字参数"))
                }
                let floors = raw.split(separator: ",").compactMap { Double($0) }
                guard floors.count == raw.split(separator: ",").count else {
                    return .failure(CLIError(message: "--rerank-floors 含无法解析的数字: \(raw)"))
                }
                parsed.rerankFloors = floors
            case "--help", "-h":
                return .failure(CLIError(message: helpText))
            default:
                return .failure(CLIError(message: "未知参数: \(arguments[index])\n\n\(helpText)"))
            }
            index += 1
        }
        return .success(parsed)
    }
}

struct ResolvedProviders {
    var providers = RagProviders()
    var embeddingModel: String?
    var rerankModel: String?
}

func providers(from environment: [String: String]) throws -> ResolvedProviders {
    guard let key = environment["SILICONFLOW_API_KEY"], !key.isEmpty else { return ResolvedProviders() }
    let baseURL = URL(string: environment["SILICONFLOW_BASE_URL"] ?? "https://api.siliconflow.cn/v1")!
    let configuration = ProviderConfiguration(
        provider: .openAICompatible,
        baseURL: baseURL,
        // Unused by the retrieval roles; the embedding and rerank models are set
        // explicitly below.
        modelID: "unused",
        secretReference: SecretReference(rawValue: "env:SILICONFLOW_API_KEY"),
        embeddingModelID: environment["SILICONFLOW_EMBEDDING_MODEL"] ?? "BAAI/bge-m3",
        rerankerModelID: environment["SILICONFLOW_RERANK_MODEL"] ?? "BAAI/bge-reranker-v2-m3"
    )
    return ResolvedProviders(
        providers: RagProviders(
            embedding: { try? OpenAICompatibleEmbeddingProvider(configuration: configuration, apiKey: key) },
            reranker: { try? SiliconFlowReranker(configuration: configuration, apiKey: key) }
        ),
        embeddingModel: configuration.embeddingModelID,
        rerankModel: configuration.rerankerModelID
    )
}

func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
}

func main() async throws {
    let parsed: CLIArguments
    switch CLIArguments.parse(Array(CommandLine.arguments.dropFirst())) {
    case .failure(let error): throw error
    case .success(let value): parsed = value
    }

    let (corpus, spec) = try RagQueryBuilder.load(corpusURL: parsed.corpusURL, specURL: parsed.specURL)
    print("corpus: \(corpus.records.count) chunks across \(corpus.bookKeys.count) books")

    let database = try AppDatabase.inMemory()
    let queries = try await RagQueryBuilder(corpus: corpus).build(spec: spec, database: database)
    try write(try RagCorpusIO.encodeLines(queries), to: parsed.queriesURL)
    print("queries: \(queries.count) written to \(parsed.queriesURL.path)")

    let resolved = try providers(from: ProcessInfo.processInfo.environment)
    if resolved.providers.embedding == nil {
        print("note: SILICONFLOW_API_KEY unset — semantic and rerank arms will report as skipped")
    }

    let ablation = RagAblation(corpus: corpus, database: database, k: parsed.k)
    if resolved.providers.embedding != nil {
        // The semantic lane reads stored vectors. Without this the hybrid arm
        // would fall back to lexical and look identical to the control.
        try await ablation.embedCorpus(providers: resolved.providers)
    }

    var arms = parsed.armNames.map { names in
        names.compactMap { name in RagArm.ladder.first { $0.name == name } }
    } ?? RagArm.ladder
    if let floors = parsed.rerankFloors {
        // Keep the local arms as the reference line, then one rerank arm per
        // floor so the sweep is read against the same baseline every time.
        arms = RagArm.ladder.filter { !$0.rerank }
        arms += floors.map {
            RagArm(name: String(format: "rerank@%.2f", $0), semantic: true, rerank: true,
                   expand: true, minimumRelevance: $0)
        }
    }
    let reports = try await ablation.run(queries: queries, arms: arms, providers: resolved.providers)

    for report in reports {
        print("")
        print("── \(report.arm.name) \(report.skipped.map { "SKIPPED: \($0)" } ?? "")")
        for slice in [report.overall] + report.bySplit + report.byIntent {
            print("   \(slice.describe(k: parsed.k))")
        }
    }

    let report = RagAblationReport(
        runAt: ISO8601DateFormatter().string(from: Date()),
        corpusSHA256: try RagCorpusIO.sha256Hex(of: parsed.corpusURL),
        queriesSHA256: try RagCorpusIO.sha256Hex(of: parsed.queriesURL),
        k: parsed.k,
        embeddingModel: resolved.embeddingModel,
        rerankModel: resolved.rerankModel,
        arms: reports
    )
    try write(try RagCorpusIO.encoder().encode(report), to: parsed.outputURL)
    print("")
    print("report: \(parsed.outputURL.path)")
}

extension RagSlice {
    func describe(k: Int) -> String {
        func rate(_ value: Double?) -> String {
            value.map { String(format: "%.3f", $0) } ?? "n/a"
        }
        return name.padding(toLength: 18, withPad: " ", startingAt: 0)
            + " n=\(queries)/\(goldBearing)g"
            + " rec@\(k)=\(rate(recallAtK)) par=\(rate(parentRecallAtK))"
            + " mrr=\(rate(mrr)) ndcg=\(rate(ndcgAtK))"
            + " edge=\(rate(edgeCorrect))"
            + " leak=\(leakTotal)"
            + " out=\(String(format: "%.1f", meanReturned ?? 0))x\(Int(meanEvidenceCharacters ?? 0))ch"
    }
}

do {
    try await main()
} catch let error as CLIError {
    FileHandle.standardError.write(Data("\(error.message)\n".utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
