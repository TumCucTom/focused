import SwiftUI

struct PlaceholderTerminalView: View {
    let sessionName: String?

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            if let name = sessionName {
                Text(name)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text(sessionName == nil
                 ? "Select an agent or press ⌘T to start one"
                 : "Live terminal wiring comes in the next iteration")
                .font(.system(size: 14))
                .foregroundStyle(Color(white: 0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
    }
}
