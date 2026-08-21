import Foundation

struct CodexProcessInvocation: Sendable {
    let arguments: [String]
    let currentDirectoryURL: URL
    let standardOutputURL: URL
    let standardErrorURL: URL
}

typealias CodexProcessRunner = @Sendable (CodexProcessInvocation) throws -> Int32

enum CodexProcessExecution {
    static func run(_ invocation: CodexProcessInvocation) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex"] + invocation.arguments
        process.currentDirectoryURL = invocation.currentDirectoryURL
        process.environment = inheritedEnvironment(from: ProcessInfo.processInfo.environment)

        FileManager.default.createFile(
            atPath: invocation.standardOutputURL.path,
            contents: nil
        )
        FileManager.default.createFile(
            atPath: invocation.standardErrorURL.path,
            contents: nil
        )

        let standardOutput = try FileHandle(forWritingTo: invocation.standardOutputURL)
        let standardError = try FileHandle(forWritingTo: invocation.standardErrorURL)
        defer {
            try? standardOutput.close()
            try? standardError.close()
        }

        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func inheritedEnvironment(from environment: [String: String]) -> [String: String] {
        let allowedKeys = ["CODEX_HOME", "HOME", "LANG", "LC_ALL", "PATH", "TMPDIR"]
        return environment.filter { allowedKeys.contains($0.key) }
    }
}
