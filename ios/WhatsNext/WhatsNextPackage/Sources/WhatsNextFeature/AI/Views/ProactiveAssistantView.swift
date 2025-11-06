import SwiftUI
#if AI_FEATURES

struct ProactiveAssistantView: View {
    @ObservedObject var viewModel: AIViewModel
    @State private var queryText = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    let conversationId: UUID

    private let eventKitUIService = EventKitUIService.shared

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isAnalyzing {
                ProgressView("AI is thinking...")
                    .padding()
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else if let insights = viewModel.proactiveInsights {
                insightsView(insights)
            } else {
                emptyState
            }

            Divider()

            queryInputBar
        }
        .alert("Calendar Action", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            Text("Error")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Try Again") {
                viewModel.errorMessage = nil
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Proactive Assistant")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Ask AI to analyze your conversation and provide insights")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Analyze Now") {
                Task {
                    await viewModel.runProactiveAssistant(conversationId: conversationId)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func insightsView(_ response: ProactiveAssistantResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // AI Summary
                summaryCard(response.message)

                // Upcoming Events
                if let events = response.insights?.upcomingEvents, !events.isEmpty {
                    insightSection(
                        title: "Upcoming Events",
                        icon: "calendar",
                        color: .blue,
                        count: events.count
                    ) {
                        ForEach(events) { event in
                            eventCard(event)
                        }
                    }
                }

                // Pending RSVPs
                if let rsvps = response.insights?.pendingRSVPs, !rsvps.isEmpty {
                    insightSection(
                        title: "Pending RSVPs",
                        icon: "envelope.badge",
                        color: .orange,
                        count: rsvps.count
                    ) {
                        ForEach(rsvps) { rsvp in
                            rsvpCard(rsvp)
                        }
                    }
                }

                // Upcoming Deadlines
                if let deadlines = response.insights?.upcomingDeadlines, !deadlines.isEmpty {
                    insightSection(
                        title: "Upcoming Deadlines",
                        icon: "clock.badge",
                        color: .red,
                        count: deadlines.count
                    ) {
                        ForEach(deadlines) { deadline in
                            deadlineCard(deadline)
                        }
                    }
                }

                // Scheduling Conflicts
                if let conflicts = response.insights?.schedulingConflicts, !conflicts.isEmpty {
                    insightSection(
                        title: "Scheduling Conflicts",
                        icon: "exclamationmark.triangle",
                        color: .red,
                        count: conflicts.count
                    ) {
                        ForEach(conflicts, id: \.self) { conflict in
                            conflictCard(conflict)
                        }
                    }
                }

                // Tools Used
                if let tools = response.toolsUsed, !tools.isEmpty {
                    toolsSection(tools)
                }
            }
            .padding()
        }
    }

    private func summaryCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                Text("AI Summary")
                    .font(.headline)
            }
            Text(message)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func insightSection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func eventCard(_ event: CalendarEvent) -> some View {
        Button {
            print("🟢 BUTTON TAPPED for event: \(event.title)")
            handleEventTap(event)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.subheadline.bold())
                        Text(event.date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if event.isSynced {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rsvpCard(_ rsvp: RSVPTracking) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rsvp.eventName)
                .font(.subheadline.bold())
            if let deadline = rsvp.deadline {
                Text("RSVP by: \(deadline, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private func deadlineCard(_ deadline: Deadline) -> some View {
        Button {
            print("🟢 BUTTON TAPPED for deadline: \(deadline.task)")
            handleDeadlineTap(deadline)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(deadline.task)
                            .font(.subheadline.bold())
                        Text(deadline.deadline, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    if deadline.isSynced {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func conflictCard(_ conflict: ProactiveAssistantResponse.SchedulingConflict) -> some View {
        Button {
            print("🟢 BUTTON TAPPED for conflict: \(conflict.date)")
            handleConflictTap(conflict)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Conflict on \(conflict.date)")
                            .font(.subheadline.bold())
                        Text("\(conflict.event1) vs \(conflict.event2)")
                            .font(.caption)
                        Text(conflict.reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toolsSection(_ tools: [ProactiveAssistantResponse.ToolExecution]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools Used")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack {
                ForEach(tools, id: \.tool) { tool in
                    Text(tool.tool)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                }
            }
        }
    }

    private var queryInputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask AI a question...", text: $queryText)
                .textFieldStyle(.roundedBorder)

            Button {
                guard !queryText.isEmpty else { return }
                Task {
                    await viewModel.runProactiveAssistant(conversationId: conversationId, query: queryText)
                    queryText = ""
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(queryText.isEmpty || viewModel.isAnalyzing)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Event Handlers

    private func handleEventTap(_ event: CalendarEvent) {
        print("🎯 Event tapped: \(event.title)")

        // Get the root view controller first (needed for both sync and opening)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("❌ Could not get root view controller")
            alertMessage = "Unable to open Calendar app"
            showingAlert = true
            return
        }

        // Find the topmost presented view controller
        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }

        Task {
            var eventId = event.appleCalendarEventId

            // If event not synced yet, create it automatically
            if eventId == nil {
                print("⚙️ Event not synced yet - auto-syncing to Calendar")
                do {
                    eventId = try await viewModel.createEventInCalendar(event)
                    print("✅ Event created with ID: \(eventId!)")

                    // Update local event object to prevent duplicates on next tap
                    await MainActor.run {
                        viewModel.updateEventWithSyncId(eventId: event.id, appleCalendarEventId: eventId!)
                    }
                } catch {
                    await MainActor.run {
                        print("❌ Failed to create event: \(error)")
                        alertMessage = "Failed to create event in Calendar: \(error.localizedDescription)"
                        showingAlert = true
                    }
                    return
                }
            } else {
                print("✅ Event already synced with ID: \(eventId!)")
            }

            // Now open the event in Calendar app
            print("🚀 Opening event in Calendar app")
            do {
                try await eventKitUIService.openEvent(eventId: eventId!, from: topController)
            } catch {
                await MainActor.run {
                    print("❌ Failed to open event: \(error)")
                    alertMessage = "Failed to open event: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }

    private func handleDeadlineTap(_ deadline: Deadline) {
        print("🎯 Deadline tapped: \(deadline.task)")

        guard let reminderId = deadline.appleReminderId else {
            // Deadline not synced yet - show message
            print("⚠️ Deadline not synced yet")
            alertMessage = "This deadline hasn't been synced to your Reminders yet. Tap the sync button to add it to your reminders."
            showingAlert = true
            return
        }

        print("✅ Deadline has reminder ID: \(reminderId)")

        // Get the root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("❌ Could not get root view controller")
            alertMessage = "Unable to open Reminders app"
            showingAlert = true
            return
        }

        // Find the topmost presented view controller
        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }

        print("🚀 Opening Reminders app")

        // Open the reminder in Reminders app
        Task {
            do {
                try await eventKitUIService.openReminder(reminderId: reminderId, from: topController)
            } catch {
                await MainActor.run {
                    print("❌ Failed to open reminder: \(error)")
                    alertMessage = "Failed to open reminder: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }

    private func handleConflictTap(_ conflict: ProactiveAssistantResponse.SchedulingConflict) {
        print("🎯 Conflict tapped: \(conflict.date)")

        // Parse the date string and open Calendar app at that date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        guard let date = dateFormatter.date(from: conflict.date) else {
            // If we can't parse the date, just open the calendar app
            print("⚠️ Could not parse date, opening Calendar at today")
            eventKitUIService.openCalendarApp(at: Date())
            return
        }

        print("🚀 Opening Calendar app at date: \(date)")
        eventKitUIService.openCalendarApp(at: date)
    }
}

#endif
