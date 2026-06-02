import SwiftUI
import FocusedCore

struct BannerView: View {
    let banner: AppState.Banner
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(banner.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.13, green: 0.12, blue: 0.11))
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 0.89, green: 0.87, blue: 0.83), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var icon: String {
        switch banner.kind {
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch banner.kind {
        case .warning: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .error: return Color(red: 0.94, green: 0.27, blue: 0.27)
        case .info: return Color(red: 0.55, green: 0.36, blue: 0.96)
        }
    }
}

struct EmptyStateBanner: View {
    let title: String
    let message: String
    let command: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(Color(white: 0.4))
            Text(title)
                .font(.system(size: 20, weight: .semibold))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Text(command)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(white: 0.15))
                    )
                    .foregroundStyle(.white)
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy to clipboard")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.98, green: 0.97, blue: 0.96))
        .padding(40)
    }
}
