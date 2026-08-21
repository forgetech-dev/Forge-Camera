import ForgeBridge
import ForgeDirectorCodex
import Foundation

@main
enum ForgeServerCommand {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let binding: DevelopmentServerBinding
        switch arguments {
        case []:
            binding = .loopback
        case ["--lan"]:
            binding = .localNetwork
        default:
            print("Usage: forge-server [--lan]")
            Foundation.exit(EX_USAGE)
        }

        let director = CodexDirectorSpike()
        let endpoint = PlanHTTPEndpoint { imageURL in
            try director.run(imageURL: imageURL).plan
        }
        let server = DevelopmentHTTPServer(binding: binding, endpoint: endpoint)

        let host = binding == .loopback ? "127.0.0.1" : "0.0.0.0"
        print("forge-server listening on http://\(host):\(DevelopmentHTTPServer.defaultPort)")
        if binding == .localNetwork {
            print("Development LAN mode: no application authentication")
        }
        print("GET /health · POST /v1/plan (multipart field: image)")
        do {
            try server.run()
        } catch {
            let description = (error as? LocalizedError)?.errorDescription
                ?? "forge-server failed to start."
            print("Error: \(description)")
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
