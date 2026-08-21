import ForgeDirectorCodex
import Foundation

@main
enum ForgeDirectorCodexSpikeCommand {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2, arguments[0] == "--image" else {
            print("Usage: forge-director-codex-spike --image /path/to/image.jpg")
            Foundation.exit(EXIT_FAILURE)
        }

        do {
            let result = try CodexDirectorSpike().run(
                imageURL: URL(fileURLWithPath: arguments[1]).standardizedFileURL
            )
            print("Codex image-to-plan validation passed")
            print(String(format: "Latency: %.2f seconds", result.elapsedSeconds))
            print("Intent: \(result.plan.intent.rawValue)")
            if let selection = result.plan.selection {
                print("Subject kind: \(selection.kind.rawValue)")
                if let anchor = selection.visualAnchor {
                    print(String(format: "Visual anchor: [%.3f, %.3f]", anchor.x, anchor.y))
                }
            }
            if let frame = result.plan.framing?.targetFrame {
                print(String(
                    format: "Target frame: [%.3f, %.3f, %.3f, %.3f]",
                    frame.x,
                    frame.y,
                    frame.width,
                    frame.height
                ))
            }
            for advice in result.plan.displayAdvice ?? [] {
                print("Advice: \(advice)")
            }
            for warning in result.warnings {
                print("Validation warning: \(warning.field) — \(warning.reason)")
            }
        } catch {
            let description = (error as? LocalizedError)?.errorDescription
                ?? "The Codex image-to-plan validation failed."
            print("Error: \(description)")
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
