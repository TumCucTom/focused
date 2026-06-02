import SwiftUI
import FocusedCore

private typealias AppSettings = FocusedCore.Settings

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 20, weight: .semibold))
            Form {
                Toggle("Notifications", isOn: binding(\.notificationsEnabled))
                HStack {
                    Text("Idle threshold")
                    Slider(value: binding(\.idleThresholdSeconds), in: 0.5...5.0)
                    Text(String(format: "%.1fs", appState.settings.settings.idleThresholdSeconds))
                        .frame(width: 50, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                Toggle("Auto-switch to idle agents", isOn: binding(\.autoFollowIdle))
                TextField("Default agent command", text: binding(\.defaultAgentCommand))
                Picker("Theme", selection: binding(\.theme)) {
                    ForEach(AppTheme.allCases, id: \.self) { t in
                        Text(t.rawValue.capitalized).tag(t)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { appState.settings.settings[keyPath: keyPath] },
            set: { newValue in appState.settings.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
