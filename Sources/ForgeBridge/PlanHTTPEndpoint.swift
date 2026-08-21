import ForgeCore
import Foundation

/// Resource limits for the development planning endpoint.
public enum PlanHTTPPolicy {
    /// Maximum bytes accepted before the HTTP header terminator.
    public static let maximumHeaderBytes = 32 * 1024
    /// Maximum multipart request body. The provider performs the final 1024-pixel sanitization.
    public static let maximumBodyBytes = 12 * 1024 * 1024
}

/// Turns one complete HTTP request into one complete HTTP response.
///
/// The planning closure is the existing provider variation point expressed without
/// adding a sixth project protocol. Tests inject a deterministic closure; the Mac
/// composition root injects the concrete image-capable provider.
public struct PlanHTTPEndpoint: Sendable {
    private let plan: @Sendable (URL) throws -> CompositionPlan

    /// Creates an endpoint backed by an image-to-plan operation.
    public init(plan: @escaping @Sendable (URL) throws -> CompositionPlan) {
        self.plan = plan
    }

    /// Handles `GET /health` or one multipart `POST /v1/plan` request.
    public func response(for requestData: Data) -> Data {
        do {
            guard requestData.count <= PlanHTTPPolicy.maximumHeaderBytes
                + PlanHTTPPolicy.maximumBodyBytes
            else {
                throw HTTPProblem.payloadTooLarge
            }
            let request = try HTTPRequest.parse(requestData)
            if request.path == "/health" {
                guard request.method == "GET" else { throw HTTPProblem.methodNotAllowed }
                return HTTPResponse.health()
            }
            guard request.path == "/v1/plan" else { throw HTTPProblem.routeNotFound }
            guard request.method == "POST" else { throw HTTPProblem.methodNotAllowed }
            let image = try MultipartImage.extract(from: request)
            return try planResponse(for: image)
        } catch let problem as HTTPProblem {
            return HTTPResponse.problem(problem)
        } catch {
            return HTTPResponse.problem(.responseEncodingFailed)
        }
    }

    private func planResponse(for image: MultipartImage) throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "forge-http-plan-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false
            )
        } catch {
            throw HTTPProblem.responseEncodingFailed
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("planning-image.\(image.fileExtension)")
        do {
            try image.data.write(to: imageURL, options: .atomic)
        } catch {
            throw HTTPProblem.responseEncodingFailed
        }

        let compositionPlan: CompositionPlan
        do {
            compositionPlan = try plan(imageURL)
        } catch {
            throw HTTPProblem.directorFailed
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let json = try? encoder.encode(compositionPlan) else {
            throw HTTPProblem.responseEncodingFailed
        }
        return HTTPResponse.success(json: json)
    }
}
