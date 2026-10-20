import SwiftUI

/// The logo: a little orb of light and the name.
public struct Wordmark: View {
    public var size: CGFloat
    public var isLit: Bool

    public init(size: CGFloat = 17, isLit: Bool = true) {
        self.size = size
        self.isLit = isLit
    }

    public var body: some View {
        HStack(spacing: size * 0.35) {
            StatusOrb(isLit: isLit)
                .frame(width: size * 1.5, height: size * 1.5)
            Text("BetterDrop")
                .font(.brand(size, weight: .bold))
                .tracking(-0.3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("BetterDrop")
    }
}

/// A small orb that's lit while connected and asleep (grey and still) when not.
public struct StatusOrb: View {
    public var isLit: Bool

    public init(isLit: Bool) {
        self.isLit = isLit
    }

    public var body: some View {
        LightOrb(energy: isLit ? 0.55 : 0, isAnimating: isLit)
            .saturation(isLit ? 1 : 0)
            .opacity(isLit ? 1 : 0.55)
            .scaleEffect(1.5)
            .animation(.smooth(duration: 0.6), value: isLit)
    }
}

#Preview {
    VStack(spacing: 20) {
        Wordmark(size: 28)
        Wordmark(size: 17, isLit: false)
    }
    .padding(40)
    .background(.black)
    .foregroundStyle(.white)
}
