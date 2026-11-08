import SwiftUI

/// Capa híbrida Liquid Glass (Xcode 26 SDK + Retrocompatibilidad iOS 18):
/// - En iOS 26+: Invoca el motor nativo de Apple (`Glass`, `.glassEffect`, `.buttonStyle(.glass)`).
/// - En iOS 18: Usa fallback translúcido con `.ultraThinMaterial` y borde especular direccional.
public extension View {
    @ViewBuilder
    func kaizenGlass<S: Shape>(interactive: Bool = false, tint: Color? = nil, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                self.glassEffect(
                    interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                    in: shape
                )
            } else {
                self.glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: shape
                )
            }
        } else {
            self.glassCardFallback(shape, tint: tint)
        }
    }
    
    @ViewBuilder
    func glassCard<S: Shape>(_ shape: S) -> some View {
        self.kaizenGlass(interactive: false, in: shape)
    }
    
    @ViewBuilder
    func kaizenGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(GlassFallbackButtonStyle(isProminent: prominent))
        }
    }
    
    @ViewBuilder
    private func glassCardFallback<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        self
            .background {
                ZStack {
                    if let tint {
                        shape.fill(tint.opacity(0.28))
                    } else {
                        shape.fill(Color.white.opacity(0.05))
                    }
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.36),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: Color.black.opacity(0.42), radius: 14, x: 0, y: 6)
    }
    
    /// Resplandor ambiental de fondo para que el Liquid Glass refracte luz y color real
    @ViewBuilder
    func ambientGlowBackground() -> some View {
        self.background {
            ZStack {
                Color.black.ignoresSafeArea()
                
                RadialGradient(
                    colors: [Color.cyan.opacity(0.30), Color.blue.opacity(0.12), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 460
                )
                .ignoresSafeArea()
                
                RadialGradient(
                    colors: [Color.indigo.opacity(0.28), Color.purple.opacity(0.10), .clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 480
                )
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
        }
    }
}

public struct GlassFallbackButtonStyle: ButtonStyle {
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
