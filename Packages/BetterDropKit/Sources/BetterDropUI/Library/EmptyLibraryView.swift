import SwiftUI

/// What the grid shows before anything's in it: a sleepy little orb and a hint.
public struct EmptyLibraryView: View {
    public var title: LocalizedStringKey
    public var message: LocalizedStringKey

    public init(title: LocalizedStringKey = "Nothing here yet", message: LocalizedStringKey) {
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 16) {
            LightOrb(energy: 0.2)
                .frame(width: 120, height: 120)
            Text(title)
                .font(.brand(20, weight: .semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
        }
        .padding(32)
    }
}
