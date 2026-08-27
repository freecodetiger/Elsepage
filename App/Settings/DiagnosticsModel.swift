import ContextRouting
import Observation

/// Developer-facing routing observability: aggregates stored routing traces
/// (fallback counts, average durations). Owned separately so the Settings
/// diagnostics page is its own concern rather than a slice of the provider model.
@MainActor @Observable
final class DiagnosticsModel {
    private let traceRepository: (any RoutingTraceRepository)?
    private(set) var routingDiagnostics: RoutingTraceDiagnostics?

    init(traceRepository: (any RoutingTraceRepository)? = nil) {
        self.traceRepository = traceRepository
    }

    func reload() async {
        guard let traceRepository else { return }
        routingDiagnostics = try? await traceRepository.diagnostics()
    }
}
