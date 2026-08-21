import ForgeBridge
import ForgeDirectorCodex
import Foundation

@main
enum ForgeServerCommand {
    static func main() {
        let director = CodexDirectorSpike()
        let endpoint = PlanHTTPEndpoint { imageURL in
            try director.run(imageURL: imageURL).plan
        }
        let server = LoopbackHTTPServer(endpoint: endpoint)

        print("forge-server listening on http://127.0.0.1:\(LoopbackHTTPServer.defaultPort)")
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
