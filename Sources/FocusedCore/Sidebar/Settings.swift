import Foundation

public enum AppTheme: String, CaseIterable, Sendable, Codable {
    case auto, light, dark
}

public struct Settings: Sendable, Codable, Equatable {
    public var notificationsEnabled: Bool
    public var idleThresholdSeconds: Double
    public var defaultAgentCommand: String
    public var theme: AppTheme

    public static let `default` = Settings(
        notificationsEnabled: true,
        idleThresholdSeconds: 1.5,
        defaultAgentCommand: "claude",
        theme: .auto
    )
}

@MainActor
@Observable
public final class SettingsStore {
    private let defaults: UserDefaults
    public private(set) var settings: Settings

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
    }

    public func update(_ mutation: (inout Settings) -> Void) {
        var s = settings
        mutation(&s)
        settings = s
        save()
    }

    private static let key = "FocusedSettings.v1"

    private static func load(from defaults: UserDefaults) -> Settings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data) else {
            return .default
        }
        return decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
