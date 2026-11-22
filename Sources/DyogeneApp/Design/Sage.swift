import DyogeneCore
import SwiftUI

/// Dyogène himself, drawn by `DyogeneArt`. Static: he changes expression with what he looks at,
/// he never animates in a loop (no timer, no redraw while idle).
struct SageFigure: View {
    var expression: DyogeneExpression = .calm
    var glow = true

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                DyogeneArt.draw(in: cg, rect: CGRect(origin: .zero, size: size), expression: expression,
                                glow: glow, detailed: size.width >= 40)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Dyogène, an old sage with a lantern")
    }
}

extension DyogeneExpression {
    init(_ mood: Remark.Mood) {
        self = switch mood {
        case .calm: .calm
        case .curious: .curious
        case .pleased: .pleased
        case .searching: .searching
        }
    }
}

/// Dyogène and what he says, in a speech bubble pointing at him.
struct SageSays: View {
    let text: String
    var expression: DyogeneExpression = .calm
    var size: CGFloat = 52

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            SageFigure(expression: expression, glow: false)
                .frame(width: size, height: size)
            Text(text)
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(SpeechBubble().fill(Color.inset))
                .overlay(SpeechBubble().stroke(Color.stroke))
                .padding(.bottom, size * 0.35)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A rounded bubble with a small tail on its lower left, toward the speaker.
struct SpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 10, style: .continuous)
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 16))
        path.addQuadCurve(to: CGPoint(x: rect.minX - 7, y: rect.maxY + 2), control: CGPoint(x: rect.minX - 2, y: rect.maxY - 4))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 12, y: rect.maxY - 1), control: CGPoint(x: rect.minX + 3, y: rect.maxY + 1))
        path.closeSubpath()
        return path
    }
}
