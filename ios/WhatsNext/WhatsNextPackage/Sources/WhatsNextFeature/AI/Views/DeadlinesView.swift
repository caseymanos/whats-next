import SwiftUI
#if AI_FEATURES

struct DeadlinesView: View {
    @ObservedObject var viewModel: AIViewModel

    private var allDeadlines: [Deadline] {
        // Only include deadlines from effectiveConversations (selected or all if none selected)
        viewModel.deadlinesByConversation
            .filter { viewModel.effectiveConversations.contains($0.key) }
            .values
            .flatMap { $0 }
            .filter { $0.status == .pending }
            .sorted { $0.deadline < $1.deadline }
    }

    private var overdueDeadlines: [Deadline] {
        allDeadlines.filter { $0.deadline < Date() }
    }

    private var todayDeadlines: [Deadline] {
        allDeadlines.filter { Calendar.current.isDateInToday($0.deadline) }
    }

    private var thisWeekDeadlines: [Deadline] {
        let today = Date()
        let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
        return allDeadlines.filter {
            $0.deadline > today && $0.deadline <= weekFromNow
        }
    }

    private var laterDeadlines: [Deadline] {
        let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return allDeadlines.filter { $0.deadline > weekFromNow }
    }

    var body: some View {
        Group {
            if viewModel.isAnalyzing {
                ProgressView("Finding deadlines...")
            } else if allDeadlines.isEmpty {
                emptyState
            } else {
                deadlinesList
            }
        }
        .refreshable {
            // Refresh triggers new analysis
            await viewModel.analyzeSelectedForDeadlines()
        }
        .task {
            // Analyze for deadlines (this also loads from database)
            await viewModel.analyzeSelectedForDeadlines()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No pending deadlines")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("AI will extract tasks with deadlines from conversations")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deadlinesList: some View {
        List {
            if !overdueDeadlines.isEmpty {
                Section(header: Label("Overdue", systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)) {
                    ForEach(overdueDeadlines) { deadline in
                        deadlineRow(deadline)
                    }
                }
            }

            if !todayDeadlines.isEmpty {
                Section(header: Label("Today", systemImage: "clock.badge.fill").foregroundStyle(.orange)) {
                    ForEach(todayDeadlines) { deadline in
                        deadlineRow(deadline)
                    }
                }
            }

            if !thisWeekDeadlines.isEmpty {
                Section(header: Text("This Week")) {
                    ForEach(thisWeekDeadlines) { deadline in
                        deadlineRow(deadline)
                    }
                }
            }

            if !laterDeadlines.isEmpty {
                Section(header: Text("Later")) {
                    ForEach(laterDeadlines) { deadline in
                        deadlineRow(deadline)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.effectiveConversations)
    }

    private func deadlineRow(_ deadline: Deadline) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task {
                    if deadline.status == .pending {
                        await viewModel.markDeadlineComplete(deadline)
                    } else {
                        await viewModel.markDeadlinePending(deadline)
                    }
                }
            } label: {
                Image(systemName: deadline.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(deadline.status == .completed ? .green : .blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(deadline.task)
                        .font(.body)
                    Spacer()
                    // Sync status indicator
                    syncStatusBadge(deadline.parsedSyncStatus)
                }

                HStack {
                    categoryBadge(deadline.category)
                    priorityBadge(deadline.priority)
                }

                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(deadline.deadline, style: .relative)
                        .font(.caption)
                        .foregroundStyle(deadlineColor(deadline.deadline))
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(deadline.deadline, style: .date)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                if let details = deadline.details {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func syncStatusBadge(_ status: SyncStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .font(.caption)
            if viewModel.isSyncing {
                Text(status.displayName)
                    .font(.caption2)
            }
        }
        .foregroundStyle(status.color)
    }

    private func categoryBadge(_ category: Deadline.DeadlineCategory) -> some View {
        Text(category.rawValue.capitalized)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(categoryColor(category).opacity(0.2))
            .foregroundStyle(categoryColor(category))
            .cornerRadius(4)
    }

    private func priorityBadge(_ priority: Deadline.DeadlinePriority) -> some View {
        Text(priority.rawValue.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor(priority).opacity(0.2))
            .foregroundStyle(priorityColor(priority))
            .cornerRadius(4)
    }

    private func categoryColor(_ category: Deadline.DeadlineCategory) -> Color {
        switch category {
        case .school: return .blue
        case .bills: return .green
        case .chores: return .purple
        case .forms: return .orange
        case .medical: return .red
        case .work: return .cyan
        case .other: return .gray
        }
    }

    private func priorityColor(_ priority: Deadline.DeadlinePriority) -> Color {
        switch priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        }
    }

    private func deadlineColor(_ deadline: Date) -> Color {
        let now = Date()
        if deadline < now {
            return .red
        } else if Calendar.current.isDateInToday(deadline) {
            return .orange
        } else {
            let daysDiff = Calendar.current.dateComponents([.day], from: now, to: deadline).day ?? 0
            return daysDiff < 3 ? .orange : .primary
        }
    }
}

#endif
