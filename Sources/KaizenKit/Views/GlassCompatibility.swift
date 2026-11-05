import SwiftUI

public struct KaizenGlassToken {
    public static let regular = KaizenGlassToken()
    public var interactive: KaizenGlassToken { self }
}

/// Extensión de compatibilidad para estilos Liquid Glass en Xcode 16 / iOS 17-18
/// Proporciona un acabado translúcido idéntico con ultraThinMaterial y bordes sutiles.
public extension View {
    @ViewBuilder
    func glassCard<S: Shape>(_ shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.35), radius: 12, y: 4)
    }
    
    @ViewBuilder
    func glassEffect<S: Shape>(_ token: KaizenGlassToken = .regular, in shape: S) -> some View {
        self.glassCard(shape)
    }
}

public struct GlassButtonStyle: ButtonStyle {
    var isProminent: Bool = false
    
    public init(isProminent: Bool = false) {
        self.isProminent = isProminent
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isProminent
                    ? AnyShapeStyle(Color.cyan)
                    : AnyShapeStyle(.ultraThinMaterial),
                in: Capsule()
            )
            .foregroundStyle(isProminent ? Color.black : Color.white)
            .overlay(
                Capsule().stroke(isProminent ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle(isProminent: false) }
    static var glassProminent: GlassButtonStyle { GlassButtonStyle(isProminent: true) }
}
