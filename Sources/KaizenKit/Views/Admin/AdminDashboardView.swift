import SwiftUI

@MainActor
@Observable
public final class AdminStore {
    public var activeDownloadsCount: Int = 2
    public var queuedCount: Int = 14
    public var circuitBreakerPausedCount: Int = 1
    public var isIntegrationHealthy: Bool = true
    
    // Logs simulados en tiempo real (formato Pino JSON / consola Kaizen)
    public var serverLogs: [String] = [
        "[INFO] [downloadQueue] Worker listening on concurrency 2",
        "[INFO] [auditIntegrityQueue] Integrity sweep verified 24 archives: 0 corrupted",
        "[WARN] [circuitBreaker] Manga ID 42 exceeded 3 consecutive errors. Pausing for 24h cooldown.",
        "[INFO] [kavitaIntegration] Series scan triggered for /data/manga/Jujutsu_Kaisen",
        "[DEBUG] [mangal] Fuzzy match resolved index 1 for Chapter 104"
    ]
    public var logLevel: String = "INFO"
    public var isResettingCircuitBreaker: Bool = false
    
    public init() {}
    
    public func resetCircuitBreaker() async {
        isResettingCircuitBreaker = true
        defer { isResettingCircuitBreaker = false }
        try? await Task.sleep(nanoseconds: 800_000_000)
        circuitBreakerPausedCount = 0
        serverLogs.insert("[INFO] [circuitBreaker] Admin manually reset all paused circuit breakers.", at: 0)
    }
}

public struct AdminDashboardView: View {
    @State private var store = AdminStore()
    let apiClient: KaizenAPIClient
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header de Estado
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Salud del Servidor")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Kaizen Server v1.10.0")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Label("En línea", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                    .padding(.horizontal)
                    
                    // Grid 2x2 de métricas BullMQ y Circuit Breaker
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metricCard(title: "Descargas Activas", value: "\(store.activeDownloadsCount)", icon: "arrow.down.circle.fill", color: .cyan)
                        metricCard(title: "En Cola BullMQ", value: "\(store.queuedCount)", icon: "clock.fill", color: .blue)
                        metricCard(title: "Integraciones", value: "OK", icon: "arrow.triangle.2.circlepath", color: .green)
                        metricCard(title: "Circuit Breaker", value: "\(store.circuitBreakerPausedCount) Pausado", icon: "exclamationmark.triangle.fill", color: .orange)
                    }
                    .padding(.horizontal)
                    
                    // Botón de Reseteo de Circuit Breaker
                    if store.circuitBreakerPausedCount > 0 {
                        Button {
                            Task { await store.resetCircuitBreaker() }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                Text(store.isResettingCircuitBreaker ? "Reiniciando..." : "Resetear Circuit Breaker (Pausados 24h)")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.5), lineWidth: 1))
                            .foregroundStyle(.orange)
                        }
                        .padding(.horizontal)
                        .disabled(store.isResettingCircuitBreaker)
                    }
                    
                    // Terminal de Logs del Servidor en Vivo
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Logs en Tiempo Real", systemImage: "terminal.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Menu("Nivel: \(store.logLevel)") {
                                Button("TRACE") { store.logLevel = "TRACE" }
                                Button("DEBUG") { store.logLevel = "DEBUG" }
                                Button("INFO") { store.logLevel = "INFO" }
                                Button("WARN") { store.logLevel = "WARN" }
                                Button("ERROR") { store.logLevel = "ERROR" }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.cyan)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(store.serverLogs, id: \.self) { log in
                                Text(log)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(logColor(for: log))
                                    .lineLimit(2)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }
                .padding(.top, 8)
            }
            .navigationTitle(String(localized: "tab_admin"))
        }
    }
    
    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    private func logColor(for text: String) -> Color {
        if text.contains("[WARN]") { return .orange }
        if text.contains("[ERROR]") { return .red }
        if text.contains("[DEBUG]") { return .cyan }
        return .green.opacity(0.9)
    }
}
