import Foundation

struct CodexSpikeWorkspace: Sendable {
    let rootURL: URL
    let imageURL: URL
    let outputURL: URL
    let standardOutputURL: URL
    let standardErrorURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
        imageURL = rootURL.appendingPathComponent("planning-image.jpg")
        outputURL = rootURL.appendingPathComponent("plan.json")
        standardOutputURL = rootURL.appendingPathComponent("codex-stdout.txt")
        standardErrorURL = rootURL.appendingPathComponent("codex-stderr.txt")
    }

    static func prepare(imageURL sourceURL: URL) throws -> CodexSpikeWorkspace {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "forge-director-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
        } catch {
            throw CodexDirectorSpikeError.temporaryWorkspaceFailed
        }

        let workspace = CodexSpikeWorkspace(rootURL: rootURL)
        do {
            try PlanningImageSanitizer.sanitize(sourceURL, to: workspace.imageURL)
        } catch let error as CodexDirectorSpikeError {
            workspace.remove()
            throw error
        } catch {
            workspace.remove()
            throw CodexDirectorSpikeError.imageSanitizationFailed
        }
        return workspace
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
