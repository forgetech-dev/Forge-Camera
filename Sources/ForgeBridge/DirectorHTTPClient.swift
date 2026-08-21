import ForgeCore
import Foundation

/// Stable failures from the development Director HTTP boundary.
public enum DirectorHTTPClientError: Error, Sendable, Equatable {
    case invalidResponse
    case unexpectedStatus(Int)
    case unhealthy
    case invalidImage
    case invalidPlan
}

/// The iPhone-side HTTP transport for the development Director server.
///
/// It checks connectivity separately from planning, so opening the App never implies
/// an external AI request. The caller must explicitly choose when to upload one image.
public struct DirectorHTTPClient: Sendable {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let baseURL: URL
    private let multipartBoundary: String
    private let load: Loader

    /// Creates a client that uses the system URL session.
    public init(baseURL: URL) {
        self.baseURL = baseURL
        multipartBoundary = "forge-\(UUID().uuidString)"
        load = { request in
            try await URLSession.shared.data(for: request)
        }
    }

    init(
        baseURL: URL,
        multipartBoundary: String = "forge-test-boundary",
        load: @escaping Loader
    ) {
        self.baseURL = baseURL
        self.multipartBoundary = multipartBoundary
        self.load = load
    }

    /// Verifies that the configured endpoint is a healthy Forge development server.
    public func checkHealth() async throws {
        var request = URLRequest(url: baseURL.appending(path: "health"))
        request.timeoutInterval = 3
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let (data, response) = try await load(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DirectorHTTPClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw DirectorHTTPClientError.unexpectedStatus(httpResponse.statusCode)
        }
        guard let health = try? JSONDecoder().decode(HealthResponse.self, from: data),
              health.status == "ok"
        else {
            throw DirectorHTTPClientError.unhealthy
        }
    }

    /// Uploads one bounded metadata-free JPEG and returns its validated composition plan.
    public func plan(jpegData: Data) async throws -> CompositionPlan {
        guard !jpegData.isEmpty else { throw DirectorHTTPClientError.invalidImage }
        var request = URLRequest(url: baseURL.appending(path: "v1/plan"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(
            "multipart/form-data; boundary=\(multipartBoundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = multipartBody(jpegData: jpegData)

        let (data, response) = try await load(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DirectorHTTPClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw DirectorHTTPClientError.unexpectedStatus(httpResponse.statusCode)
        }
        guard let proposed = try? JSONDecoder().decode(CompositionPlan.self, from: data),
              let validated = try? PlanValidator().validate(proposed)
        else {
            throw DirectorHTTPClientError.invalidPlan
        }
        return validated.plan
    }

    private func multipartBody(jpegData: Data) -> Data {
        let prefix = """
        --\(multipartBoundary)\r
        Content-Disposition: form-data; name="image"; filename="planning-image.jpg"\r
        Content-Type: image/jpeg\r
        \r

        """
        let suffix = "\r\n--\(multipartBoundary)--\r\n"
        var body = Data(prefix.utf8)
        body.append(jpegData)
        body.append(Data(suffix.utf8))
        return body
    }
}

private struct HealthResponse: Decodable {
    let status: String
}
