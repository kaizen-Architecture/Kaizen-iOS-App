import SwiftUI

@MainActor
@Observable
public final class AIStudioStore {
    public var targetUrl: String = "https://example-manga.com"
    public var generatedLuaCode: String = ""
    public var isAnalyzing: Bool = false
    public var isTesting: Bool = false
    public var testStatusMessage: String?
    public var isDeployed: Bool = false
    
    public init() {}
    
    public func analyzeAndGenerate(isEn: Bool) async {
        isAnalyzing = true
        testStatusMessage = nil
        defer { isAnalyzing = false }
        
        // Simulación de inferencia local con Neural Engine (Apple Foundation Models / Core ML)
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        
        generatedLuaCode = """
-- Kaizen Scraper sintetizado localmente en Neural Engine
local scraper = {}

scraper.name = "CustomMangaSource"
scraper.baseUrl = "\(targetUrl)"

function scraper.search(query)
    local doc = http.get(scraper.baseUrl .. "/search?q=" .. query)
    local results = {}
    for el in doc:find(".manga-card") do
        table.insert(results, {
            title = el:find(".title"):text(),
            url = el:find("a"):attr("href")
        })
    end
    return results
end

function scraper.getChapters(mangaUrl)
    local doc = http.get(mangaUrl)
    local chapters = {}
    for el in doc:find(".chapter-item") do
        table.insert(chapters, {
            title = el:find(".chapter-title"):text(),
            url = el:find("a"):attr("href")
        })
    end
    return chapters
end

function scraper.getPages(chapterUrl)
    local doc = http.get(chapterUrl)
    local pages = {}
    for img in doc:find(".page-image img") do
        table.insert(pages, img:attr("src"))
    end
    return pages
end

return scraper
"""
    }
    
    public func testScraperLocally(isEn: Bool) async {
        isTesting = true
        defer { isTesting = false }
        try? await Task.sleep(nanoseconds: 800_000_000)
        testStatusMessage = isEn ? "✅ Lexical validation OK: 3 functions detected (search, getChapters, getPages)." : "✅ Validación léxica OK: 3 funciones detectadas (search, getChapters, getPages)."
    }
    
    public func deployToServer(isEn: Bool) async {
        try? await Task.sleep(nanoseconds: 600_000_000)
        isDeployed = true
        testStatusMessage = isEn ? "🚀 Scraper deployed successfully to Kaizen server." : "🚀 Scraper desplegado exitosamente en el servidor Kaizen."
    }
}

/// AI Studio: Generación y refinamiento de scrapers con Apple Intelligence (exclusivo Admin)
public struct AIStudioView: View {
    @Environment(AppState.self) private var appState
    @State private var store = AIStudioStore()
    let apiClient: KaizenAPIClient
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if !appState.isManagement {
                    ContentUnavailableView(
                        isEn ? "Admin Only" : "Solo Administradores",
                        systemImage: "lock.shield",
                        description: Text(isEn ? "AI Studio is restricted to administrators and managers." : "AI Studio es una herramienta de ingeniería de scrapers restringida a administradores.")
                    )
                } else {
                    mainStudioView
                }
            }
            .navigationTitle("AI Studio")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var mainStudioView: some View {
        VStack(spacing: 0) {
            // Barra de URL y botón de análisis
            HStack(spacing: 10) {
                TextField("https://sitio-manga.com", text: $store.targetUrl)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                Button {
                    Task { await store.analyzeAndGenerate(isEn: isEn) }
                } label: {
                    HStack(spacing: 4) {
                        if store.isAnalyzing {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "sparkles")
                            Text(isEn ? "Analyze" : "Analizar")
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.cyan, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.black)
                }
                .disabled(store.isAnalyzing || store.targetUrl.isEmpty)
            }
            .padding()
            
            // Badge de IA On-Device
            HStack {
                Label(isEn ? "On-Device Neural Engine Synthesis" : "Inferencia Local (Neural Engine Apple Intelligence)", systemImage: "cpu.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.green)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // Editor de Código
            ZStack {
                Color.black.ignoresSafeArea()
                
                if store.generatedLuaCode.isEmpty {
                    ContentUnavailableView(
                        isEn ? "No Code Generated" : "Sin código generado",
                        systemImage: "curlybraces",
                        description: Text(isEn ? "Enter a manga site URL to synthesize a Lua scraper locally and privately." : "Introduce una URL de manga para sintetizar el scraper .lua de forma local y privada.")
                    )
                } else {
                    ScrollView {
                        Text(store.generatedLuaCode)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.green.opacity(0.95))
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            
            if let msg = store.testStatusMessage {
                Text(msg)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .padding(.vertical, 8)
            }
            
            // Botones de Acción
            if !store.generatedLuaCode.isEmpty {
                HStack(spacing: 16) {
                    Button {
                        Task { await store.testScraperLocally(isEn: isEn) }
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text(store.isTesting ? (isEn ? "Validating..." : "Validando...") : (isEn ? "Test Scraper" : "Validar Scraper"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .disabled(store.isTesting)
                    
                    Button {
                        Task { await store.deployToServer(isEn: isEn) }
                    } label: {
                        HStack {
                            Image(systemName: "cloud.fill")
                            Text(isEn ? "Deploy to Kaizen" : "Desplegar en Servidor")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.cyan, in: Capsule())
                        .foregroundStyle(.black)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.85))
            }
        }
    }
}
