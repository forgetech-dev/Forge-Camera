import Foundation

enum HTTPProblem: Error, Sendable, Equatable {
    case malformedRequest
    case routeNotFound
    case methodNotAllowed
    case unsupportedMediaType
    case payloadTooLarge
    case directorFailed
    case responseEncodingFailed

    var status: Int {
        switch self {
        case .malformedRequest: 400
        case .routeNotFound: 404
        case .methodNotAllowed: 405
        case .unsupportedMediaType: 415
        case .payloadTooLarge: 413
        case .directorFailed: 502
        case .responseEncodingFailed: 500
        }
    }

    var code: String {
        switch self {
        case .malformedRequest: "malformed_request"
        case .routeNotFound: "route_not_found"
        case .methodNotAllowed: "method_not_allowed"
        case .unsupportedMediaType: "unsupported_media_type"
        case .payloadTooLarge: "payload_too_large"
        case .directorFailed: "director_failed"
        case .responseEncodingFailed: "response_encoding_failed"
        }
    }
}

enum HTTPResponse {
    static func success(json: Data) -> Data {
        make(status: 200, reason: "OK", body: json)
    }

    static func health() -> Data {
        success(json: Data(#"{"status":"ok"}"#.utf8))
    }

    static func problem(_ problem: HTTPProblem) -> Data {
        let body = (try? JSONEncoder().encode(ErrorEnvelope(error: .init(code: problem.code))))
            ?? Data(#"{"error":{"code":"response_encoding_failed"}}"#.utf8)
        return make(status: problem.status, reason: reason(for: problem.status), body: body)
    }

    private static func make(status: Int, reason: String, body: Data) -> Data {
        let headers = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        var response = Data(headers.utf8)
        response.append(body)
        return response
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Payload Too Large"
        case 415: "Unsupported Media Type"
        case 502: "Bad Gateway"
        default: "Internal Server Error"
        }
    }
}

private struct ErrorEnvelope: Encodable {
    struct Payload: Encodable {
        let code: String
    }

    let error: Payload
}
