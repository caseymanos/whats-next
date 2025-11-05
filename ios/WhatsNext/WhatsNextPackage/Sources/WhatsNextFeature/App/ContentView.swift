import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var globalRealtimeManager: GlobalRealtimeManager
    @ObservedObject private var debug = DebugSettings.shared
    @State private var selectedTab: Tab = .chats

    public init() {}

    enum Tab: Hashable {
        case chats
        case aiInsights
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            Group {
                // Only show ConversationListView after GlobalRealtimeManager is active
                if authViewModel.isAuthenticated && globalRealtimeManager.isActive {
                    ConversationListView()
                } else if authViewModel.isAuthenticated {
                    // User is authenticated but GlobalRealtimeManager not ready yet
                    ProgressView("Connecting...")
                } else {
                    LoginView()
                }
            }
            .tabItem { Label("Chats", systemImage: "message") }
            .tag(Tab.chats)

            // AI tab appears only when enabled in Debug settings
            #if AI_FEATURES
            if debug.aiEnabled {
                AITabView()
                    .tabItem { Label("AI Insights", systemImage: "sparkles") }
                    .tag(Tab.aiInsights)
            }
            #endif
        }
        .onChange(of: debug.aiEnabled) { oldValue, newValue in
            // If AI tab is being disabled and we're on it, switch to Chats
            if !newValue && selectedTab == .aiInsights {
                selectedTab = .chats
            }
        }
        .onOpenURL { url in
            Task {
                do {
                    try await SupabaseClientService.shared.auth.session(from: url)
                } catch {
                    // Auth URL handling failed - user will need to sign in manually
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}

