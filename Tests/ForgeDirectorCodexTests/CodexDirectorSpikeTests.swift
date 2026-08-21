import Foundation
import Testing
@testable import ForgeDirectorCodex

@Suite("Codex Director development spike")
struct CodexDirectorSpikeTests {
    @Test("The child process inherits only what CLI auth and execution need")
    func restrictedEnvironment() {
        let inherited = CodexProcessExecution.inheritedEnvironment(from: [
            "CODEX_HOME": "/tmp/codex-home",
            "HOME": "/tmp/home",
            "OPENAI_API_KEY": "must-not-cross-boundary",
            "PATH": "/usr/bin",
            "UNRELATED_TOKEN": "must-not-cross-boundary",
        ])

        #expect(inherited["CODEX_HOME"] == "/tmp/codex-home")
        #expect(inherited["HOME"] == "/tmp/home")
        #expect(inherited["PATH"] == "/usr/bin")
        #expect(inherited["OPENAI_API_KEY"] == nil)
        #expect(inherited["UNRELATED_TOKEN"] == nil)
    }

    @Test("Every strict object schema requires each declared property")
    func strictSchemaRequirements() throws {
        let schemaURL = try #require(CodexDirectorSpike.schemaURL)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL))
        let schema = try #require(object as? [String: Any])

        try assertStrictObjectRequirements(in: schema)
    }

    @Test("The invocation is isolated, non-interactive, ephemeral, and schema constrained")
    func controlledInvocation() {
        let requestID = "00000000-0000-0000-0000-000000000001"
        let workspace = CodexSpikeWorkspace(
            rootURL: URL(fileURLWithPath: "/tmp/forge-director-test")
        )
        let invocation = CodexDirectorSpike.makeInvocation(
            workspace: workspace,
            schemaURL: URL(fileURLWithPath: "/tmp/schema.json"),
            requestID: requestID
        )

        #expect(invocation.arguments.contains("--ephemeral"))
        #expect(invocation.arguments.contains("--ignore-user-config"))
        #expect(argumentValue(after: "--model", in: invocation.arguments) == "gpt-5.6-luna")
        #expect(
            argumentValue(after: "--config", in: invocation.arguments)
                == #"model_verbosity="low""#
        )
        #expect(invocation.arguments.contains("features.fast_mode=true"))
        #expect(invocation.arguments.contains(#"service_tier="fast""#))
        #expect(invocation.arguments.contains("read-only"))
        #expect(invocation.arguments.contains("--output-schema"))
        #expect(invocation.arguments.contains("--output-last-message"))
        #expect(invocation.arguments.contains("/tmp/forge-director-test/planning-image.jpg"))
        #expect(invocation.arguments.last?.contains(requestID) == true)
    }

    @Test("Valid model JSON is decoded and passed through core validation")
    func validatesModelOutput() throws {
        let requestID = "00000000-0000-0000-0000-000000000002"
        let imageURL = try temporaryImage(extension: "jpg")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let spike = CodexDirectorSpike { invocation in
            let outputURL = try #require(argumentValue(
                after: "--output-last-message",
                in: invocation.arguments
            ))
            try Data(Self.validPlanJSON(requestID: requestID).utf8).write(
                to: URL(fileURLWithPath: outputURL)
            )
            return 0
        }

        let result = try spike.run(imageURL: imageURL, requestID: requestID)

        #expect(result.plan.requestId == requestID)
        #expect(result.plan.selection?.kind == .animal)
        #expect(result.plan.selection?.visualAnchor != nil)
        #expect(result.plan.framing?.targetFrame != nil)
        #expect(result.warnings.isEmpty)
    }

    @Test("A mismatched response cannot be attached to the active request")
    func rejectsMismatchedRequest() throws {
        let requestID = "00000000-0000-0000-0000-000000000003"
        let imageURL = try temporaryImage(extension: "png")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let spike = CodexDirectorSpike { invocation in
            let outputURL = try #require(argumentValue(
                after: "--output-last-message",
                in: invocation.arguments
            ))
            try Data(Self.validPlanJSON(
                requestID: "00000000-0000-0000-0000-000000000099"
            ).utf8).write(to: URL(fileURLWithPath: outputURL))
            return 0
        }

        #expect(throws: CodexDirectorSpikeError.responseRequestMismatch) {
            try spike.run(imageURL: imageURL, requestID: requestID)
        }
    }

    @Test("Malformed output fails without repair loops or prose parsing")
    func rejectsMalformedOutput() throws {
        let requestID = "00000000-0000-0000-0000-000000000004"
        let imageURL = try temporaryImage(extension: "jpg")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let spike = CodexDirectorSpike { invocation in
            let outputURL = try #require(argumentValue(
                after: "--output-last-message",
                in: invocation.arguments
            ))
            try Data("not json".utf8).write(to: URL(fileURLWithPath: outputURL))
            return 0
        }

        #expect(throws: CodexDirectorSpikeError.planDecodingFailed) {
            try spike.run(imageURL: imageURL, requestID: requestID)
        }
    }

    @Test("Only JPEG and PNG inputs are accepted")
    func rejectsUnsupportedInput() throws {
        let imageURL = try temporaryImage(extension: "heic")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        #expect(throws: CodexDirectorSpikeError.unsupportedImageFormat) {
            try CodexDirectorSpike().run(imageURL: imageURL)
        }
    }
}

private extension CodexDirectorSpikeTests {
    static func validPlanJSON(requestID: String) -> String {
        """
        {
          "schemaVersion": 1,
          "planId": "plan-1",
          "requestId": "\(requestID)",
          "intent": "environmental_portrait",
          "confidence": 0.84,
          "rationale": "The cat is the strongest subject.",
          "selection": {
            "kind": "animal",
            "label": "cat",
            "sourceRegion": [0.36, 0.28, 0.31, 0.45],
            "visualAnchor": [0.49, 0.36],
            "confidence": 0.91
          },
          "framing": { "targetFrame": [0.16, 0.10, 0.68, 0.80] },
          "displayAdvice": ["Use the eyes as the visual anchor."],
          "expiresAfterSeconds": 30
        }
        """
    }

    func temporaryImage(extension pathExtension: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "forge-codex-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let imageURL = directory.appendingPathComponent("input.\(pathExtension)")
        let onePixelPNG = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        try onePixelPNG.write(to: imageURL)
        return imageURL
    }
}

private func argumentValue(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

private func assertStrictObjectRequirements(in value: Any) throws {
    if let schema = value as? [String: Any] {
        if schema["type"] as? String == "object",
           let properties = schema["properties"] as? [String: Any] {
            let required = try Set(#require(schema["required"] as? [String]))
            #expect(required == Set(properties.keys))
        }
        for nested in schema.values {
            try assertStrictObjectRequirements(in: nested)
        }
    } else if let values = value as? [Any] {
        for nested in values {
            try assertStrictObjectRequirements(in: nested)
        }
    }
}
