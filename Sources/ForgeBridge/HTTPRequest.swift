import Foundation

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(_ data: Data) throws -> HTTPRequest {
        guard let separator = data.range(of: HTTPWire.headerSeparator) else {
            throw HTTPProblem.malformedRequest
        }
        let headerData = data[..<separator.lowerBound]
        guard headerData.count <= PlanHTTPPolicy.maximumHeaderBytes,
              let headerText = String(data: headerData, encoding: .utf8)
        else {
            throw HTTPProblem.malformedRequest
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw HTTPProblem.malformedRequest
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3, requestParts[2].hasPrefix("HTTP/1.") else {
            throw HTTPProblem.malformedRequest
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                throw HTTPProblem.malformedRequest
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, headers[name] == nil else {
                throw HTTPProblem.malformedRequest
            }
            headers[name] = value
        }

        let body = Data(data[separator.upperBound...])
        let declaredLength = try HTTPRequestFraming.contentLength(in: headers)
        guard body.count == declaredLength else {
            throw HTTPProblem.malformedRequest
        }
        return HTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
            body: body
        )
    }
}

enum HTTPRequestFraming {
    static func expectedLength(in data: Data) throws -> Int? {
        guard let separator = data.range(of: HTTPWire.headerSeparator) else {
            guard data.count <= PlanHTTPPolicy.maximumHeaderBytes else {
                throw HTTPProblem.payloadTooLarge
            }
            return nil
        }
        guard separator.lowerBound <= PlanHTTPPolicy.maximumHeaderBytes,
              let headerText = String(data: data[..<separator.lowerBound], encoding: .utf8)
        else {
            throw HTTPProblem.malformedRequest
        }
        let headers = try headerFields(in: headerText)
        let bodyLength = try contentLength(in: headers)
        guard bodyLength <= PlanHTTPPolicy.maximumBodyBytes else {
            throw HTTPProblem.payloadTooLarge
        }
        return separator.upperBound + bodyLength
    }

    static func expectsContinue(in data: Data) -> Bool {
        guard let separator = data.range(of: HTTPWire.headerSeparator),
              let headerText = String(data: data[..<separator.lowerBound], encoding: .utf8),
              let headers = try? headerFields(in: headerText)
        else {
            return false
        }
        return headers["expect"]?.lowercased() == "100-continue"
    }

    static func contentLength(in headers: [String: String]) throws -> Int {
        guard let rawValue = headers["content-length"] else { return 0 }
        guard let value = Int(rawValue), value >= 0 else {
            throw HTTPProblem.malformedRequest
        }
        return value
    }

    private static func headerFields(in text: String) throws -> [String: String] {
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first,
              requestLine.split(separator: " ").count == 3
        else {
            throw HTTPProblem.malformedRequest
        }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                throw HTTPProblem.malformedRequest
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, fields[name] == nil else {
                throw HTTPProblem.malformedRequest
            }
            fields[name] = value
        }
        return fields
    }
}

enum HTTPWire {
    static let headerSeparator = Data("\r\n\r\n".utf8)
}
