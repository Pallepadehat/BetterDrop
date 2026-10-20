import SwiftUI

/// The six digits to compare on both screens, on glass, edged with light.
public struct PairingCodeView: View {
    public var code: String
    public var size: CGFloat

    public init(code: String, size: CGFloat = 34) {
        self.code = code
        self.size = size
    }

    public var body: some View {
        HStack(spacing: size * 0.22) {
            ForEach(Array(code.enumerated()), id: \.offset) { index, digit in
                DigitTile(digit: digit, size: size)
                    .padding(.leading, index == 3 ? size * 0.3 : 0)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Code \(code.map(String.init).joined(separator: " "))"))
    }
}

private struct DigitTile: View {
    let digit: Character
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
        Text(String(digit))
            .font(Font.brand(size, weight: .semibold).monospacedDigit())
            .frame(width: size * 1.25, height: size * 1.6)
            .background(Color.white.opacity(0.06), in: shape)
            .overlay(shape.strokeBorder(Glow.text, lineWidth: 1.2).opacity(0.7))
            .transition(.blurReplace)
    }
}

#Preview {
    PairingCodeView(code: "482913")
        .padding()
        .background(.black)
}
