import SwiftUI

public struct KaizenGlassToken {
    public static let regular = KaizenGlassToken()
    public func interactive() -> KaizenGlassToken { self }
}

/// Extensión de compatibilidad para estilos Liquid Glass en Xcode 16 / iOS 17-18
/// Proporciona un acabado translúcido de alta gama con doble capa de material y luz especular direccional.
public extension View {
    @ViewBuilder
    func glassCard<S: Shape>(_ shape: S) -> some View {
        self
            .background {
                ZStack {
                    shape.fill(Color.white.opacity(0.04))
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.04),
                            Color.white.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: Color.black.opacity(0.42), radius: 14, x: 0, y: 6)
    }
    
    @ViewBuilder
    func glassEffect<S: Shape>(_ token: KaizenGlassToken = .regular, in shape: S) -> some View {
        self.glassCard(shape)
    }
    
    /// Resplandor ambiental de fondo para interfaces Liquid Glass
    @ViewBuilder
    func ambientGlowBackground() -> some View {
        self.background {
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Halo superior izquierdo cyan tenue
                Circle()
                    .fill(Color.cyan.opacity(0.10))
                    .frame(width: 450, height: 450)
                    .blur(radius: 120)
                    .offset(x: -120, y: -220)
                
                // Halo superior derecho índigo/morado tenue
                Circle()
                    .fill(Color.indigo.opacity(0.08))
                    .frame(width: 480, height: 480)
                    .blur(radius: 130)
                    .offset(x: 140, y: -160)
            }
            .ignoresSafeArea()
        }
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
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.cyan, Color.cyan.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    : AnyShapeStyle(.ultraThinMaterial),
                in: Capsule()
            )
            .foregroundStyle(isProminent ? Color.black : Color.white)
            .overlay(
                Capsule().stroke(
                    LinearGradient(
                        colors: isProminent
                            ? [Color.white.opacity(0.6), Color.clear]
                            : [Color.white.opacity(0.3), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: isProminent ? Color.cyan.opacity(0.35) : Color.black.opacity(0.3), radius: isProminent ? 8 : 4, y: 2)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle(isProminent: false) }
    static var glassProminent: GlassButtonStyle { GlassButtonStyle(isProminent: true) }
}
