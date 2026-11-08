import SwiftUI

/// Motor visual Liquid Glass de Kaizen (Xcode 26 SDK + Retrocompatibilidad iOS 18):
/// Reproduce fielmente el acabado de cristal ahumado con bisel especular luminoso
/// y píldoras activas en cian neón con halo exterior de los mockups de diseño.
public extension View {
    @ViewBuilder
    func kaizenGlass<S: Shape>(interactive: Bool = false, tint: Color? = nil, in shape: S) -> some View {
        if let tint {
            // Píldora/control activo: Cian neón brillante con reflejo superior y halo exterior
            self
                .background {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.30, green: 0.96, blue: 1.0),
                                tint,
                                tint.opacity(0.88)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .overlay(
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.85),
                                Color.white.opacity(0.25),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                )
                .shadow(color: tint.opacity(0.55), radius: 12, x: 0, y: 0)
                .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
        } else {
            // Superficie de cristal ahumado con refracción nativa iOS 26 + luz interna + bisel especular
            self
                .background {
                    ZStack {
                        if #available(iOS 26.0, *) {
                            Color.clear
                                .glassEffect(
                                    interactive ? .regular.interactive() : .regular,
                                    in: shape
                                )
                        } else {
                            shape.fill(.ultraThinMaterial)
                        }
                        
                        // Reflejo diagonal interno de cristal esmerilado
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.13),
                                    Color.white.opacity(0.05),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
                .overlay(
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                Color.white.opacity(0.15),
                                Color.cyan.opacity(0.18),
                                Color.white.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.15
                    )
                )
                .shadow(color: Color.black.opacity(0.55), radius: 16, x: 0, y: 8)
        }
    }
    
    @ViewBuilder
    func glassCard<S: Shape>(_ shape: S) -> some View {
        self.kaizenGlass(interactive: false, in: shape)
    }
    
    @ViewBuilder
    func kaizenGlassButton(prominent: Bool = false) -> some View {
        self.buttonStyle(GlassFallbackButtonStyle(isProminent: prominent))
    }
    
    /// Resplandor ambiental profundo con foco central y esquinas para que las tarjetas refracten luz real
    @ViewBuilder
    func ambientGlowBackground() -> some View {
        self.background {
            ZStack {
                Color(red: 0.03, green: 0.04, blue: 0.06).ignoresSafeArea()
                
                // Halo superior izquierdo cian
                RadialGradient(
                    colors: [Color.cyan.opacity(0.32), Color.blue.opacity(0.12), .clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 520
                )
                .ignoresSafeArea()
                
                // Nebulosa central azul/cian detrás de las tarjetas principales
                RadialGradient(
                    colors: [Color.cyan.opacity(0.16), Color.indigo.opacity(0.12), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 580
                )
                .ignoresSafeArea()
                
                // Halo inferior derecho índigo/violeta
                RadialGradient(
                    colors: [Color.indigo.opacity(0.32), Color.purple.opacity(0.14), .clear],
                    center: .bottomTrailing,
                    startRadius: 10,
                    endRadius: 540
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
            .padding(.vertical, 9)
            .background {
                ZStack {
                    if isProminent {
                        Capsule().fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.30, green: 0.96, blue: 1.0),
                                    Color.cyan
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
            }
            .foregroundStyle(isProminent ? Color.black : Color.white)
            .overlay(
                Capsule().stroke(
                    LinearGradient(
                        colors: isProminent
                            ? [Color.white.opacity(0.85), Color.cyan.opacity(0.4)]
                            : [Color.white.opacity(0.48), Color.white.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15
                )
            )
            .shadow(
                color: isProminent ? Color.cyan.opacity(0.55) : Color.black.opacity(0.45),
                radius: isProminent ? 12 : 6,
                y: isProminent ? 0 : 3
            )
            .opacity(configuration.isPressed ? 0.78 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
