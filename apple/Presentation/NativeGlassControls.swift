import SwiftUI

/// Glass belongs to controls, while forms, artwork and reading content keep solid surfaces.
extension View {
    func nativeGlassControl(tint: Color, cornerRadius: CGFloat = 16) -> some View {
        modifier(NativeGlassControl(tint: tint, cornerRadius: cornerRadius))
    }

    func nativeGlassButton(prominent: Bool = false) -> some View {
        modifier(NativeGlassButton(prominent: prominent))
    }
}

private struct NativeGlassControl: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled
    let tint: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        surface(content)
            .opacity(isEnabled ? 1 : 0.5)
            .transaction { if reduceMotion { $0.animation = nil } }
    }

    @ViewBuilder private func surface(_ content: Content) -> some View {
        if #available(iOS 26, tvOS 26, *), !reduceTransparency, contrast != .increased {
            content.foregroundColor(.white)
                .glassEffect(.regular.tint(tint).interactive(!reduceMotion && isEnabled), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content.foregroundColor(.white)
                .background(RoundedRectangle(cornerRadius: cornerRadius).fill(tint))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.primary, lineWidth: contrast == .increased ? 2 : 0))
        }
    }
}

private struct NativeGlassButton: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let prominent: Bool

    func body(content: Content) -> some View {
        styled(content).transaction { if reduceMotion { $0.animation = nil } }
    }

    @ViewBuilder private func styled(_ content: Content) -> some View {
        #if os(tvOS)
        // Native TV buttons adopt glass when focused on supported hardware and keep remote activation intact.
        content.buttonStyle(.bordered)
        #else
        if #available(iOS 26, *), !reduceTransparency, contrast != .increased {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else {
            content.buttonStyle(DefaultButtonStyle())
        }
        #endif
    }
}

#if os(iOS)
extension View {
    func nativeFloatingControl(background: Color) -> some View {
        modifier(NativeFloatingControl(background: background))
    }

    @ViewBuilder func listeningSheet() -> some View {
        if #available(iOS 16, *) {
            presentationDetents([.large]).presentationDragIndicator(.visible)
        } else { self }
    }
}

private struct NativeFloatingControl: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let background: Color

    @ViewBuilder func body(content: Content) -> some View {
        Group {
            if #available(iOS 26, *), !reduceTransparency, contrast != .increased {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
            } else {
                content.background(RoundedRectangle(cornerRadius: 24).fill(background))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary, lineWidth: contrast == .increased ? 2 : 0))
            }
        }.transaction { if reduceMotion { $0.animation = nil } }
    }
}
#endif
