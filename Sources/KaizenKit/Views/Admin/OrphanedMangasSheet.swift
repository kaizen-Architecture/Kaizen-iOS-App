import SwiftUI

/// Hoja para gestionar y migrar en lote mangas huérfanos (sin fuente activa, fuente eliminada o fuente caída).
public struct OrphanedMangasSheet: View {
    let apiClient: KaizenAPIClient
    var onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var selectedIds: Set<Int> = []
    @State private var activeSources: [String] = []
    @State private var targetSource: String = ""
    @State private var removeOldSources: Bool = true
    @State private var searchText: String = ""
    @State private var isLoadingSources: Bool = true
    @State private var isRunning: Bool = false
    @State private var errorMessage: String?
    @State private var migrationResult: BatchMigrationResult?

    public init(apiClient: KaizenAPIClient, onSuccess: @escaping () -> Void = {}) {
        self.apiClient = apiClient
        self.onSuccess = onSuccess
    }

    private var isEn: Bool {
        appState.currentLanguage == "en"
    }

    private var orphanedMangas: [Manga] {
        appState.orphanedMangas
    }

    private var filteredMangas: [Manga] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return orphanedMangas }
        return orphanedMangas.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let result = migrationResult {
                    resultsView(result)
                } else {
                    configurationView
                }

                if isRunning {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.cyan)
                        Text(isEn ? "Processing orphaned series..." : "Procesando series huérfanas...")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .kaizenGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .navigationTitle(isEn ? "Orphaned Manga" : "Mangas Huérfanos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Close" : "Cerrar") {
                        dismiss()
                    }
                    .disabled(isRunning)
                }
            }
            .task {
                selectedIds = Set(orphanedMangas.map(\.id))
                await loadSources()
            }
            .alert(isEn ? "Error" : "Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(isEn ? "OK" : "Aceptar", role: .cancel) { errorMessage = nil }
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }

    // MARK: - Vista de Configuración y Selección

    @ViewBuilder
    private var configurationView: some View {
        if orphanedMangas.isEmpty {
            ContentUnavailableView(
                isEn ? "No orphaned manga" : "Sin mangas huérfanos",
                systemImage: "checkmark.seal.fill",
                description: Text(isEn ? "All ongoing series have an active source assigned." : "Todas tus series en emisión tienen una fuente activa asignada.")
            )
        } else {
            List {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                        Text(isEn
                             ? "These series have no active source (removed, failed, or unassigned), so they won't receive chapter updates. Migrate them in batch to another scraper or mark them as standalone."
                             : "Estas series no tienen una fuente activa (eliminada, caída o sin asignar), por lo que no recibirán nuevos capítulos. Migra su fuente en lote o márcalas como independientes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.orange.opacity(0.1))
                }

                Section {
                    if isLoadingSources {
                        HStack {
                            ProgressView().tint(.cyan)
                            Text(isEn ? "Loading active sources..." : "Cargando fuentes activas...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.white.opacity(0.04))
                    } else if activeSources.isEmpty {
                        Text(isEn ? "No active sources available on server." : "No hay fuentes activas disponibles en el servidor.")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .listRowBackground(Color.white.opacity(0.04))
                    } else {
                        Picker(isEn ? "Target Source" : "Fuente de destino", selection: $targetSource) {
                            ForEach(activeSources, id: \.self) { src in
                                Text(src).tag(src)
                            }
                        }
                        .tint(.cyan)
                        .listRowBackground(Color.white.opacity(0.04))

                        Toggle(isEn ? "Remove old sources" : "Eliminar fuentes anteriores", isOn: $removeOldSources)
                            .tint(.cyan)
                            .listRowBackground(Color.white.opacity(0.04))
                    }
                } header: {
                    Text(isEn ? "Batch Migration" : "Migración en Lote")
                }

                Section {
                    HStack {
                        TextField(isEn ? "Filter by title..." : "Filtrar por título...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.04))

                    ForEach(filteredMangas) { manga in
                        Button {
                            toggleSelection(manga.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIds.contains(manga.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIds.contains(manga.id) ? Color.cyan : Color.secondary)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(manga.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)

                                    HStack(spacing: 6) {
                                        Text(orphanReasonLabel(for: manga))
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.18), in: Capsule())
                                            .foregroundStyle(.orange)

                                        if let src = manga.source, !src.isEmpty, src != "NONE" {
                                            Text(src)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.white.opacity(0.04))
                    }
                } header: {
                    HStack {
                        Text(isEn ? "Orphaned Series (\(selectedIds.count)/\(orphanedMangas.count))" : "Series Huérfanas (\(selectedIds.count)/\(orphanedMangas.count))")
                        Spacer()
                        Button(allFilteredSelected ? (isEn ? "Deselect all" : "Deseleccionar") : (isEn ? "Select all" : "Seleccionar todas")) {
                            toggleSelectAllFiltered()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                    }
                }

                Section {
                    Button {
                        Task { await runBatchMigration() }
                    } label: {
                        HStack {
                            Spacer()
                            Label(
                                isEn ? "Migrate \(selectedIds.count) Series" : "Migrar \(selectedIds.count) Series",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(.subheadline.weight(.bold))
                            Spacer()
                        }
                    }
                    .disabled(selectedIds.isEmpty || targetSource.isEmpty || isRunning)
                    .foregroundStyle((selectedIds.isEmpty || targetSource.isEmpty) ? Color.secondary : Color.cyan)
                    .listRowBackground(Color.cyan.opacity(0.14))

                    Button {
                        Task { await markAsStandalone() }
                    } label: {
                        HStack {
                            Spacer()
                            Label(
                                isEn ? "Mark as Standalone" : "Marcar como Independientes",
                                systemImage: "checkmark.shield"
                            )
                            .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                    }
                    .disabled(selectedIds.isEmpty || isRunning)
                    .foregroundStyle(selectedIds.isEmpty ? Color.secondary : Color.teal)
                    .listRowBackground(Color.teal.opacity(0.12))
                } footer: {
                    Text(isEn
                         ? "Marking a series as standalone keeps its downloaded chapters without requiring an active scraper."
                         : "Marcar una serie como independiente conserva sus capítulos descargados sin exigir un scraper activo.")
                        .font(.caption2)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Vista de Resultados

    private func resultsView(_ result: BatchMigrationResult) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: result.failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(result.failedCount == 0 ? .green : .yellow)
                            .font(.title3)
                        Text(result.failedCount == 0
                             ? (isEn ? "Migration completed" : "¡Migración completada!")
                             : (isEn ? "Migration finished with warnings" : "Migración finalizada con avisos"))
                            .font(.headline)
                            .foregroundStyle(.white)
                    }

                    Text(isEn
                         ? "Migrated \(result.successCount) of \(result.total) series to \(targetSource)."
                         : "Se han migrado \(result.successCount) de \(result.total) series a \(targetSource).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.white.opacity(0.04))
            }

            Section(isEn ? "Details" : "Detalles") {
                ForEach(result.results) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(item.success ? .green : .red)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)

                            if item.success {
                                let matched = item.matchedTitle ?? item.title
                                let count = item.chaptersCount ?? 0
                                Text(isEn ? "Matched: \(matched) (\(count) ch.)" : "Coincidencia: \(matched) (\(count) caps.)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let reason = item.reason {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                }
            }

            Section {
                Button {
                    onSuccess()
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Text(isEn ? "Done & Refresh Library" : "Aceptar y Actualizar Biblioteca")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                    }
                }
                .foregroundStyle(.cyan)
                .listRowBackground(Color.cyan.opacity(0.14))
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Helpers

    private var allFilteredSelected: Bool {
        !filteredMangas.isEmpty && filteredMangas.allSatisfy { selectedIds.contains($0.id) }
    }

    private func toggleSelection(_ id: Int) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func toggleSelectAllFiltered() {
        let ids = filteredMangas.map(\.id)
        if allFilteredSelected {
            for id in ids { selectedIds.remove(id) }
        } else {
            for id in ids { selectedIds.insert(id) }
        }
    }

    private func orphanReasonLabel(for manga: Manga) -> String {
        if manga.isSourceFailed {
            return isEn ? "Failed source" : "Fuente caída"
        }
        if manga.isSourceMissing {
            return isEn ? "Missing source" : "Fuente eliminada"
        }
        return isEn ? "No source" : "Sin fuente"
    }

    private func loadSources() async {
        guard let session = appState.session else {
            isLoadingSources = false
            return
        }
        isLoadingSources = true
        defer { isLoadingSources = false }
        do {
            let list = try await apiClient.fetchSourcesList(serverUrl: session.serverUrl, token: session.apiToken)
            let active = list.filter { $0.isActive && !$0.isFailed }.map(\.name)
            activeSources = active
            if targetSource.isEmpty || !active.contains(targetSource) {
                targetSource = active.first ?? ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runBatchMigration() async {
        guard let session = appState.session, !selectedIds.isEmpty, !targetSource.isEmpty else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let res = try await apiClient.batchMigrateSource(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                mangaIds: Array(selectedIds),
                targetSource: targetSource,
                removeOldSources: removeOldSources
            )
            migrationResult = res
            await appState.loadLibrary(client: apiClient, force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markAsStandalone() async {
        guard let session = appState.session, !selectedIds.isEmpty else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            try await apiClient.setAcceptedStandalone(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                mangaIds: Array(selectedIds),
                isAcceptedStandalone: true
            )
            await appState.loadLibrary(client: apiClient, force: true)
            onSuccess()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
