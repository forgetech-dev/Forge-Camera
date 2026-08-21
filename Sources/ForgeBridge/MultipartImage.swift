import Foundation

struct MultipartImage: Sendable, Equatable {
    let data: Data
    let fileExtension: String

    static func extract(from request: HTTPRequest) throws -> MultipartImage {
        guard let contentType = request.headers["content-type"],
              let boundary = boundary(from: contentType)
        else {
            throw HTTPProblem.unsupportedMediaType
        }
        let delimiter = Data("--\(boundary)".utf8)
        var searchStart = request.body.startIndex

        while let delimiterRange = request.body.range(
            of: delimiter,
            in: searchStart ..< request.body.endIndex
        ) {
            let partStart = delimiterRange.upperBound
            guard !request.body[partStart...].starts(with: Data("--".utf8)) else { break }
            let contentStart = request.body[partStart...].starts(with: Data("\r\n".utf8))
                ? partStart + 2
                : partStart
            guard let nextDelimiter = request.body.range(
                of: delimiter,
                in: contentStart ..< request.body.endIndex
            ) else {
                throw HTTPProblem.malformedRequest
            }
            var part = Data(request.body[contentStart ..< nextDelimiter.lowerBound])
            if part.suffix(2) == Data("\r\n".utf8) {
                part.removeLast(2)
            }
            if let image = try imagePart(from: part) {
                return image
            }
            searchStart = nextDelimiter.lowerBound
        }
        throw HTTPProblem.malformedRequest
    }

    private static func imagePart(from part: Data) throws -> MultipartImage? {
        guard let separator = part.range(of: HTTPWire.headerSeparator),
              let headerText = String(data: part[..<separator.lowerBound], encoding: .utf8)
        else {
            throw HTTPProblem.malformedRequest
        }
        let lowercasedHeaders = headerText.lowercased()
        guard lowercasedHeaders.contains("content-disposition: form-data"),
              lowercasedHeaders.contains("name=\"image\"")
        else {
            return nil
        }
        let fileExtension: String
        if lowercasedHeaders.contains("content-type: image/jpeg") {
            fileExtension = "jpg"
        } else if lowercasedHeaders.contains("content-type: image/png") {
            fileExtension = "png"
        } else {
            throw HTTPProblem.unsupportedMediaType
        }
        let data = Data(part[separator.upperBound...])
        guard !data.isEmpty else {
            throw HTTPProblem.malformedRequest
        }
        return MultipartImage(data: data, fileExtension: fileExtension)
    }

    private static func boundary(from contentType: String) -> String? {
        let components = contentType.split(separator: ";", omittingEmptySubsequences: true)
        guard components.first?.trimmingCharacters(in: .whitespaces).lowercased()
            == "multipart/form-data"
        else {
            return nil
        }
        for component in components.dropFirst() {
            let pair = component.split(separator: "=", maxSplits: 1)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "boundary"
            else {
                continue
            }
            let rawValue = pair[1].trimmingCharacters(in: .whitespaces)
            let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !value.isEmpty, value.count <= 70, value.unicodeScalars.allSatisfy(\.isASCII)
            else {
                return nil
            }
            return value
        }
        return nil
    }
}
