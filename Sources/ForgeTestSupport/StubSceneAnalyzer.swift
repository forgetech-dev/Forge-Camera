import ForgeCore

/// A deterministic analyzer that maps a frame straight onto a caller-supplied scene.
///
/// Lets a pipeline test drive perception without Vision, a camera, or an image: the
/// test decides what each frame "sees", so the assertions are about the loop rather
/// than about detection quality.
public struct StubSceneAnalyzer<Content: Sendable>: SceneAnalyzer {
    public typealias FrameContent = Content

    private let scene: @Sendable (SceneFrame<Content>, SceneState?) -> SceneState

    public init(scene: @escaping @Sendable (SceneFrame<Content>, SceneState?) -> SceneState) {
        self.scene = scene
    }

    /// Reports one subject at a fixed place, so guidance has something to act on.
    public init(subjectBounds: NormalizedRect = NormalizedRect(
        x: 0.2,
        y: 0.3,
        width: 0.15,
        height: 0.4
    )) {
        self.init { frame, _ in
            SceneState(
                timestamp: frame.timestamp,
                frame: frame.geometry,
                subjects: [
                    DetectedSubject(id: SubjectID("stub"), bounds: subjectBounds),
                ]
            )
        }
    }

    public func analyze(
        _ frame: SceneFrame<Content>,
        previous: SceneState?
    ) async -> SceneState {
        scene(frame, previous)
    }
}

/// A director that counts how often it was consulted.
///
/// The point of the trigger policy is that this number stays small relative to the
/// frame count, so a test needs to be able to read it.
public actor CountingDirectorProvider: DirectorProvider {
    private let underlying: any DirectorProvider
    public private(set) var callCount = 0

    public init(wrapping underlying: any DirectorProvider = HeuristicDirector()) {
        self.underlying = underlying
    }

    public func plan(_ request: DirectorRequest) async throws -> CompositionPlan {
        callCount += 1
        return try await underlying.plan(request)
    }
}

/// A director that always fails, for exercising the no-backend degradation path.
public struct FailingDirectorProvider: DirectorProvider {
    private let error: DirectorError

    public init(error: DirectorError = .unavailable) {
        self.error = error
    }

    public func plan(_: DirectorRequest) async throws -> CompositionPlan {
        throw error
    }
}
