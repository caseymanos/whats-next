#if DEBUG
import SwiftUI
import Network

struct DebugView: View {
    @ObservedObject private var debug = DebugSettings.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var syncService = MessageSyncService.shared
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var outboxCount: Int = 0
    @State private var cachedMessageCount: Int = 0
    @State private var localStorageSize: String = "Calculating..."

    var body: some View {
        NavigationStack {
            Form {
                // AI Features Section
                Section("AI Features") {
                    Toggle("Enable AI Tab", isOn: $debug.aiEnabled)
                        .help("Show or hide the AI Insights tab")

                    Toggle("Use Live AI (Supabase)", isOn: $debug.useLiveAI)
                        .help("When enabled, uses real AI service. When disabled, uses mock responses")
                        .disabled(!debug.aiEnabled)
                }

                // Network Status Section
                Section("Network Status") {
                    HStack {
                        Text("Connection")
                        Spacer()
                        Label(
                            networkMonitor.isConnected ? "Online" : "Offline",
                            systemImage: networkMonitor.isConnected ? "wifi" : "wifi.slash"
                        )
                        .foregroundStyle(networkMonitor.isConnected ? .green : .red)
                    }

                    if let connectionType = networkMonitor.connectionType {
                        HStack {
                            Text("Type")
                            Spacer()
                            Text(connectionTypeString(connectionType))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Sync Status Section
                Section("Sync Status") {
                    HStack {
                        Text("Sync Status")
                        Spacer()
                        if syncService.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }

                    if let error = syncService.syncError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Sync Now") {
                        Task {
                            await syncService.syncOutbox()
                        }
                    }
                    .disabled(syncService.isSyncing || !networkMonitor.isConnected)
                }

                // Local Storage Section
                Section("Local Storage") {
                    HStack {
                        Text("Outbox Messages")
                        Spacer()
                        Text("\(outboxCount)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Cached Messages")
                        Spacer()
                        Text("\(cachedMessageCount)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Storage Used")
                        Spacer()
                        Text(localStorageSize)
                            .foregroundStyle(.secondary)
                    }

                    Button("Clear Cache") {
                        clearCache()
                    }
                    .foregroundStyle(.red)
                }

                // Auth & User Section
                Section("Authentication") {
                    if let user = authViewModel.currentUser {
                        HStack {
                            Text("User ID")
                            Spacer()
                            Text(user.id.uuidString.prefix(8) + "...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Username")
                            Spacer()
                            Text(user.username ?? user.email ?? "Unknown")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Status")
                            Spacer()
                            Label("Authenticated", systemImage: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                        }
                    } else {
                        Label("Not Authenticated", systemImage: "xmark.shield.fill")
                            .foregroundStyle(.red)
                    }
                }

                // Error Simulation Section
                Section("Error Simulation") {
                    Picker("Force Error", selection: $debug.forcedError) {
                        ForEach(DebugSettings.ForcedError.allCases) { error in
                            Text(error.rawValue.capitalized)
                                .tag(error)
                        }
                    }

                    if debug.forcedError != .none {
                        Toggle("Sticky Error", isOn: $debug.stickyError)
                            .help("When enabled, error persists until manually cleared")

                        HStack {
                            Text("Retry After")
                            Spacer()
                            Text("\(debug.retryAfterSeconds)s")
                                .foregroundStyle(.secondary)
                        }

                        Stepper("", value: $debug.retryAfterSeconds, in: 5...60, step: 5)
                    }
                }
            }
            .navigationTitle("Debug")
            .task {
                await updateStorageStats()
            }
            .refreshable {
                await updateStorageStats()
            }
        }
    }

    private func connectionTypeString(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        case .wiredEthernet: return "Ethernet"
        case .loopback: return "Loopback"
        case .other: return "Other"
        @unknown default: return "Unknown"
        }
    }

    private func updateStorageStats() async {
        do {
            let localStorage = LocalStorageService.shared
            let outbox = try localStorage.fetchOutboxMessages()
            outboxCount = outbox.count

            // Estimate cached message count (would need proper API)
            cachedMessageCount = 0

            // Calculate storage size
            if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let size = try FileManager.default.allocatedSizeOfDirectory(at: documentsPath)
                localStorageSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            }
        } catch {
            // Error updating stats - show placeholder
            localStorageSize = "Unavailable"
        }
    }

    private func clearCache() {
        Task {
            do {
                let localStorage = LocalStorageService.shared
                try localStorage.clearAll()
                await updateStorageStats()
            } catch {
                // Handle error silently in debug view
            }
        }
    }
}

extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> Int {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]

        var enumerator = self.enumerator(at: url, includingPropertiesForKeys: Array(resourceKeys))!
        var totalSize = 0

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                  resourceValues.isRegularFile == true else {
                continue
            }

            totalSize += resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0
        }

        return totalSize
    }
}
#endif

