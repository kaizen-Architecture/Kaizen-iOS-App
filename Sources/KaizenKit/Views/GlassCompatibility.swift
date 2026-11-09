import SwiftUI

/// Motor visual Cyberpunk Liquid Glass de Kaizen (Xcode 26 SDK + Retrocompatibilidad iOS 18):
/// Proporciona superficies de cristal ahumado con degradado interno, bisel especular cian/blanco,
/// sombra de elevación 3D profunda, píldoras neón y fondo degradado atmosférico.
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
                                Color(red: 0.35, green: 0.98, blue: 1.0),
                                tint,
                                Color(red: 0.0, green: 0.72, blue: 0.92)
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
                                Color.white.opacity(0.90),
                                Color.white.opacity(0.30),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.3
                    )
                )
                .shadow(color: tint.opacity(0.60), radius: 12, x: 0, y: 0)
                .shadow(color: Color.black.opacity(0.45), radius: 6, x: 0, y: 3)
                .contentShape(shape)
        } else {
            // Superficie de cristal ahumado con degradado interno + bisel especular cian/blanco + sombra 3D
            self
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        
                        // Degradado interno de cristal ahumado con tinte cian/azul sutil para dar volumen sobre el fondo
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.16, green: 0.23, blue: 0.34).opacity(0.68),
                                    Color(red: 0.09, green: 0.13, blue: 0.21).opacity(0.76),
                                    Color(red: 0.06, green: 0.08, blue: 0.14).opacity(0.84)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        
                        // Reflejo especular diagonal superior
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.03),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                    }
                }
                .overlay(
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.cyan.opacity(0.40),
                                Color.white.opacity(0.12),
                                Color.cyan.opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.25
                    )
                )
                .shadow(color: Color.black.opacity(0.72), radius: 16, x: 0, y: 9)
                .shadow(color: Color.cyan.opacity(0.10), radius: 10, x: 0, y: 0)
                .contentShape(shape)
        }
    }
    
    @ViewBuilder
    func glassCard<S: Shape>(_ shape: S) -> some View {
        self.kaizenGlass(interactive: false, in: shape)
    }
    
    /// Variante de alto rendimiento a 120 FPS para celdas en cuadrículas densas (`LazyVGrid` en `Library`, `Explore` y `Requests`):
    /// Conserva el mismo acabado Cyberpunk (cristal ahumado cian/azul + reflejo especular + borde neón)
    /// sin instanciar 25 `CABackdropLayer` (`.ultraThinMaterial`) ni múltiples sombras dinámicas por celda.
    @ViewBuilder
    func kaizenCardGlass<S: Shape>(in shape: S) -> some View {
        self
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.22, blue: 0.33).opacity(0.92),
                            Color(red: 0.08, green: 0.12, blue: 0.20).opacity(0.95),
                            Color(red: 0.05, green: 0.07, blue: 0.13).opacity(0.97)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.48),
                            Color.cyan.opacity(0.36),
                            Color.white.opacity(0.10),
                            Color.cyan.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15
                )
            )
            .contentShape(shape)
    }
    
    @ViewBuilder
    func kaizenGlassButton(prominent: Bool = false) -> some View {
        self.buttonStyle(GlassFallbackButtonStyle(isProminent: prominent))
    }
    
    /// Fondo degradado Cyberpunk profundo con nebulosas cian, azul eléctrico y violeta
    /// para que las tarjetas redondeadas de cristal destaquen con relieve y transparencia real.
    @ViewBuilder
    func ambientGlowBackground() -> some View {
        self.background {
            ZStack {
                // Base degradada diagonal (no negro plano)
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.10, blue: 0.20),
                        Color(red: 0.03, green: 0.06, blue: 0.12),
                        Color(red: 0.06, green: 0.04, blue: 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Foco superior izquierdo Cian Neón
                RadialGradient(
                    colors: [Color.cyan.opacity(0.36), Color.blue.opacity(0.16), .clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 560
                )
                .ignoresSafeArea()
                
                // Foco central Azul Eléctrico / Cian detrás de los paneles
                RadialGradient(
                    colors: [Color.cyan.opacity(0.20), Color.indigo.opacity(0.16), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 620
                )
                .ignoresSafeArea()
                
                // Foco inferior derecho Índigo / Violeta Cyberpunk
                RadialGradient(
                    colors: [Color.indigo.opacity(0.38), Color.purple.opacity(0.18), .clear],
                    center: .bottomTrailing,
                    startRadius: 10,
                    endRadius: 560
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
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background {
                ZStack {
                    if isProminent {
                        Capsule().fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.98, blue: 1.0),
                                    Color.cyan,
                                    Color(red: 0.0, green: 0.72, blue: 0.92)
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
                                    Color(red: 0.18, green: 0.25, blue: 0.38).opacity(0.75),
                                    Color(red: 0.08, green: 0.12, blue: 0.20).opacity(0.85)
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
                            ? [Color.white.opacity(0.90), Color.cyan.opacity(0.50)]
                            : [Color.white.opacity(0.55), Color.cyan.opacity(0.30)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
            )
            .shadow(
                color: isProminent ? Color.cyan.opacity(0.60) : Color.black.opacity(0.55),
                radius: isProminent ? 12 : 8,
                y: isProminent ? 0 : 4
            )
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.78 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
