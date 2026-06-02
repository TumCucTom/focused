import Foundation

public enum AppTheme: String, CaseIterable, Sendable, Codable {
    case auto, light, dark
}

public struct Settings: Sendable, Codable, Equatable {
    public var notificationsEnabled: Bool
    public var idleThresholdSeconds: Double
    public var defaultAgentCommand: String
    public var theme: AppTheme
    public var autoFollowIdle: Bool

    public static let `default` = Settings(
        notificationsEnabled: true,
        idleThresholdSeconds: 1.5,
        defaultAgentCommand: "claude",
        theme: .auto,
        autoFollowIdle: true
    )

    private enum CodingKeys: String, CodingKey {
        case notificationsEnabled, idleThresholdSeconds, defaultAgentCommand, theme, autoFollowIdle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.notificationsEnabled = try c.decode(Bool.self, forKey: .notificationsEnabled)
        self.idleThresholdSeconds = try c.decode(Double.self, forKey: .idleThresholdSeconds)
        self.defaultAgentCommand = try c.decode(String.self, forKey: .defaultAgentCommand)
        self.theme = try c.decode(AppTheme.self, forKey: .theme)
        self.autoFollowIdle = try c.decodeIfPresent(Bool.self, forKey: .autoFollowIdle) ?? true
    }

    public init(
        notificationsEnabled: Bool,
        idleThresholdSeconds: Double,
        defaultAgentCommand: String,
        theme: AppTheme,
        autoFollowIdle: Bool
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.idleThresholdSeconds = idleThresholdSeconds
        self.defaultAgentCommand = defaultAgentCommand
        self.theme = theme
        self.autoFollowIdle = autoFollowIdle
    }
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
