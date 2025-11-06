import Foundation
#if AI_FEATURES
import SwiftUI

@MainActor
final class AIViewModel: ObservableObject {
    @Published var selectedConversations: Set<UUID> = []
    @Published var isAnalyzing = false
    @Published var errorMessage: String?

    // Feature-specific state
    @Published var eventsByConversation: [UUID: [CalendarEvent]] = [:]
    @Published var decisionsByConversation: [UUID: [Decision]] = [:]
    @Published var priorityMessagesByConversation: [UUID: [PriorityMessage]] = [:]
    @Published var rsvpsByConversation: [UUID: [RSVPTracking]] = [:]
    @Published var deadlinesByConversation: [UUID: [Deadline]] = [:]
    @Published var proactiveInsights: ProactiveAssistantResponse?

    // Calendar sync state
    @Published var syncSettings: CalendarSyncSettings?
    @Published var isSyncing = false
    @Published var syncErrorMessage: String?
    @Published var syncProgress: SyncProgress?

    // Sync progress tracking
    public struct SyncProgress {
        public var current: Int
        public var total: Int
        public var currentItem: String
    }

    // Conflict detection state
    @Published var conflictsByConversation: [UUID: [SchedulingConflict]] = [:]
    @Published var isDetectingConflicts = false
    @Published var conflictDetectionError: String?

    // Current user ID (required for user-specific features)
    var currentUserId: UUID?

    // All available conversation IDs (for "show all" functionality)
    private(set) var allConversationIds: [UUID] = []

    // Computed property: When no conversations selected, show all
    var effectiveConversations: Set<UUID> {
        if selectedConversations.isEmpty {
            return Set(allConversationIds)
        }
        return selectedConversations
    }

    /// The conversation ID that will be displayed in ConflictDetectionView
    /// This matches the logic in AITabView where ConflictDetectionView gets the first selected conversation
    var displayedConflictConversationId: UUID? {
        selectedConversations.first ?? allConversationIds.first
    }

    private var service: AIServiceProtocol {
        DebugSettings.shared.useLiveAI ? SupabaseAIService() : MockAIService()
    }

    private let syncEngine = CalendarSyncEngine()
    private let conflictDetectionService = ConflictDetectionService.shared

    // MARK: - Calendar Events
    func analyzeSelectedForEvents() async {
        guard !effectiveConversations.isEmpty else {
            errorMessage = "No conversations available"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        var allExtractedEvents: [CalendarEvent] = []

        for id in selectedConversations {
            do {
                let events = try await service.extractCalendarEvents(conversationId: id)
                eventsByConversation[id] = events
                allExtractedEvents.append(contentsOf: events)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        // Auto-sync after extraction if enabled
        if let settings = syncSettings, settings.autoSyncEnabled, !allExtractedEvents.isEmpty {
            await autoSyncEvents(allExtractedEvents)
        }
    }

    // MARK: - Decisions
    func analyzeSelectedForDecisions(daysBack: Int = 7) async {
        guard !effectiveConversations.isEmpty else {
            errorMessage = "No conversations available"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        for id in effectiveConversations {
            do {
                let decisions = try await service.trackDecisions(conversationId: id, daysBack: daysBack)
                decisionsByConversation[id] = decisions
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Priority Messages
    func analyzeSelectedForPriority() async {
        guard !effectiveConversations.isEmpty else {
            errorMessage = "No conversations available"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        for id in effectiveConversations {
            do {
                let messages = try await service.detectPriority(conversationId: id)
                priorityMessagesByConversation[id] = messages
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - RSVPs
    func analyzeSelectedForRSVPs() async {
        guard !effectiveConversations.isEmpty else {
            errorMessage = "No conversations available"
            return
        }

        guard let userId = currentUserId else {
            errorMessage = "User ID required"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        for id in effectiveConversations {
            do {
                // Call Edge Function to extract and create new RSVPs (conversation-scoped)
                let (_, _) = try await service.trackRSVPs(conversationId: id, userId: userId)
                // Then load ALL RSVPs (both pending AND responded) from database
                await refreshRSVPs(conversationId: id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Deadlines
    func analyzeSelectedForDeadlines() async {
        guard !effectiveConversations.isEmpty else {
            errorMessage = "No conversations available"
            return
        }

        guard let userId = currentUserId else {
            errorMessage = "User ID required"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        for id in effectiveConversations {
            do {
                let deadlines = try await service.extractDeadlines(conversationId: id, userId: userId)
                deadlinesByConversation[id] = deadlines
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Proactive Assistant
    func runProactiveAssistant(conversationId: UUID, query: String? = nil) async {
        guard let userId = currentUserId else {
            errorMessage = "User ID required"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        do {
            let response = try await service.proactiveAssistant(
                conversationId: conversationId,
                userId: userId,
                query: query
            )
            proactiveInsights = response
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - All Features
    func analyzeAll(conversationId: UUID) async {
        guard let userId = currentUserId else {
            errorMessage = "User ID required"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        errorMessage = nil

        // Run all analyses in parallel
        async let events = service.extractCalendarEvents(conversationId: conversationId)
        async let decisions = service.trackDecisions(conversationId: conversationId, daysBack: 7)
        async let priority = service.detectPriority(conversationId: conversationId)
        async let rsvps = service.trackRSVPs(conversationId: conversationId, userId: userId)
        async let deadlines = service.extractDeadlines(conversationId: conversationId, userId: userId)

        do {
            let (evts, decs, pri, (rsvList, _), ddls) = try await (events, decisions, priority, rsvps, deadlines)
            eventsByConversation[conversationId] = evts
            decisionsByConversation[conversationId] = decs
            priorityMessagesByConversation[conversationId] = pri
            rsvpsByConversation[conversationId] = rsvList
            deadlinesByConversation[conversationId] = ddls

            // Auto-sync if enabled
            await autoSyncIfEnabled(events: evts, deadlines: ddls)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Calendar Sync

    /// Load sync settings for current user
    func loadSyncSettings() async {
        guard let userId = currentUserId else { return }

        do {
            syncSettings = try await syncEngine.fetchSyncSettings(userId: userId)
        } catch {
            // Create default settings if none exist
            syncSettings = try? await syncEngine.createDefaultSettings(userId: userId)
        }
    }

    /// Update sync settings
    func updateSyncSettings(_ settings: CalendarSyncSettings) async throws {
        try await syncEngine.updateSyncSettings(settings)
        syncSettings = settings
    }

    /// Auto-sync events with progress tracking
    private func autoSyncEvents(_ events: [CalendarEvent]) async {
        guard let userId = currentUserId else { return }
        guard let settings = syncSettings, settings.hasAnySyncEnabled else { return }

        // Filter to only pending events (not yet synced)
        let pendingEvents = events.filter { $0.appleCalendarEventId == nil && $0.googleCalendarEventId == nil }
        guard !pendingEvents.isEmpty else { return }

        isSyncing = true
        defer {
            isSyncing = false
            syncProgress = nil
        }
        syncErrorMessage = nil

        for (index, event) in pendingEvents.enumerated() {
            // Update progress
            syncProgress = SyncProgress(
                current: index + 1,
                total: pendingEvents.count,
                currentItem: event.title
            )

            do {
                try await syncEngine.syncCalendarEvent(event, userId: userId)
            } catch {
                syncErrorMessage = error.localizedDescription
                // Continue syncing remaining events even if one fails
            }
        }
    }

    /// Auto-sync events and deadlines if enabled (used by analyzeAll)
    private func autoSyncIfEnabled(events: [CalendarEvent], deadlines: [Deadline]) async {
        guard let userId = currentUserId else { return }
        guard let settings = syncSettings else { return }
        guard settings.autoSyncEnabled && settings.hasAnySyncEnabled else { return }

        isSyncing = true
        defer { isSyncing = false }
        syncErrorMessage = nil

        // Sync events
        for event in events {
            do {
                try await syncEngine.syncCalendarEvent(event, userId: userId)
            } catch {
                syncErrorMessage = error.localizedDescription
            }
        }

        // Sync deadlines
        if settings.appleRemindersEnabled {
            for deadline in deadlines {
                do {
                    try await syncEngine.syncDeadlineToReminders(deadline, userId: userId)
                } catch {
                    syncErrorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Manually sync a specific event
    func syncEvent(_ event: CalendarEvent) async {
        guard let userId = currentUserId else {
            syncErrorMessage = "User ID required"
            return
        }

        isSyncing = true
        defer { isSyncing = false }
        syncErrorMessage = nil

        do {
            try await syncEngine.syncCalendarEvent(event, userId: userId)

            // Refresh events to show updated sync status
            if let conversationId = eventsByConversation.first(where: { $0.value.contains(where: { $0.id == event.id }) })?.key {
                await refreshEvents(conversationId: conversationId)
            }
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    /// Create event in Apple Calendar and return the event ID
    /// This is for the tap-to-open flow where we auto-sync before opening
    func createEventInCalendar(_ event: CalendarEvent) async throws -> String {
        guard let settings = syncSettings else {
            throw NSError(domain: "AIViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sync settings not found"])
        }

        guard settings.appleCalendarEnabled else {
            throw NSError(domain: "AIViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Apple Calendar sync is not enabled"])
        }

        // Get calendar name from category mapping
        let calendarName = settings.calendarName(for: event.category.rawValue)

        // Create event in Calendar app
        let eventKitService = EventKitService()
        let eventId = try await eventKitService.createEvent(from: event, calendarName: calendarName)

        // Update database with the external ID
        let supabase = SupabaseClientService.shared
        try await supabase.database
            .from("calendar_events")
            .update(["apple_calendar_event_id": eventId])
            .eq("id", value: event.id)
            .execute()

        return eventId
    }

    /// Update a specific event with its Apple Calendar ID after syncing
    /// This prevents duplicate calendar entries when tapping the same event multiple times
    func updateEventWithSyncId(eventId: UUID, appleCalendarEventId: String) {
        // Find the event in the dictionary and update it
        for (convId, events) in eventsByConversation {
            if let index = events.firstIndex(where: { $0.id == eventId }) {
                var updatedEvent = events[index]
                updatedEvent.appleCalendarEventId = appleCalendarEventId
                updatedEvent.syncStatus = "synced"

                // Update the array with the modified event
                var updatedEvents = events
                updatedEvents[index] = updatedEvent
                eventsByConversation[convId] = updatedEvents

                print("✅ Updated local event with sync ID: \(appleCalendarEventId)")
                return
            }
        }
    }

    /// Manually sync a specific deadline
    func syncDeadline(_ deadline: Deadline) async {
        guard let userId = currentUserId else {
            syncErrorMessage = "User ID required"
            return
        }

        isSyncing = true
        defer { isSyncing = false }
        syncErrorMessage = nil

        do {
            try await syncEngine.syncDeadlineToReminders(deadline, userId: userId)

            // Refresh deadlines to show updated sync status
            if let conversationId = deadlinesByConversation.first(where: { $0.value.contains(where: { $0.id == deadline.id }) })?.key {
                await refreshDeadlines(conversationId: conversationId)
            }
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    /// Sync all pending items
    func syncAllPending() async {
        guard let userId = currentUserId else {
            syncErrorMessage = "User ID required"
            return
        }

        isSyncing = true
        defer { isSyncing = false }
        syncErrorMessage = nil

        do {
            async let eventsSync = syncEngine.syncAllPendingEvents(userId: userId)
            async let deadlinesSync = syncEngine.syncAllPendingDeadlines(userId: userId)
            try await (eventsSync, deadlinesSync)

            // Automatically trigger conflict detection after successful sync
            await detectConflictsForSelectedConversations()
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    /// Process retry queue
    func processRetryQueue() async {
        guard let userId = currentUserId else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await syncEngine.processSyncQueue(userId: userId)
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    /// Detect external changes from Apple Calendar/Reminders
    func detectExternalChanges() async {
        guard let userId = currentUserId else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            async let calendarChanges = syncEngine.detectAndSyncExternalCalendarChanges(userId: userId)
            async let reminderChanges = syncEngine.detectAndSyncExternalReminderChanges(userId: userId)
            try await (calendarChanges, reminderChanges)
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    /// Refresh events for a conversation (used after sync to update status)
    private func refreshEvents(conversationId: UUID) async {
        do {
            let events = try await service.extractCalendarEvents(conversationId: conversationId)
            eventsByConversation[conversationId] = events
        } catch {
            // Silently fail - this is just a refresh
        }
    }

    /// Refresh deadlines for a conversation (used after sync to update status)
    private func refreshDeadlines(conversationId: UUID) async {
        guard let userId = currentUserId else { return }

        do {
            let deadlines = try await service.extractDeadlines(conversationId: conversationId, userId: userId)
            deadlinesByConversation[conversationId] = deadlines
        } catch {
            // Silently fail - this is just a refresh
        }
    }

    // MARK: - Deadline Actions

    /// Mark a deadline as completed
    func markDeadlineComplete(_ deadline: Deadline) async {
        do {
            let supabase = SupabaseClientService.shared

            // Update status to completed
            let now = ISO8601DateFormatter().string(from: Date())
            try await supabase.database
                .from("deadlines")
                .update([
                    "status": Deadline.DeadlineStatus.completed.rawValue,
                    "completed_at": now
                ])
                .eq("id", value: deadline.id)
                .execute()

            // Update reminder if synced
            if let reminderId = deadline.appleReminderId {
                do {
                    var updatedDeadline = deadline
                    updatedDeadline.status = .completed
                    try await EventKitService().updateReminder(reminderId: reminderId, from: updatedDeadline)
                } catch {
                    // Silently fail reminder update
                }
            }

            // Refresh the deadline list
            if let conversationId = deadlinesByConversation.first(where: { $0.value.contains(where: { $0.id == deadline.id }) })?.key {
                await refreshDeadlines(conversationId: conversationId)
            }
        } catch {
            errorMessage = "Failed to mark as complete: \(error.localizedDescription)"
        }
    }

    /// Mark a deadline as pending (uncomplete)
    func markDeadlinePending(_ deadline: Deadline) async {
        do {
            let supabase = SupabaseClientService.shared

            // Update status to pending and clear completed_at
            try await supabase.database
                .from("deadlines")
                .update([
                    "status": Deadline.DeadlineStatus.pending.rawValue,
                    "completed_at": ""  // Empty string to clear the timestamp
                ])
                .eq("id", value: deadline.id)
                .execute()

            // Update reminder if synced
            if let reminderId = deadline.appleReminderId {
                do {
                    var updatedDeadline = deadline
                    updatedDeadline.status = .pending
                    try await EventKitService().updateReminder(reminderId: reminderId, from: updatedDeadline)
                } catch {
                    // Silently fail reminder update
                }
            }

            // Refresh the deadline list
            if let conversationId = deadlinesByConversation.first(where: { $0.value.contains(where: { $0.id == deadline.id }) })?.key {
                await refreshDeadlines(conversationId: conversationId)
            }
        } catch {
            errorMessage = "Failed to mark as pending: \(error.localizedDescription)"
        }
    }

    // MARK: - RSVP Responses

    /// Respond to an RSVP (yes/no/maybe)
    /// Records which user responded by setting user_id
    func respondToRSVP(_ rsvp: RSVPTracking, status: RSVPTracking.RSVPStatus) async {
        guard let userId = currentUserId else {
            errorMessage = "User ID required to respond"
            return
        }

        do {
            let supabase = SupabaseClientService.shared
            let now = ISO8601DateFormatter().string(from: Date())

            // Update RSVP status, set responded_at timestamp, and record who responded
            try await supabase.database
                .from("rsvp_tracking")
                .update([
                    "status": status.rawValue,
                    "responded_at": now,
                    "user_id": userId.uuidString  // Record who responded to the shared RSVP
                ])
                .eq("id", value: rsvp.id)
                .execute()

            // Create calendar event if user responded "yes" or "maybe"
            if status == .yes || status == .maybe {
                do {
                    let isTentative = (status == .maybe)
                    _ = try await createCalendarEventFromRSVP(rsvp, isTentative: isTentative)
                } catch {
                    // Show error but don't fail the RSVP update
                    errorMessage = "RSVP updated, but calendar event creation failed: \(error.localizedDescription)"
                }
            }

            // Refresh the RSVP list
            if let conversationId = rsvpsByConversation.first(where: { $0.value.contains(where: { $0.id == rsvp.id }) })?.key {
                await refreshRSVPs(conversationId: conversationId)
            }
        } catch {
            errorMessage = "Failed to respond to RSVP: \(error.localizedDescription)"
        }
    }

    /// Create a calendar event from an RSVP
    private func createCalendarEventFromRSVP(_ rsvp: RSVPTracking, isTentative: Bool) async throws -> CalendarEvent {
        guard let userId = currentUserId else {
            throw NSError(domain: "AIViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "User ID required"])
        }

        let supabase = SupabaseClientService.shared

        // Determine event date: Use eventDate if available, otherwise default to 7 days from now
        let eventDate: Date
        if let existingEventDate = rsvp.eventDate {
            eventDate = existingEventDate
        } else {
            eventDate = Date().addingTimeInterval(7 * 86400) // 7 days from now
        }

        // Create CalendarEvent object
        let statusText = isTentative ? "Maybe (Tentative)" : "Yes"
        let description = "RSVP Response: \(statusText)"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: eventDate)

        // Create encodable insert data
        struct InsertEventData: Encodable {
            let id: String
            let conversation_id: String
            let message_id: String?
            let user_id: String
            let title: String
            let date: String
            let time: String?
            let location: String?
            let description: String?
            let category: String
            let confidence: Double
            let confirmed: Bool
            let created_at: String
            let updated_at: String
            let sync_status: String
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let insertData = InsertEventData(
            id: UUID().uuidString,
            conversation_id: rsvp.conversationId.uuidString,
            message_id: rsvp.messageId.uuidString,
            user_id: userId.uuidString,
            title: rsvp.eventName,
            date: dateString,
            time: nil,
            location: nil,
            description: description,
            category: "social",
            confidence: 1.0,
            confirmed: true,
            created_at: now,
            updated_at: now,
            sync_status: "pending"
        )

        try await supabase.database
            .from("calendar_events")
            .insert(insertData)
            .execute()

        // Create CalendarEvent for sync
        let calendarEvent = CalendarEvent(
            id: UUID(uuidString: insertData.id)!,
            conversationId: rsvp.conversationId,
            messageId: rsvp.messageId,
            title: rsvp.eventName,
            date: eventDate,
            time: nil,
            location: nil,
            description: description,
            category: .social,
            confidence: 1.0,
            confirmed: true
        )

        // Sync to Apple Calendar via EventKitService
        do {
            try await syncEvent(calendarEvent)
        } catch {
            // Log error but don't fail - event is still in database
            print("Failed to sync RSVP event to calendar: \(error.localizedDescription)")
        }

        // Refresh events to show the new calendar event
        await refreshEvents(conversationId: rsvp.conversationId)

        return calendarEvent
    }

    /// Refresh RSVPs for a conversation from database
    /// RSVPs are now conversation-scoped (shared), not user-scoped
    private func refreshRSVPs(conversationId: UUID) async {
        do {
            let supabase = SupabaseClientService.shared
            let rsvps: [RSVPTracking] = try await supabase.database
                .from("rsvp_tracking")
                .select()
                .eq("conversation_id", value: conversationId)
                // No user_id filter - RSVPs are shared between conversation participants
                .order("created_at", ascending: false)
                .execute()
                .value

            rsvpsByConversation[conversationId] = rsvps
        } catch {
            print("Failed to refresh RSVPs: \(error.localizedDescription)")
        }
    }

    // MARK: - Conflict Detection

    /// Detect scheduling conflicts for selected conversations
    func detectConflictsForSelectedConversations() async {
        guard !effectiveConversations.isEmpty else { return }

        isDetectingConflicts = true
        defer { isDetectingConflicts = false }
        conflictDetectionError = nil

        for conversationId in effectiveConversations {
            do {
                let result = try await conflictDetectionService.detectConflicts(conversationId: conversationId)
                conflictsByConversation[conversationId] = result.conflicts
            } catch {
                conflictDetectionError = error.localizedDescription
            }
        }
    }

    /// Get total count of unresolved conflicts for the displayed conversation
    /// This matches what ConflictDetectionView will show (only the first selected conversation)
    var totalUnresolvedConflictsCount: Int {
        guard let conversationId = displayedConflictConversationId else { return 0 }

        return conflictsByConversation[conversationId]?
            .filter { $0.status != .resolved }
            .count ?? 0
    }

    /// Get conflicts for a specific conversation
    func conflicts(for conversationId: UUID) -> [SchedulingConflict] {
        conflictsByConversation[conversationId] ?? []
    }

    // MARK: - Conversation Management & Cached Loading

    /// Set available conversations (for "show all" functionality)
    func setAvailableConversations(_ ids: [UUID]) {
        allConversationIds = ids
    }

    /// Load all insights from database (instant - already parsed by backend)
    func loadAllInsights() async {
        guard let userId = currentUserId else { return }
        let conversationIds = Array(effectiveConversations)

        // Load cached insights from database in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadCachedEvents(for: conversationIds) }
            group.addTask { await self.loadCachedDecisions(for: conversationIds) }
            group.addTask { await self.loadCachedPriorityMessages(for: conversationIds) }
            group.addTask { await self.loadCachedRSVPs(for: conversationIds, userId: userId) }
            group.addTask { await self.loadCachedDeadlines(for: conversationIds, userId: userId) }
            group.addTask { await self.loadCachedConflicts(for: conversationIds) }
        }
    }

    /// Load cached events from database
    private func loadCachedEvents(for conversationIds: [UUID]) async {
        let supabase = SupabaseClientService.shared

        for convId in conversationIds {
            do {
                let events: [CalendarEvent] = try await supabase.database
                    .from("calendar_events")
                    .select()
                    .eq("conversation_id", value: convId)
                    .order("date", ascending: true)
                    .execute()
                    .value

                eventsByConversation[convId] = events
            } catch {
                print("Failed to load cached events for conversation \(convId): \(error)")
            }
        }
    }

    /// Load cached decisions from database
    private func loadCachedDecisions(for conversationIds: [UUID]) async {
        let supabase = SupabaseClientService.shared

        for convId in conversationIds {
            do {
                let decisions: [Decision] = try await supabase.database
                    .from("decisions")
                    .select()
                    .eq("conversation_id", value: convId)
                    .order("created_at", ascending: false)
                    .execute()
                    .value

                decisionsByConversation[convId] = decisions
            } catch {
                print("Failed to load cached decisions for conversation \(convId): \(error)")
            }
        }
    }

    /// Load cached priority messages from database
    private func loadCachedPriorityMessages(for conversationIds: [UUID]) async {
        let supabase = SupabaseClientService.shared

        for convId in conversationIds {
            do {
                let messages: [PriorityMessage] = try await supabase.database
                    .from("priority_messages")
                    .select()
                    .eq("conversation_id", value: convId)
                    .order("created_at", ascending: false)
                    .execute()
                    .value

                priorityMessagesByConversation[convId] = messages
            } catch {
                print("Failed to load cached priority messages for conversation \(convId): \(error)")
            }
        }
    }

    /// Load cached RSVPs from database (conversation-scoped, shared)
    private func loadCachedRSVPs(for conversationIds: [UUID], userId: UUID) async {
        let supabase = SupabaseClientService.shared

        for convId in conversationIds {
            do {
                let rsvps: [RSVPTracking] = try await supabase.database
                    .from("rsvp_tracking")
                    .select()
                    .eq("conversation_id", value: convId)
                    // No user_id filter - RSVPs are shared between conversation participants
                    .order("created_at", ascending: false)
                    .execute()
                    .value

                rsvpsByConversation[convId] = rsvps
            } catch {
                print("Failed to load cached RSVPs for conversation \(convId): \(error)")
            }
        }
    }

    /// Load cached deadlines from database
    private func loadCachedDeadlines(for conversationIds: [UUID], userId: UUID) async {
        let supabase = SupabaseClientService.shared

        for convId in conversationIds {
            do {
                let deadlines: [Deadline] = try await supabase.database
                    .from("deadlines")
                    .select()
                    .eq("conversation_id", value: convId)
                    .eq("user_id", value: userId)
                    .order("deadline", ascending: true)
                    .execute()
                    .value

                deadlinesByConversation[convId] = deadlines
            } catch {
                print("Failed to load cached deadlines for conversation \(convId): \(error)")
            }
        }
    }

    /// Load cached conflicts from database
    private func loadCachedConflicts(for conversationIds: [UUID]) async {
        let supabase = SupabaseClientService.shared

        for convId in conversationIds {
            do {
                let responses: [SchedulingConflictResponse] = try await supabase.database
                    .from("scheduling_conflicts")
                    .select()
                    .eq("conversation_id", value: convId.uuidString)
                    .eq("status", value: "unresolved")
                    .order("severity", ascending: false)
                    .execute()
                    .value

                // Convert responses to domain models
                let conflicts = try responses.map { try $0.toDomain() }
                conflictsByConversation[convId] = conflicts
            } catch {
                print("Failed to load cached conflicts for conversation \(convId): \(error)")
            }
        }
    }
}

#endif


