import Foundation

/// AI-extracted deadline or task from conversations
/// Corresponds to the deadlines table and extract-deadlines Edge Function
public struct Deadline: Codable, Identifiable, Hashable {
    public let id: UUID
    public let messageId: UUID?
    public let conversationId: UUID
    public let userId: UUID
    public let task: String
    public let deadline: Date
    public let category: DeadlineCategory
    public let priority: DeadlinePriority
    public let details: String?
    public var status: DeadlineStatus
    public let createdAt: Date
    public let completedAt: Date?

    // Reminder sync fields
    public var appleReminderId: String?
    public var syncStatus: String?
    public var lastSyncAttempt: Date?
    public var syncError: String?

    public enum DeadlineCategory: String, Codable {
        case school
        case bills
        case chores
        case forms
        case medical
        case work
        case other
    }

    public enum DeadlinePriority: String, Codable, Comparable {
        case urgent
        case high
        case medium
        case low

        public static func < (lhs: DeadlinePriority, rhs: DeadlinePriority) -> Bool {
            let order: [DeadlinePriority] = [.urgent, .high, .medium, .low]
            guard let lhsIndex = order.firstIndex(of: lhs),
                  let rhsIndex = order.firstIndex(of: rhs) else {
                return false
            }
            return lhsIndex < rhsIndex
        }
    }

    public enum DeadlineStatus: String, Codable {
        case pending
        case completed
        case cancelled
    }

    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case conversationId = "conversation_id"
        case userId = "user_id"
        case task
        case deadline
        case category
        case priority
        case details
        case status
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case appleReminderId = "apple_reminder_id"
        case syncStatus = "sync_status"
        case lastSyncAttempt = "last_sync_attempt"
        case syncError = "sync_error"
    }

    public init(
        id: UUID = UUID(),
        messageId: UUID? = nil,
        conversationId: UUID,
        userId: UUID,
        task: String,
        deadline: Date,
        category: DeadlineCategory,
        priority: DeadlinePriority,
        details: String? = nil,
        status: DeadlineStatus = .pending,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        appleReminderId: String? = nil,
        syncStatus: String? = nil,
        lastSyncAttempt: Date? = nil,
        syncError: String? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.conversationId = conversationId
        self.userId = userId
        self.task = task
        self.deadline = deadline
        self.category = category
        self.priority = priority
        self.details = details
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.appleReminderId = appleReminderId
        self.syncStatus = syncStatus
        self.lastSyncAttempt = lastSyncAttempt
        self.syncError = syncError
    }

    /// Get parsed sync status enum
    public var parsedSyncStatus: SyncStatus {
        guard let statusStr = syncStatus else { return .pending }
        return SyncStatus(rawValue: statusStr) ?? .pending
    }

    /// Check if synced to Apple Reminders
    public var isSynced: Bool {
        appleReminderId != nil
    }

    // Custom decoder to handle deadline as string or timestamp
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        messageId = try container.decodeIfPresent(UUID.self, forKey: .messageId)
        conversationId = try container.decode(UUID.self, forKey: .conversationId)
        userId = try container.decode(UUID.self, forKey: .userId)
        task = try container.decode(String.self, forKey: .task)
        category = try container.decode(DeadlineCategory.self, forKey: .category)
        priority = try container.decode(DeadlinePriority.self, forKey: .priority)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        status = try container.decode(DeadlineStatus.self, forKey: .status)
        appleReminderId = try container.decodeIfPresent(String.self, forKey: .appleReminderId)
        syncStatus = try container.decodeIfPresent(String.self, forKey: .syncStatus)
        syncError = try container.decodeIfPresent(String.self, forKey: .syncError)

        // Decode lastSyncAttempt as Date or string
        if let lastSyncDate = try? container.decodeIfPresent(Date.self, forKey: .lastSyncAttempt) {
            lastSyncAttempt = lastSyncDate
        } else if let lastSyncString = try? container.decodeIfPresent(String.self, forKey: .lastSyncAttempt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            lastSyncAttempt = formatter.date(from: lastSyncString)
        } else {
            lastSyncAttempt = nil
        }

        // Try to decode deadline as Date first, then as ISO8601 string
        if let deadlineDate = try? container.decode(Date.self, forKey: .deadline) {
            deadline = deadlineDate
        } else if let deadlineString = try? container.decode(String.self, forKey: .deadline) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = formatter.date(from: deadlineString) {
                deadline = date
            } else {
                // Try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: deadlineString) {
                    deadline = date
                } else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .deadline,
                        in: container,
                        debugDescription: "Unable to parse deadline date from string: \(deadlineString)"
                    )
                }
            }
        } else {
            throw DecodingError.keyNotFound(CodingKeys.deadline, DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Deadline field not found or invalid type"
            ))
        }

        // Try to decode createdAt similarly
        if let createdAtDate = try? container.decode(Date.self, forKey: .createdAt) {
            createdAt = createdAtDate
        } else if let createdAtString = try? container.decode(String.self, forKey: .createdAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            createdAt = formatter.date(from: createdAtString) ?? Date()
        } else {
            createdAt = Date()
        }

        // Decode completedAt similarly
        if let completedAtDate = try? container.decodeIfPresent(Date.self, forKey: .completedAt) {
            completedAt = completedAtDate
        } else if let completedAtString = try? container.decodeIfPresent(String.self, forKey: .completedAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            completedAt = formatter.date(from: completedAtString)
        } else {
            completedAt = nil
        }
    }
}

/// Response from extract-deadlines Edge Function
public struct ExtractDeadlinesResponse: Codable {
    public let deadlines: [DeadlineData]

    public struct DeadlineData: Codable {
        public let messageId: String
        public let task: String
        public let deadline: String // ISO 8601
        public let category: Deadline.DeadlineCategory
        public let priority: Deadline.DeadlinePriority
        public let details: String?
        public let assignedTo: String?
    }
}
