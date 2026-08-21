import ForgeCore
import Foundation

/// Failures from the explicit development-only Codex image-to-plan spike.
public enum CodexDirectorSpikeError: Error, Sendable, Equatable {
    case inputNotFound
    case unsupportedImageFormat
    case inputImageDecodingFailed
    case imageSanitizationFailed
    case invalidRequestID
    case temporaryWorkspaceFailed
    case schemaUnavailable
    case codexUnavailable
    case authenticationRequired
    case executionFailed(exitCode: Int32)
    case missingOutput
    case planDecodingFailed
    case planValidationFailed
    case responseRequestMismatch
    case missingRequiredGuidance
}

extension CodexDirectorSpikeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .inputNotFound:
            "The input image does not exist."
        case .unsupportedImageFormat:
            "The spike accepts a JPEG or PNG image."
        case .inputImageDecodingFailed:
            "The input image could not be decoded."
        case .imageSanitizationFailed:
            "The input image could not be privacy-sanitized."
        case .invalidRequestID:
            "The request identifier must be a UUID."
        case .temporaryWorkspaceFailed:
            "The temporary Codex workspace could not be prepared."
        case .schemaUnavailable:
            "The bundled CompositionPlan output schema is unavailable."
        case .codexUnavailable:
            "The codex command is unavailable on this Mac."
        case .authenticationRequired:
            "Codex authentication is required. Run codex login on this Mac."
        case let .executionFailed(exitCode):
            "codex exec failed with exit code \(exitCode)."
        case .missingOutput:
            "codex exec completed without a final CompositionPlan."
        case .planDecodingFailed:
            "The Codex response did not decode as CompositionPlan JSON."
        case .planValidationFailed:
            "The decoded CompositionPlan failed core validation."
        case .responseRequestMismatch:
            "The CompositionPlan request identifier did not match the request."
        case .missingRequiredGuidance:
            "The CompositionPlan did not contain a usable anchor and target frame."
        }
    }
}

/// The measured result of one explicit external-service validation run.
public struct CodexDirectorSpikeResult: Sendable, Equatable {
    /// The decoded and core-validated structured plan.
    public let plan: CompositionPlan
    /// Field-level degradations reported by core validation.
    public let warnings: [PlanValidator.Warning]
    /// Wall-clock duration of the external `codex exec` process.
    public let elapsedSeconds: Double
}

/// Runs one development-only image-to-`CompositionPlan` validation on a trusted Mac.
///
/// The caller must supply a non-sensitive image. This module downsizes it, re-encodes
/// pixels into a new JPEG without source metadata, and gives the sanitized copy a
/// generic temporary path before invoking `codex exec`. CLI authentication remains
/// owned by Codex and is never read or copied by this module.
public struct CodexDirectorSpike: Sendable {
    private let processRunner: CodexProcessRunner

    /// Creates a spike that invokes the installed `codex` command through `PATH`.
    public init() {
        processRunner = CodexProcessExecution.run
    }

    init(processRunner: @escaping CodexProcessRunner) {
        self.processRunner = processRunner
    }

    /// Produces and validates one plan. This is an explicitly invoked external-service
    /// operation and is never called by ordinary tests or the iPhone app.
    public func run(
        imageURL: URL,
        requestID: String = UUID().uuidString
    ) throws -> CodexDirectorSpikeResult {
        let schemaURL = try Self.preflight(imageURL: imageURL, requestID: requestID)
        let workspace = try CodexSpikeWorkspace.prepare(imageURL: imageURL)
        defer { workspace.remove() }

        let invocation = Self.makeInvocation(
            workspace: workspace,
            schemaURL: schemaURL,
            requestID: requestID
        )
        let elapsed = try execute(invocation)
        let validated = try Self.decodeAndValidate(
            outputURL: workspace.outputURL,
            requestID: requestID
        )
        return CodexDirectorSpikeResult(
            plan: validated.plan,
            warnings: validated.warnings,
            elapsedSeconds: Self.seconds(in: elapsed)
        )
    }
}

private extension CodexDirectorSpike {
    static func preflight(imageURL: URL, requestID: String) throws -> URL {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw CodexDirectorSpikeError.inputNotFound
        }
        guard supportedImageExtensions.contains(imageURL.pathExtension.lowercased())
        else {
            throw CodexDirectorSpikeError.unsupportedImageFormat
        }
        guard UUID(uuidString: requestID) != nil else {
            throw CodexDirectorSpikeError.invalidRequestID
        }
        guard let schemaURL = Self.schemaURL else {
            throw CodexDirectorSpikeError.schemaUnavailable
        }
        return schemaURL
    }

    func execute(_ invocation: CodexProcessInvocation) throws -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        let exitCode: Int32
        do {
            exitCode = try processRunner(invocation)
        } catch {
            throw CodexDirectorSpikeError.codexUnavailable
        }
        let elapsed = start.duration(to: clock.now)
        guard exitCode == 0 else {
            throw Self.executionError(
                exitCode: exitCode,
                standardErrorURL: invocation.standardErrorURL
            )
        }
        return elapsed
    }

    static func decodeAndValidate(
        outputURL: URL,
        requestID: String
    ) throws -> PlanValidator.Result {
        guard let output = try? Data(contentsOf: outputURL), !output.isEmpty else {
            throw CodexDirectorSpikeError.missingOutput
        }

        let decoded: CompositionPlan
        do {
            decoded = try JSONDecoder().decode(CompositionPlan.self, from: output)
        } catch {
            throw CodexDirectorSpikeError.planDecodingFailed
        }

        let validated: PlanValidator.Result
        do {
            validated = try PlanValidator().validate(decoded)
        } catch {
            throw CodexDirectorSpikeError.planValidationFailed
        }
        guard validated.plan.requestId == requestID else {
            throw CodexDirectorSpikeError.responseRequestMismatch
        }
        guard validated.plan.selection?.visualAnchor != nil,
              validated.plan.framing?.targetFrame != nil
        else {
            throw CodexDirectorSpikeError.missingRequiredGuidance
        }
        return validated
    }

    static func seconds(in duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

extension CodexDirectorSpike {
    static let supportedImageExtensions = ["jpeg", "jpg", "png"]
    static let schemaURL = Bundle.module.url(
        forResource: "CompositionPlan.schema",
        withExtension: "json"
    )

    static func makeInvocation(
        workspace: CodexSpikeWorkspace,
        schemaURL: URL,
        requestID: String
    ) -> CodexProcessInvocation {
        CodexProcessInvocation(
            arguments: [
                "exec",
                "--ephemeral",
                "--ignore-user-config",
                "--sandbox", "read-only",
                "--skip-git-repo-check",
                "--color", "never",
                "--image", workspace.imageURL.path,
                "--output-schema", schemaURL.path,
                "--output-last-message", workspace.outputURL.path,
                prompt(requestID: requestID),
            ],
            currentDirectoryURL: workspace.rootURL,
            standardOutputURL: workspace.standardOutputURL,
            standardErrorURL: workspace.standardErrorURL
        )
    }

    static func prompt(requestID: String) -> String {
        """
        Act as a practical photography director. Do not call tools or inspect the filesystem. Analyze
        only the attached planning image and choose the strongest person, animal, object, place,
        relationship, light pattern, or scene-level theme for one photograph. Return only JSON
        matching the supplied schema.

        Use requestId exactly "\(requestID)" and schemaVersion 1. Generate a non-empty planId.
        Coordinates use the upright displayed image with origin at the top-left, x increasing right,
        and y increasing down. All coordinates are normalized to 0...1.

        selection.visualAnchor is the single point of greatest compositional attention, not
        necessarily the centre of a detected object. Set selection.sourceRegion to null when the
        subject is a scene or light pattern without a discrete region. framing.targetFrame is the
        proposed final photograph boundary within the current image; it is not a subject detection
        box. Choose one decisive, useful frame rather than returning the whole image by default.

        Provide one to three short, concrete photography suggestions in displayAdvice. They are
        display-only and must not encode application commands. Do not invent physical distances,
        camera capabilities, or objects that are not visible. If uncertain, return a simpler plan
        with lower confidence instead of guessing.
        """
    }

    static func executionError(
        exitCode: Int32,
        standardErrorURL: URL
    ) -> CodexDirectorSpikeError {
        if exitCode == 127 {
            return .codexUnavailable
        }
        let message = (try? String(contentsOf: standardErrorURL, encoding: .utf8))?
            .lowercased() ?? ""
        let authenticationMarkers = [
            "authentication required",
            "login required",
            "not logged in",
            "please sign in",
        ]
        if authenticationMarkers.contains(where: message.contains) {
            return .authenticationRequired
        }
        return .executionFailed(exitCode: exitCode)
    }
}
