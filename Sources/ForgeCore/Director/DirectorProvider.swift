import Foundation

/// What the director is asked to decide about.
public struct DirectorRequest: Sendable, Equatable {
    public let requestId: String
    public let scene: SceneState
    /// A caller-supplied intent, when the user has chosen one.
    public let intentHint: PhotographicIntent?
    /// The plan currently latched, so a provider can refine rather than restart.
    public let previousPlanId: String?

    public init(
        requestId: String,
        scene: SceneState,
        intentHint: PhotographicIntent? = nil,
        previousPlanId: String? = nil
    ) {
        self.requestId = requestId
        self.scene = scene
        self.intentHint = intentHint
        self.previousPlanId = previousPlanId
    }
}

public enum DirectorError: Error, Sendable, Equatable {
    case unavailable
    case timedOut
    case invalidPlan(reason: String)
    case budgetExhausted
}

/// Decides what the photograph should be.
///
/// Implementations are interchangeable: a deterministic local heuristic, a mock, a
/// hosted model, a user's own key, or an on-device model. Nothing above this protocol
/// knows which is in use.
public protocol DirectorProvider: Sendable {
    func plan(_ request: DirectorRequest) async throws -> CompositionPlan
}
