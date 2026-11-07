import SwiftUI

/// Banner flotante de Liquid Glass que informa del progreso de comprobación de capítulos
/// y notifica de novedades tras el pull-to-refresh.
public struct SyncProgressBanner: View {
    @Environment(AppState.self) private var appState
    
    public init() {}
    
    public var body: some View {
        Group {
            if appState.isCheckingForNewChapters, let status = appState.chapterCheckStatusMessage {
                HStack(spacing: 12) {
                    ProgressView(value: appState.chapterCheckProgress, total: 1.0)
                        .tint(.cyan)
                        .frame(width: 80)
                    
                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassCard(Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let toast = appState.chapterCheckToastMessage {
                HStack(spacing: 8) {
                    Text(toast)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassCard(Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.isCheckingForNewChapters)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.chapterCheckToastMessage)
    }
}
