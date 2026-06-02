import SwiftUI
import FocusedCore

struct SidebarRowView: View {
    let session: AgentSession

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusDot
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(red: 0.55, green: 0.36, blue: 0.96))
                    }
                    Text(session.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(red: 0.13, green: 0.12, blue: 0.11))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(session.shortDirectory)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.45))
                    .lineLimit(1)
                if !session.previewText.isEmpty {
                    Text(session.previewText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.55))
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.clear)
        )
    }

    @ViewBuilder
    private var statusDot: some View {
        switch session.status {
        case .starting:
            Circle()
                .fill(Color(white: 0.7))
                .frame(width: 8, height: 8)
        case .working:
            Circle()
                .fill(Color(red: 1.0, green: 0.48, blue: 0.10))
                .frame(width: 8, height: 8)
        case .idle:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(red: 0.20, green: 0.83, blue: 0.60))
                .font(.system(size: 12))
        case .exited:
            Circle()
                .stroke(Color(white: 0.7), lineWidth: 1.5)
                .frame(width: 8, height: 8)
        }
    }
}
