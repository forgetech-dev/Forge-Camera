import ForgeCore
import Foundation
import Testing
@testable import ForgeBridge

@Suite("Plan HTTP endpoint")
struct PlanHTTPEndpointTests {
    @Test("Health is local and does not invoke planning")
    func health() {
        let endpoint = PlanHTTPEndpoint { _ in throw TestFailure.unexpectedPlan }

        let response = endpoint.response(for: request(method: "GET", path: "/health"))

        #expect(status(in: response) == 200)
        #expect(String(data: body(in: response), encoding: .utf8) == #"{"status":"ok"}"#)
    }

    @Test("A multipart JPEG produces a CompositionPlan JSON response")
    func multipartPlan() throws {
        let image = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let endpoint = PlanHTTPEndpoint { imageURL in
            let receivedImage = try Data(contentsOf: imageURL)
            #expect(receivedImage == image)
            #expect(imageURL.lastPathComponent == "planning-image.jpg")
            return Self.plan
        }

        let response = endpoint.response(for: multipartRequest(
            image: image,
            mediaType: "image/jpeg"
        ))
        let decoded = try JSONDecoder().decode(CompositionPlan.self, from: body(in: response))

        #expect(status(in: response) == 200)
        #expect(decoded == Self.plan)
    }

    @Test("Unknown routes fail without invoking planning")
    func unknownRoute() {
        let endpoint = PlanHTTPEndpoint { _ in throw TestFailure.unexpectedPlan }

        let response = endpoint.response(for: request(method: "GET", path: "/missing"))

        #expect(status(in: response) == 404)
        #expect(String(data: body(in: response), encoding: .utf8)?
            .contains("route_not_found") == true)
    }

    @Test("Unsupported image media types are rejected before planning")
    func unsupportedImage() {
        let endpoint = PlanHTTPEndpoint { _ in throw TestFailure.unexpectedPlan }

        let response = endpoint.response(for: multipartRequest(
            image: Data([0x00]),
            mediaType: "image/heic"
        ))

        #expect(status(in: response) == 415)
    }

    @Test("Provider failures expose only a stable error code")
    func providerFailureIsRedacted() {
        let endpoint = PlanHTTPEndpoint { _ in throw TestFailure.secretDetails }

        let response = endpoint.response(for: multipartRequest(
            image: Data([0x89, 0x50, 0x4E, 0x47]),
            mediaType: "image/png"
        ))
        let responseBody = String(data: body(in: response), encoding: .utf8)

        #expect(status(in: response) == 502)
        #expect(responseBody?.contains("director_failed") == true)
        #expect(responseBody?.contains("secret") == false)
    }

    @Test("Framing waits for exactly the declared request body")
    func requestFraming() throws {
        let complete = request(method: "POST", path: "/v1/plan", body: Data([1, 2, 3]))
        let partial = Data(complete.dropLast())

        #expect(try HTTPRequestFraming.expectedLength(in: partial) == complete.count)
        #expect(try HTTPRequestFraming.expectedLength(in: complete) == complete.count)
    }
}

private extension PlanHTTPEndpointTests {
    enum TestFailure: Error {
        case unexpectedPlan
        case secretDetails
    }

    static let plan = CompositionPlan(
        planId: "http-plan",
        requestId: "request-1",
        intent: .portrait,
        selection: SubjectSelection(
            kind: .animal,
            visualAnchor: .init(x: 0.52, y: 0.41)
        ),
        framing: FramingPlan(targetFrame: .init(x: 0.2, y: 0.1, width: 0.6, height: 0.8)),
        displayAdvice: ["Keep the eyes clear"]
    )

    func request(method: String, path: String, body: Data = Data()) -> Data {
        let headers = """
        \(method) \(path) HTTP/1.1\r
        Host: 127.0.0.1\r
        Content-Length: \(body.count)\r
        \r

        """
        var data = Data(headers.utf8)
        data.append(body)
        return data
    }

    func multipartRequest(image: Data, mediaType: String) -> Data {
        let boundary = "forge-test-boundary"
        let bodyPrefix = """
        --\(boundary)\r
        Content-Disposition: form-data; name="image"; filename="input"\r
        Content-Type: \(mediaType)\r
        \r

        """
        let bodySuffix = "\r\n--\(boundary)--\r\n"
        var body = Data(bodyPrefix.utf8)
        body.append(image)
        body.append(Data(bodySuffix.utf8))
        let headers = """
        POST /v1/plan HTTP/1.1\r
        Host: 127.0.0.1\r
        Content-Type: multipart/form-data; boundary=\(boundary)\r
        Content-Length: \(body.count)\r
        \r

        """
        var request = Data(headers.utf8)
        request.append(body)
        return request
    }

    func status(in response: Data) -> Int? {
        guard let lineEnd = response.range(of: Data("\r\n".utf8)),
              let line = String(data: response[..<lineEnd.lowerBound], encoding: .utf8)
        else {
            return nil
        }
        return line.split(separator: " ").dropFirst().first.flatMap { Int($0) }
    }

    func body(in response: Data) -> Data {
        guard let separator = response.range(of: HTTPWire.headerSeparator) else { return Data() }
        return Data(response[separator.upperBound...])
    }
}
