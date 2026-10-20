import SwiftUI

/// The six digits to compare on both screens, set in glowing tiles.
public struct PairingCodeView: View {
    public var code: String

    public init(code: String) {
        self.code = code
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(code.enumerated()), id: \.offset) { index, digit in
                Text(String(digit))
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 58)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Glow.text, lineWidth: 1.5)
                            .opacity(0.8)
                    }
                    .padding(.leading, index == 3 ? 10 : 0)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Code \(code.map(String.init).joined(separator: " "))"))
    }
}

#Preview {
    PairingCodeView(code: "482913")
        .padding()
        .background(.black)
}
