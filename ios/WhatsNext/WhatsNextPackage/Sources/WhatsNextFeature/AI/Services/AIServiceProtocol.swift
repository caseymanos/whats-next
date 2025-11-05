import Foundation
#if AI_FEATURES

protocol AIServiceProtocol {
    func extractCalendarEvents(conversationId: UUID) async throws -> [CalendarEvent]
    func trackDecisions(conversationId: UUID, daysBack: Int) async throws -> [Decision]
    func detectPriority(conversationId: UUID) async throws -> [PriorityMessage]
    func trackRSVPs(conversationId: UUID) async throws -> (rsvps: [RSVPTracking], summary: TrackRSVPsResponse.RSVPSummary)
    func extractDeadlines(conversationId: UUID, userId: UUID) async throws -> [Deadline]
    func proactiveAssistant(conversationId: UUID, userId: UUID, query: String?) async throws -> ProactiveAssistantResponse
}

#endif


