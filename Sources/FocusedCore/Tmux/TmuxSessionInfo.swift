import Foundation

public struct TmuxSessionInfo: Equatable, Sendable {
    public let name: String
    public let windows: Int
    public let createdAt: Date

    public init(name: String, windows: Int, createdAt: Date) {
        self.name = name
        self.windows = windows
        self.createdAt = createdAt
    }
}
