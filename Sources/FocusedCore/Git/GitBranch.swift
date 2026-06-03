import Foundation

/// Lightweight git branch lookup. Returns nil for non-repos, detached HEAD, or any error.
public enum GitBranch {
    public static func currentBranch(in directory: String) -> String? {
        guard directory != "(external)", !directory.isEmpty else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory, "symbolic-ref", "--quiet", "--short", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let branch = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let branch, !branch.isEmpty else { return nil }
        return branch
    }
}
