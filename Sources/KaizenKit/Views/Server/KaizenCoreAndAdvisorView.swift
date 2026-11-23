import SwiftUI

// MARK: - Kaizen Core (Núcleo Kaizen) Diagnostics, Updater & Settings (#5, #7)

public struct KaizenCoreView: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient

    @State private var response: KaizenCoreSystemResponse?
    @State private var isLoading = true
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var statusBanner: String?

    // Edición de ajuste individual
    @State private var editingItem: KaizenCoreConfigItem?
    @State private var editDraftValue: String = ""

    private var isEn: Bool { appState.currentLanguage == "en" }

    private static let hiddenLegacyPrefixes = ["mangadex.", "tui.", "reader.", "cli.", "icons."]
    private static let exportFormatOptions = ["cbz", "zip", "pdf", "plain"]
    private static let impersonateOptions = ["chrome_133", "chrome_131", "firefox_135", "firefox_133", "safari_16_0", "none"]

    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }

    private var filteredConfig: [KaizenCoreConfigItem] {
        (response?.config ?? []).filter { item in
            !Self.hiddenLegacyPrefixes.contains { item.key.hasPrefix($0) }
        }
    }

    private var formatItems: [KaizenCoreConfigItem] {
        filteredConfig.filter { $0.key.hasPrefix("formats.") }
    }

    private var networkItems: [KaizenCoreConfigItem] {
        filteredConfig.filter { $0.key.hasPrefix("network.") }
    }

    private var headlessItems: [KaizenCoreConfigItem] {
        filteredConfig.filter { $0.key.hasPrefix("headless.") }
    }

    private var otherItems: [KaizenCoreConfigItem] {
        filteredConfig.filter {
            !$0.key.hasPrefix("formats.") && !$0.key.hasPrefix("network.") && !$0.key.hasPrefix("headless.")
        }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let statusBanner {
                    bannerRow(text: statusBanner, tint: .cyan, icon: "checkmark.circle.fill") {
                        self.statusBanner = nil
                    }
                }
                if let errorMessage {
                    bannerRow(text: errorMessage, tint: .red, icon: "exclamationmark.triangle.fill") {
                        self.errorMessage = nil
                    }
                }

                if isLoading && response == nil {
                    VStack(spacing: 12) {
                        ProgressView().tint(.cyan)
                        Text(isEn ? "Loading Kaizen Core diagnostics..." : "Cargando diagnóstico de Núcleo Kaizen...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                } else if let data = response {
                    coreHeaderCard(diagnostics: data.diagnostics)
                    doctorHealthCard(doctor: data.diagnostics.kaizenMangal.doctor)
                    if !filteredConfig.isEmpty {
                        configGroupCard(title: isEn ? "Export Format" : "Formato de Exportación", icon: "doc.zipper", items: formatItems)
                        configGroupCard(title: isEn ? "Network, TLS & Cloudflare" : "Red, TLS y Cloudflare", icon: "network", items: networkItems)
                        configGroupCard(title: isEn ? "Headless Browser" : "Navegador Headless", icon: "safari", items: headlessItems)
                        if !otherItems.isEmpty {
                            configGroupCard(title: isEn ? "Other Settings" : "Otros Ajustes", icon: "slider.horizontal.3", items: otherItems)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        isEn ? "Kaizen Core Unavailable" : "Núcleo Kaizen no disponible",
                        systemImage: "cpu",
                        description: Text(isEn ? "Connect to Kaizen Server v2.0+ to manage Kaizen Core." : "Conéctate a Kaizen Server v2.0+ para gestionar el Núcleo Kaizen.")
                    )
                    .padding(.top, 40)
                }
            }
            .padding(16)
            .padding(.bottom, 30)
        }
        .refreshable {
            await loadCoreStatus()
        }
        .task {
            await loadCoreStatus()
        }
        .sheet(item: $editingItem) { item in
            configEditorSheet(item: item)
        }
    }

    // MARK: - Tarjeta Principal (Versión, Contrato, Update / Rollback)

    private func coreHeaderCard(diagnostics: KaizenCoreDiagnostics) -> some View {
        let km = diagnostics.kaizenMangal
        let vc = diagnostics.versionCheck
        let compatColor = compatibilityTint(for: vc?.compatibilityStatus)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cpu.fill")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                    .frame(width: 44, height: 44)
                    .background(Color.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(isEn ? "Kaizen Core" : "Núcleo Kaizen")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)

                    HStack(spacing: 6) {
                        badgePill(km.version ?? "unknown", tint: .cyan)
                        if let contract = km.contractVersion {
                            badgePill("v\(contract) CLI", tint: .indigo)
                        }
                        if let vc {
                            badgePill(
                                vc.usingManagedBinary
                                    ? (isEn ? "Managed" : "Gestionado")
                                    : (isEn ? "Bundled" : "Integrado"),
                                tint: vc.usingManagedBinary ? .green : .secondary
                            )
                        }
                    }
                }

                Spacer()

                if isMutating {
                    ProgressView().tint(.cyan)
                }
            }

            if let vc {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(compatColor)
                            .frame(width: 8, height: 8)
                        Text(compatibilityLabel(for: vc.compatibilityStatus))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(compatColor)
                        Spacer()
                        if let latest = vc.latestCoreVersion, vc.coreUpdateAvailable {
                            Text("→ \(latest)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.cyan)
                        }
                    }

                    if let msg = vc.compatibilityMessage, !msg.isEmpty {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(compatColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(compatColor.opacity(0.3), lineWidth: 1))
            }

            // Botones de acción: Check Now / Update Core / Rollback
            HStack(spacing: 8) {
                Button {
                    Task { await runCoreCheck() }
                } label: {
                    Label(isEn ? "Check Now" : "Comprobar", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isMutating)

                Button {
                    Task { await runCoreUpdate() }
                } label: {
                    Label(isEn ? "Update Core" : "Actualizar Core", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.cyan.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
                .disabled(isMutating)

                if vc?.canRollback == true {
                    Button {
                        Task { await runCoreRollback() }
                    } label: {
                        Label(isEn ? "Rollback" : "Revertir", systemImage: "arrow.uturn.backward")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(isMutating)
                }
            }
        }
        .padding(16)
        .glassCard(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Tarjeta de Salud (`doctor --json`)

    @ViewBuilder
    private func doctorHealthCard(doctor: KaizenCoreDoctorInfo?) -> some View {
        if let doctor {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(isEn ? "Core Diagnostics" : "Diagnóstico del Núcleo", systemImage: "stethoscope")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    badgePill(
                        doctor.ok ? (isEn ? "Healthy" : "Saludable") : (isEn ? "Warnings" : "Avisos"),
                        tint: doctor.ok ? .green : .orange
                    )
                }

                VStack(spacing: 8) {
                    if let tls = doctor.tlsProfile {
                        doctorRow(
                            icon: "lock.shield",
                            title: isEn ? "TLS Profile" : "Perfil TLS",
                            value: tls.resolved ?? tls.configured ?? "default",
                            ok: true
                        )
                    }
                    if let browser = doctor.browser {
                        doctorRow(
                            icon: "safari",
                            title: isEn ? "Headless Browser" : "Navegador Headless",
                            value: browser.available ? (browser.mode ?? "ready") : (browser.error ?? (isEn ? "Unavailable" : "No disponible")),
                            ok: browser.available
                        )
                    }
                    if let solver = doctor.solver {
                        doctorRow(
                            icon: "cloud.bolt",
                            title: "Cloudflare Solver",
                            value: !solver.configured
                                ? (isEn ? "Not configured" : "Sin configurar")
                                : (solver.reachable ? (isEn ? "Reachable" : "Accesible") : (solver.error ?? (isEn ? "Unreachable" : "Inaccesible"))),
                            ok: !solver.configured || solver.reachable
                        )
                    }
                }

                if !doctor.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(doctor.warnings, id: \.self) { warning in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text(warning)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(16)
            .glassCard(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func doctorRow(icon: String, title: String, value: String, ok: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(ok ? .cyan : .orange)
                .frame(width: 22)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(ok ? .white : .orange)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Grupo de Ajustes de Kaizen Core

    @ViewBuilder
    private func configGroupCard(title: String, icon: String, items: [KaizenCoreConfigItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)

                VStack(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            editingItem = item
                            editDraftValue = item.value
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.key)
                                        .font(.caption.monospaced().weight(.semibold))
                                        .foregroundStyle(.white)
                                    if let desc = item.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(item.value.isEmpty ? "—" : item.value)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.cyan)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .glassCard(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func configEditorSheet(item: KaizenCoreConfigItem) -> some View {
        NavigationStack {
            Form {
                Section(header: Text(item.key)) {
                    if item.key == "formats.use" {
                        Picker(isEn ? "Export Format" : "Formato", selection: $editDraftValue) {
                            ForEach(Self.exportFormatOptions, id: \.self) { opt in
                                Text(opt.uppercased()).tag(opt)
                            }
                        }
                        .pickerStyle(.segmented)
                    } else if item.key == "network.impersonate" {
                        Picker(isEn ? "TLS Profile" : "Perfil TLS", selection: $editDraftValue) {
                            ForEach(Self.impersonateOptions, id: \.self) { opt in
                                Text(opt).tag(opt)
                            }
                        }
                    } else if item.valueType == "boolean" {
                        Toggle(
                            isEn ? "Enabled" : "Activado",
                            isOn: Binding(
                                get: { editDraftValue.lowercased() == "true" },
                                set: { editDraftValue = $0 ? "true" : "false" }
                            )
                        )
                    } else {
                        TextField(isEn ? "Value" : "Valor", text: $editDraftValue)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                if let desc = item.description, !desc.isEmpty {
                    Section(header: Text(isEn ? "Description" : "Descripción")) {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isEn ? "Edit Core Setting" : "Editar Ajuste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Cancel" : "Cancelar") { editingItem = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEn ? "Save" : "Guardar") {
                        let target = item
                        let draft = editDraftValue
                        editingItem = nil
                        Task { await saveConfigItem(target, rawValue: draft) }
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers & Networking

    private func compatibilityTint(for status: String?) -> Color {
        switch status {
        case "up_to_date": return .green
        case "core_update_compatible": return .cyan
        case "kaizen_update_recommended": return .orange
        case "contract_mismatch": return .red
        default: return .secondary
        }
    }

    private func compatibilityLabel(for status: String) -> String {
        switch status {
        case "up_to_date":
            return isEn ? "Up to date" : "Actualizado"
        case "core_update_compatible":
            return isEn ? "Core update available (compatible)" : "Actualización de Core disponible (compatible)"
        case "kaizen_update_recommended":
            return isEn ? "Kaizen Server update recommended" : "Se recomienda actualizar Kaizen Server"
        case "contract_mismatch":
            return isEn ? "Contract mismatch" : "Incompatibilidad de contrato"
        default:
            return status
        }
    }

    private func badgePill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private func bannerRow(text: String, tint: Color, icon: String, onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.caption.weight(.medium)).foregroundStyle(.white)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.35), lineWidth: 1))
    }

    private func loadCoreStatus() async {
        guard let session = appState.session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await apiClient.fetchKaizenCoreStatus(serverUrl: session.serverUrl, token: session.apiToken)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runCoreCheck() async {
        guard let session = appState.session else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            let vc = try await apiClient.checkKaizenCoreUpdates(serverUrl: session.serverUrl, token: session.apiToken)
            statusBanner = vc.compatibilityMessage ?? compatibilityLabel(for: vc.compatibilityStatus)
            await loadCoreStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runCoreUpdate() async {
        guard let session = appState.session else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            let res = try await apiClient.updateKaizenCore(serverUrl: session.serverUrl, token: session.apiToken)
            if res.success {
                statusBanner = res.message ?? (isEn ? "Kaizen Core updated successfully." : "Núcleo Kaizen actualizado correctamente.")
            } else {
                errorMessage = res.error ?? res.message ?? (isEn ? "Core update failed." : "Error al actualizar el núcleo.")
            }
            await loadCoreStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runCoreRollback() async {
        guard let session = appState.session else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            let res = try await apiClient.rollbackKaizenCore(serverUrl: session.serverUrl, token: session.apiToken)
            if res.success {
                statusBanner = res.message ?? (isEn ? "Rolled back Kaizen Core binary." : "Binario de Núcleo Kaizen revertido.")
            } else {
                errorMessage = res.error ?? res.message ?? (isEn ? "Rollback failed." : "Error al revertir.")
            }
            await loadCoreStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveConfigItem(_ item: KaizenCoreConfigItem, rawValue: String) async {
        guard let session = appState.session else { return }
        isMutating = true
        defer { isMutating = false }

        let typedValue: Any
        switch item.valueType {
        case "boolean":
            typedValue = rawValue.lowercased() == "true"
        case "number":
            typedValue = Int(rawValue.trimmingCharacters(in: .whitespaces)) ?? Double(rawValue.trimmingCharacters(in: .whitespaces)) ?? rawValue
        default:
            typedValue = rawValue.trimmingCharacters(in: .whitespaces)
        }

        do {
            try await apiClient.setKaizenCoreConfig(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                key: item.key,
                value: typedValue
            )
            statusBanner = isEn ? "Saved \(item.key)" : "Guardado \(item.key)"
            await loadCoreStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Better Source Advisor (Live Streaming REST v1) (#4, #7)

public struct BetterSourceAdvisorView: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient

    public enum ScanPreset: String, CaseIterable, Identifiable {
        case readingOnly
        case top15
        case top30
        case top50
        case all

        public var id: String { rawValue }
    }

    @State private var status = BetterSourceScanStatus()
    @State private var selectedPreset: ScanPreset = .readingOnly
    @State private var isLoading = true
    @State private var switchingMangaId: Int?
    @State private var switchedMangaIds: Set<Int> = []
    @State private var errorMessage: String?
    @State private var infoBanner: String?

    private var isEn: Bool { appState.currentLanguage == "en" }

    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let infoBanner {
                    advisorBanner(text: infoBanner, tint: .green, icon: "checkmark.circle.fill") {
                        self.infoBanner = nil
                    }
                }
                if let errorMessage {
                    advisorBanner(text: errorMessage, tint: .red, icon: "exclamationmark.triangle.fill") {
                        self.errorMessage = nil
                    }
                }

                controlCard
                recommendationsSection
            }
            .padding(16)
            .padding(.bottom, 30)
        }
        .refreshable {
            await fetchStatus()
        }
        .task {
            await fetchStatus()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if status.isRunning {
                    await fetchStatus()
                }
            }
        }
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .frame(width: 44, height: 44)
                    .background(Color.purple.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(isEn ? "Better Source Advisor" : "Asesor de Mejores Fuentes")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(
                        isEn
                            ? "Compares real max whole chapter numbers across active Lua sources."
                            : "Compara el número real de capítulo máximo entre tus fuentes Lua activas."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            // Selector de lote
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ScanPreset.allCases) { preset in
                        let isSelected = selectedPreset == preset
                        Button {
                            selectedPreset = preset
                        } label: {
                            Text(presetLabel(preset))
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    isSelected ? Color.purple.opacity(0.32) : Color.white.opacity(0.07),
                                    in: Capsule()
                                )
                                .foregroundStyle(isSelected ? .white : .secondary)
                                .overlay(
                                    Capsule().stroke(isSelected ? Color.purple.opacity(0.7) : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(status.isRunning)
                    }
                }
            }

            if status.isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(status.currentMangaTitle ?? (isEn ? "Scanning..." : "Escaneando..."))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("\(status.processedCount) / \(max(status.totalCount, 1))")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.cyan)
                    }

                    ProgressView(value: status.progressRatio)
                        .tint(.cyan)
                }
                .padding(10)
                .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 10) {
                if status.isRunning {
                    Button(role: .destructive) {
                        Task { await cancelScan() }
                    } label: {
                        Label(isEn ? "Cancel Scan" : "Cancelar Escaneo", systemImage: "stop.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.red.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Task { await startScan() }
                    } label: {
                        Label(isEn ? "Start Live Scan" : "Iniciar Escaneo en Vivo", systemImage: "play.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.purple.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .glassCard(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isEn ? "Recommendations" : "Recomendaciones")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(status.recommendations.count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.2), in: Capsule())
                    .foregroundStyle(.purple)
            }

            if isLoading && status.recommendations.isEmpty {
                ProgressView().tint(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if status.recommendations.isEmpty {
                Text(
                    status.isRunning
                        ? (isEn ? "Searching for better sources..." : "Buscando mejores fuentes...")
                        : (isEn ? "No recommendations yet. Start a scan to compare your active sources." : "Sin recomendaciones todavía. Inicia un escaneo para comparar tus fuentes activas.")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(status.recommendations) { rec in
                        recommendationCard(rec)
                    }
                }
            }
        }
    }

    private func recommendationCard(_ rec: BetterSourceRecommendation) -> some View {
        let isSwitching = switchingMangaId == rec.mangaId
        let isDone = switchedMangaIds.contains(rec.mangaId)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(rec.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if rec.isReading {
                            Text(isEn ? "READING" : "LEYENDO")
                                .font(.system(size: 9, weight: .black))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.2), in: Capsule())
                                .foregroundStyle(.cyan)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("\(rec.currentSource) (Ch. \(rec.currentMaxChapter))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(rec.bestSource) (Ch. \(rec.bestMaxChapter))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                Text("+\(rec.delta) \(isEn ? "ch." : "caps.")")
                    .font(.caption.weight(.black))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(.green)
            }

            Button {
                Task { await switchSource(for: rec) }
            } label: {
                HStack(spacing: 6) {
                    if isSwitching {
                        ProgressView().scaleEffect(0.75).tint(.white)
                    } else {
                        Image(systemName: isDone ? "checkmark.circle.fill" : "arrow.triangle.swap")
                    }
                    Text(
                        isDone
                            ? (isEn ? "Switched & Synced" : "Cambiada y sincronizando")
                            : (isEn ? "Switch Source & Sync" : "Cambiar Fuente y Sincronizar")
                    )
                }
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    isDone ? Color.green.opacity(0.2) : Color.cyan.opacity(0.2),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .foregroundStyle(isDone ? .green : .cyan)
            }
            .buttonStyle(.plain)
            .disabled(isSwitching || isDone)
        }
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func presetLabel(_ preset: ScanPreset) -> String {
        switch preset {
        case .readingOnly:
            let n = status.totalReadingReleasingInLibrary
            return n > 0
                ? (isEn ? "Reading now (\(n))" : "Leyendo (\(n))")
                : (isEn ? "Reading now" : "Leyendo ahora")
        case .top15:
            return isEn ? "Top 15" : "Top 15"
        case .top30:
            return isEn ? "Top 30" : "Top 30"
        case .top50:
            return isEn ? "Top 50" : "Top 50"
        case .all:
            let n = status.totalReleasingInLibrary
            return n > 0
                ? (isEn ? "All releasing (\(n))" : "Todos en emisión (\(n))")
                : (isEn ? "All releasing" : "Todos en emisión")
        }
    }

    private func advisorBanner(text: String, tint: Color, icon: String, onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.caption.weight(.medium)).foregroundStyle(.white)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private func fetchStatus() async {
        guard let session = appState.session else { return }
        defer { isLoading = false }
        do {
            status = try await apiClient.fetchBetterSourceScanStatus(serverUrl: session.serverUrl, token: session.apiToken)
            errorMessage = nil
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startScan() async {
        guard let session = appState.session else { return }
        errorMessage = nil
        switchedMangaIds.removeAll()
        let limit: Int?
        let readingOnly: Bool
        switch selectedPreset {
        case .readingOnly:
            limit = nil; readingOnly = true
        case .top15:
            limit = 15; readingOnly = false
        case .top30:
            limit = 30; readingOnly = false
        case .top50:
            limit = 50; readingOnly = false
        case .all:
            limit = nil; readingOnly = false
        }
        do {
            status = try await apiClient.startBetterSourceScan(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                limit: limit,
                readingOnly: readingOnly
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelScan() async {
        guard let session = appState.session else { return }
        do {
            status = try await apiClient.cancelBetterSourceScan(serverUrl: session.serverUrl, token: session.apiToken)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func switchSource(for rec: BetterSourceRecommendation) async {
        guard let session = appState.session else { return }
        switchingMangaId = rec.mangaId
        defer { switchingMangaId = nil }
        do {
            try await apiClient.switchBetterSource(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                mangaId: rec.mangaId,
                newSource: rec.bestSource,
                newSourceTitle: rec.bestMatchedTitle
            )
            switchedMangaIds.insert(rec.mangaId)
            infoBanner = isEn
                ? "Switched '\(rec.title)' to \(rec.bestSource) and queued sync."
                : "Cambiado '\(rec.title)' a \(rec.bestSource) y sincronización encolada."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
