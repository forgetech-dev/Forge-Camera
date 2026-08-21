import ForgeCore
import Foundation
import Testing
@testable import ForgeBridge

@Suite("Director HTTP client")
struct DirectorHTTPClientTests {
    @Test("A healthy response confirms the configured server")
    func healthy() async throws {
        let baseURL = try #require(URL(string: "http://camera-mac.local:8765"))
        let client = DirectorHTTPClient(baseURL: baseURL) { request in
            #expect(request.url == URL(string: "http://camera-mac.local:8765/health"))
            #expect(request.timeoutInterval == 3)
            return try response(url: baseURL, status: 200, body: #"{"status":"ok"}"#)
        }

        try await client.checkHealth()
    }

    @Test("An HTTP failure remains a typed transport result")
    func serverFailure() async throws {
        let baseURL = try #require(URL(string: "http://camera-mac.local:8765"))
        let client = DirectorHTTPClient(baseURL: baseURL) { _ in
            try response(
                url: baseURL,
                status: 503,
                body: #"{"status":"unavailable"}"#
            )
        }

        await #expect(throws: DirectorHTTPClientError.unexpectedStatus(503)) {
            try await client.checkHealth()
        }
    }

    @Test("An unrelated JSON endpoint is not accepted as the Director")
    func unhealthyPayload() async throws {
        let baseURL = try #require(URL(string: "http://camera-mac.local:8765"))
        let client = DirectorHTTPClient(baseURL: baseURL) { _ in
            try response(url: baseURL, status: 200, body: #"{"message":"ok"}"#)
        }

        await #expect(throws: DirectorHTTPClientError.unhealthy) {
            try await client.checkHealth()
        }
    }

    @Test("One JPEG is uploaded as multipart and decoded as a validated plan")
    func planUpload() async throws {
        let baseURL = try #require(URL(string: "http://camera-mac.local:8765"))
        let encodedPlan = try JSONEncoder().encode(Self.plan)
        let client = DirectorHTTPClient(baseURL: baseURL) { request in
            #expect(request.url == URL(string: "http://camera-mac.local:8765/v1/plan"))
            #expect(request.httpMethod == "POST")
            #expect(request.timeoutInterval == 30)
            #expect(request.value(forHTTPHeaderField: "Content-Type")
                == "multipart/form-data; boundary=forge-test-boundary")
            let body = try #require(request.httpBody)
            #expect(body.range(of: Data("name=\"image\"".utf8)) != nil)
            #expect(body.range(of: Data([0xFF, 0xD8, 0xFF, 0xD9])) != nil)
            return try response(url: baseURL, status: 200, body: encodedPlan)
        }

        let plan = try await client.plan(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]))

        #expect(plan == Self.plan)
    }

    @Test("Malformed plan JSON never becomes application state")
    func malformedPlan() async throws {
        let baseURL = try #require(URL(string: "http://camera-mac.local:8765"))
        let client = DirectorHTTPClient(baseURL: baseURL) { _ in
            try response(url: baseURL, status: 200, body: Data(#"{"planId":""}"#.utf8))
        }

        await #expect(throws: DirectorHTTPClientError.invalidPlan) {
            try await client.plan(jpegData: Data([0xFF]))
        }
    }

    @Test("An empty planning image is rejected before networking")
    func emptyImage() async throws {
        let baseURL = try #require(URL(string: "http://camera-mac.local:8765"))
        let client = DirectorHTTPClient(baseURL: baseURL) { _ in
            throw TestFailure.unexpectedNetworkRequest
        }

        await #expect(throws: DirectorHTTPClientError.invalidImage) {
            try await client.plan(jpegData: Data())
        }
    }

    @Test("LAN exposure must be selected explicitly")
    func serverBindings() {
        #expect(DevelopmentServerBinding.loopback.ipv4Address == "127.0.0.1")
        #expect(DevelopmentServerBinding.localNetwork.ipv4Address == "0.0.0.0")
    }

    private static let plan = CompositionPlan(
        planId: "phone-plan",
        requestId: "server-request",
        intent: .portrait,
        selection: SubjectSelection(
            kind: .animal,
            visualAnchor: .init(x: 0.52, y: 0.41)
        ),
        framing: FramingPlan(targetFrame: .init(x: 0.2, y: 0.1, width: 0.6, height: 0.8)),
        displayAdvice: ["Keep the eyes clear"]
    )
}

private func response(url: URL, status: Int, body: String) throws -> (Data, URLResponse) {
    try response(url: url, status: status, body: Data(body.utf8))
}

private func response(url: URL, status: Int, body: Data) throws -> (Data, URLResponse) {
    guard let response = HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    ) else {
        throw TestFailure.responseConstruction
    }
    return (body, response)
}

private enum TestFailure: Error {
    case responseConstruction
    case unexpectedNetworkRequest
}
