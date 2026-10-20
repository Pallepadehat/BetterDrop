import SwiftUI

/// What the grid shows before anything's in it.
public struct EmptyLibraryView: View {
    public var message: LocalizedStringKey

    public init(message: LocalizedStringKey) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .light))
                .glowingForeground()
                .symbolEffect(.breathe)
            Text("Nothing here yet")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(40)
    }
}
