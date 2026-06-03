import SwiftUI
import AppKit
import FocusedCore

struct SpawnPickerView: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Spawn shell in…")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if appState.settings.settings.recentDirectories.isEmpty {
                        Text("No recent directories yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.5))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(appState.settings.settings.recentDirectories, id: \.self) { dir in
                            RecentRow(directory: dir) {
                                onPick(dir)
                                dismiss()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 220)

            Divider()

            HStack {
                Button("Choose Directory…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Spawn"
                    if panel.runModal() == .OK, let url = panel.url {
                        onPick(url.path)
                        dismiss()
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 420)
    }
}

private struct RecentRow: View {
    let directory: String
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.45))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(directory.split(separator: "/").last.map(String.init) ?? directory)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.13, green: 0.12, blue: 0.11))
                    Text(directory)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color(white: 0.92) : Color.clear)
                    .padding(.horizontal, 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
