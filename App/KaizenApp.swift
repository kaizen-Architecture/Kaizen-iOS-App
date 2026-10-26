import SwiftUI

@main
struct KaizenApp: App {
    @State private var appState = AppState()
    private let apiClient = KaizenAPIClient()
    
    var body: some Scene {
        WindowGroup {
            RootAppView(apiClient: apiClient)
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }
}
