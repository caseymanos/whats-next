import SwiftUI
#if AI_FEATURES

struct RSVPView: View {
    @ObservedObject var viewModel: AIViewModel
    @State private var processingRSVPId: UUID?
    @State private var showErrorAlert = false

    private var allRSVPs: [RSVPTracking] {
        // Only include RSVPs from effectiveConversations (selected or all if none selected)
        viewModel.rsvpsByConversation
            .filter { viewModel.effectiveConversations.contains($0.key) }
            .values
            .flatMap { $0 }
            .sorted { ($0.deadline ?? Date.distantFuture) < ($1.deadline ?? Date.distantFuture) }
    }

    private var pendingRSVPs: [RSVPTracking] {
        allRSVPs.filter { $0.status == .pending }
    }

    var body: some View {
        Group {
            if viewModel.isAnalyzing {
                ProgressView("Finding RSVPs...")
            } else if allRSVPs.isEmpty {
                emptyState
            } else {
                rsvpsList
            }
        }
        .refreshable {
            // Refresh triggers new analysis
            await viewModel.analyzeSelectedForRSVPs()
        }
        .task {
            // First analyze for RSVPs (this also loads from database)
            await viewModel.analyzeSelectedForRSVPs()
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Failed to respond to RSVP")
        }
        .onChange(of: viewModel.errorMessage) { newValue in
            if newValue != nil {
                showErrorAlert = true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No RSVPs pending")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("AI will track event invitations requiring responses")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rsvpsList: some View {
        List {
            if !pendingRSVPs.isEmpty {
                Section(header: Label("Pending Responses", systemImage: "clock.badge.exclamationmark")) {
                    ForEach(pendingRSVPs) { rsvp in
                        rsvpRow(rsvp)
                    }
                }
            }

            let respondedRSVPs = allRSVPs.filter { $0.status != .pending }
            if !respondedRSVPs.isEmpty {
                Section(header: Text("Responded")) {
                    ForEach(respondedRSVPs) { rsvp in
                        rsvpRow(rsvp)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.effectiveConversations)
    }

    private func rsvpRow(_ rsvp: RSVPTracking) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(rsvp.eventName)
                    .font(.headline)
                Spacer()
                statusBadge(rsvp.status)
            }

            if let eventDate = rsvp.eventDate {
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                    Text("Event:")
                        .font(.caption)
                    Text(eventDate, style: .date)
                        .font(.caption.bold())
                }
                .foregroundStyle(.secondary)
            }

            if let deadline = rsvp.deadline {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("RSVP by:")
                        .font(.caption)
                    Text(deadline, style: .relative)
                        .font(.caption.bold())
                        .foregroundStyle(deadlineColor(deadline))
                }
                .foregroundStyle(.secondary)
            }

            if rsvp.status == .pending {
                HStack(spacing: 12) {
                    responseButton("Yes", color: .green, rsvp: rsvp)
                    responseButton("No", color: .red, rsvp: rsvp)
                    responseButton("Maybe", color: .orange, rsvp: rsvp)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    private func responseButton(_ label: String, color: Color, rsvp: RSVPTracking) -> some View {
        Button {
            Task {
                processingRSVPId = rsvp.id
                let status: RSVPTracking.RSVPStatus = {
                    switch label {
                    case "Yes": return .yes
                    case "No": return .no
                    case "Maybe": return .maybe
                    default: return .pending
                    }
                }()
                await viewModel.respondToRSVP(rsvp, status: status)
                processingRSVPId = nil
            }
        } label: {
            if processingRSVPId == rsvp.id {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 40)
            } else {
                Text(label)
                    .frame(minWidth: 40)
            }
        }
        .font(.caption.bold())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.2))
        .foregroundStyle(color)
        .cornerRadius(8)
        .disabled(processingRSVPId != nil) // Disable all buttons while processing
    }

    private func statusBadge(_ status: RSVPTracking.RSVPStatus) -> some View {
        Text(status.rawValue.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.2))
            .foregroundStyle(statusColor(status))
            .cornerRadius(4)
    }

    private func statusColor(_ status: RSVPTracking.RSVPStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .yes: return .green
        case .no: return .red
        case .maybe: return .yellow
        }
    }

    private func deadlineColor(_ deadline: Date) -> Color {
        let now = Date()
        let daysDiff = Calendar.current.dateComponents([.day], from: now, to: deadline).day ?? 0

        if daysDiff < 1 {
            return .red
        } else if daysDiff < 3 {
            return .orange
        } else {
            return .primary
        }
    }
}

#endif
