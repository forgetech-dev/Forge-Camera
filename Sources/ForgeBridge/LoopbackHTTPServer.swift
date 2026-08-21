import Darwin
import Foundation

/// Startup failures for the development loopback server.
public enum ForgeBridgeError: Error, Sendable, Equatable {
    case socketCreationFailed(code: Int32)
    case bindFailed(code: Int32)
    case listenFailed(code: Int32)
    case acceptFailed(code: Int32)
}

extension ForgeBridgeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .socketCreationFailed(code): "Socket creation failed (errno \(code))."
        case let .bindFailed(code): "Loopback bind failed (errno \(code))."
        case let .listenFailed(code): "Socket listen failed (errno \(code))."
        case let .acceptFailed(code): "Socket accept failed (errno \(code))."
        }
    }
}

/// A deliberately single-request-at-a-time HTTP/1.1 server bound to IPv4 loopback.
///
/// The first slice is synchronous because the upstream planning operation is already
/// coalesced and slow. LAN exposure, concurrency, and pairing are separate later slices.
public struct LoopbackHTTPServer: Sendable {
    /// Fixed development endpoint shared by the server command and curl instructions.
    public static let defaultPort: UInt16 = 8765

    private let port: UInt16
    private let endpoint: PlanHTTPEndpoint

    /// Creates a loopback-only server. No wildcard or LAN bind is possible through this API.
    public init(
        port: UInt16 = LoopbackHTTPServer.defaultPort,
        endpoint: PlanHTTPEndpoint
    ) {
        self.port = port
        self.endpoint = endpoint
    }

    /// Binds `127.0.0.1` and serves until the process is interrupted.
    public func run() throws {
        let listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw ForgeBridgeError.socketCreationFailed(code: errno)
        }
        defer { Darwin.close(listener) }
        try configure(listener: listener)

        while true {
            let client = Darwin.accept(listener, nil, nil)
            if client < 0 {
                if errno == EINTR {
                    continue
                }
                throw ForgeBridgeError.acceptFailed(code: errno)
            }
            serve(client: client)
        }
    }
}

private extension LoopbackHTTPServer {
    func configure(listener: Int32) throws {
        var reuseAddress: Int32 = 1
        _ = withUnsafePointer(to: &reuseAddress) { pointer in
            Darwin.setsockopt(
                listener,
                SOL_SOCKET,
                SO_REUSEADDR,
                pointer,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(
                    listener,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bindResult == 0 else { throw ForgeBridgeError.bindFailed(code: errno) }
        guard Darwin.listen(listener, 4) == 0 else {
            throw ForgeBridgeError.listenFailed(code: errno)
        }
    }

    func serve(client: Int32) {
        defer { Darwin.close(client) }
        var noSignal: Int32 = 1
        _ = withUnsafePointer(to: &noSignal) { pointer in
            Darwin.setsockopt(
                client,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                pointer,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }

        let response: Data
        do {
            response = try endpoint.response(for: readRequest(from: client))
        } catch let problem as HTTPProblem {
            response = HTTPResponse.problem(problem)
        } catch {
            response = HTTPResponse.problem(.malformedRequest)
        }
        send(response, to: client)
    }

    func readRequest(from client: Int32) throws -> Data {
        var request = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        var sentContinue = false

        while true {
            let received = buffer.withUnsafeMutableBytes { bytes in
                Darwin.recv(client, bytes.baseAddress, bytes.count, 0)
            }
            guard received > 0 else { throw HTTPProblem.malformedRequest }
            request.append(contentsOf: buffer.prefix(received))

            if let expectedLength = try HTTPRequestFraming.expectedLength(in: request) {
                if request.count >= expectedLength {
                    return Data(request.prefix(expectedLength))
                }
                if !sentContinue, HTTPRequestFraming.expectsContinue(in: request) {
                    send(Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), to: client)
                    sentContinue = true
                }
            }
        }
    }

    func send(_ data: Data, to client: Int32) {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let sent = Darwin.send(
                    client,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset,
                    0
                )
                guard sent > 0 else { return }
                offset += sent
            }
        }
    }
}
