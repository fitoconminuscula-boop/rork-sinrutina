import Foundation

/// Something shared into SinRutina from another app. It waits in a small queue
/// until the app itself applies the business rules and creates a real task.
nonisolated struct SRInboxItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var rawText: String
    var linkURL: String?
    var attachmentName: String?
    var sourceApp: String?
    var createdAt: Date
    var suggestion: SRCaptureSuggestion
    /// What the person chose in the share sheet. `nil` means "guardar y decidir luego".
    var chosenStateRaw: String?

    init(
        id: UUID = UUID(),
        rawText: String,
        linkURL: String? = nil,
        attachmentName: String? = nil,
        sourceApp: String? = nil,
        createdAt: Date = Date(),
        suggestion: SRCaptureSuggestion,
        chosenState: TaskState? = nil
    ) {
        self.id = id
        self.rawText = rawText
        self.linkURL = linkURL
        self.attachmentName = attachmentName
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.suggestion = suggestion
        self.chosenStateRaw = chosenState?.rawValue
    }

    var chosenState: TaskState? {
        guard let chosenStateRaw else { return nil }
        return TaskState(rawValue: chosenStateRaw)
    }
}

nonisolated enum SRShareInbox {
    private static let limit = 40

    static func append(_ item: SRInboxItem) {
        var items = all()
        items.append(item)
        if items.count > limit {
            items = Array(items.suffix(limit))
        }
        save(items)
    }

    static func all() -> [SRInboxItem] {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.inbox),
              let items = try? JSONDecoder().decode([SRInboxItem].self, from: data) else {
            return []
        }
        return items.sorted { $0.createdAt < $1.createdAt }
    }

    static func remove(id: UUID) {
        save(all().filter { $0.id != id })
    }

    static func clear() {
        SRShared.defaults.removeObject(forKey: SRShared.Key.inbox)
    }

    private static func save(_ items: [SRInboxItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.inbox)
    }
}
