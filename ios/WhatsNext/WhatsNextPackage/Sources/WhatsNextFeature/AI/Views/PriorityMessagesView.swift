import SwiftUI
#if AI_FEATURES

struct PriorityMessagesView: View {
    @ObservedObject var viewModel: AIViewModel

    private var allPriorityMessages: [PriorityMessage] {
        // Only include messages from effectiveConversations (selected or all if none selected)
        viewModel.priorityMessagesByConversation
            .filter { viewModel.effectiveConversations.contains($0.key) }
            .values
            .flatMap { $0 }
            .sorted { $0.priority < $1.priority }
    }

    var body: some View {
        Group {
            if viewModel.isAnalyzing {
                ProgressView("Detecting priority messages...")
            } else if allPriorityMessages.isEmpty {
                emptyState
            } else {
                messagesList
            }
        }
        .refreshable {
            // Refresh triggers new analysis
            await viewModel.analyzeSelectedForPriority()
        }
        .task {
            // Analyze for priority messages (this also loads from database)
            await viewModel.analyzeSelectedForPriority()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No priority messages")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("AI will flag urgent messages requiring attention")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messagesList: some View {
        List {
            ForEach(allPriorityMessages) { message in
                priorityRow(message)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.effectiveConversations)
    }

    private func priorityRow(_ message: PriorityMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            priorityIcon(message.priority)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    priorityBadge(message.priority)
                    if message.actionRequired {
                        Label("Action Required", systemImage: "checkmark.circle")
                            .font(.caption2.bold())
                            .foregroundStyle(.red)
                    }
                }

                Text(message.reason)
                    .font(.body)

                Text(message.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func priorityIcon(_ priority: PriorityMessage.Priority) -> some View {
        Image(systemName: {
            switch priority {
            case .urgent: return "exclamationmark.3"
            case .high: return "exclamationmark.2"
            case .medium: return "exclamationmark"
            }
        }())
        .font(.title2)
        .foregroundStyle(priorityColor(priority))
    }

    private func priorityBadge(_ priority: PriorityMessage.Priority) -> some View {
        Text(priority.rawValue.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(priorityColor(priority).opacity(0.2))
            .foregroundStyle(priorityColor(priority))
            .cornerRadius(4)
    }

    private func priorityColor(_ priority: PriorityMessage.Priority) -> Color {
        switch priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .yellow
        }
    }
}

#endif
