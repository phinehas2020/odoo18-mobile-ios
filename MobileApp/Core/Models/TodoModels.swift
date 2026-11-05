import Foundation

/// A personal stage from Odoo's To-Do app (Inbox, Today, This Week, …).
struct TodoStage: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let sequence: Int
    let folded: Bool
}

struct TodoTag: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let color: Int
}

struct TodoPerson: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct TodoItem: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var state: String
    var done: Bool
    var closed: Bool
    var starred: Bool
    var dateDeadline: Date?
    var stageId: Int?
    var stageName: String?
    var tags: [TodoTag]
    var assignees: [TodoPerson]
    var hasDescription: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, state, done, closed, starred, tags, assignees
        case dateDeadline = "date_deadline"
        case stageId = "stage_id"
        case stageName = "stage_name"
        case hasDescription = "has_description"
    }

    init(id: Int, name: String, state: String = "01_in_progress", done: Bool = false, closed: Bool = false,
         starred: Bool = false, dateDeadline: Date? = nil, stageId: Int? = nil, stageName: String? = nil,
         tags: [TodoTag] = [], assignees: [TodoPerson] = [], hasDescription: Bool = false) {
        self.id = id; self.name = name; self.state = state; self.done = done; self.closed = closed
        self.starred = starred; self.dateDeadline = dateDeadline; self.stageId = stageId; self.stageName = stageName
        self.tags = tags; self.assignees = assignees; self.hasDescription = hasDescription
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        state = try c.decode(String.self, forKey: .state)
        done = try c.decode(Bool.self, forKey: .done)
        closed = try c.decodeIfPresent(Bool.self, forKey: .closed) ?? done
        starred = try c.decodeIfPresent(Bool.self, forKey: .starred) ?? false
        dateDeadline = try c.decodeIfPresent(Date.self, forKey: .dateDeadline)
        stageId = try c.decodeIfPresent(Int.self, forKey: .stageId)
        stageName = try c.decodeIfPresent(String.self, forKey: .stageName)
        tags = try c.decodeIfPresent([TodoTag].self, forKey: .tags) ?? []
        assignees = try c.decodeIfPresent([TodoPerson].self, forKey: .assignees) ?? []
        hasDescription = try c.decodeIfPresent(Bool.self, forKey: .hasDescription) ?? false
    }

    var isOverdue: Bool {
        guard let dateDeadline, !closed else { return false }
        return dateDeadline < Date()
    }
}

/// Detail payload: the list item plus Odoo's HTML notes.
struct TodoDetail: Decodable {
    var item: TodoItem
    var descriptionHTML: String

    private enum CodingKeys: String, CodingKey { case descriptionHTML = "description_html" }

    init(item: TodoItem, descriptionHTML: String = "") {
        self.item = item
        self.descriptionHTML = descriptionHTML
    }

    init(from decoder: Decoder) throws {
        item = try TodoItem(from: decoder)
        descriptionHTML = try decoder.container(keyedBy: CodingKeys.self)
            .decodeIfPresent(String.self, forKey: .descriptionHTML) ?? ""
    }
}

struct TodoListResponse: Decodable {
    let items: [TodoItem]
    let stages: [TodoStage]
    let truncated: Bool
}

struct TodoCreateRequest: Encodable {
    var name: String
    var descriptionText: String?
    var starred: Bool
    var dateDeadline: Date?
    var stageId: Int?

    enum CodingKeys: String, CodingKey {
        case name, starred
        case descriptionText = "description_text"
        case dateDeadline = "date_deadline"
        case stageId = "stage_id"
    }
}

/// Partial update. Only non-nil fields are sent; `.some(nil)` explicitly clears a value.
struct TodoPatch: Encodable, Equatable {
    var name: String?
    var starred: Bool?
    var done: Bool?
    var stageId: Int?
    var dateDeadline: Date??
    var descriptionText: String??

    enum CodingKeys: String, CodingKey {
        case name, starred, done
        case stageId = "stage_id"
        case dateDeadline = "date_deadline"
        case descriptionText = "description_text"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(starred, forKey: .starred)
        try c.encodeIfPresent(done, forKey: .done)
        try c.encodeIfPresent(stageId, forKey: .stageId)
        if let dateDeadline {
            if let date = dateDeadline { try c.encode(date, forKey: .dateDeadline) } else { try c.encodeNil(forKey: .dateDeadline) }
        }
        if let descriptionText {
            if let text = descriptionText { try c.encode(text, forKey: .descriptionText) } else { try c.encodeNil(forKey: .descriptionText) }
        }
    }
}

enum TodoFilter: String, CaseIterable, Identifiable {
    case open, done
    var id: String { rawValue }
    var title: String { self == .open ? "To do" : "Done" }
}

/// Grouping used by the list: Odoo personal stages, in the user's stage order.
struct TodoSection: Identifiable, Equatable {
    let id: String
    let title: String
    var items: [TodoItem]

    static func group(_ items: [TodoItem], stages: [TodoStage]) -> [TodoSection] {
        var sections: [TodoSection] = []
        let unstaged = items.filter { item in item.stageId == nil || !stages.contains { $0.id == item.stageId } }
        if !unstaged.isEmpty { sections.append(TodoSection(id: "none", title: "No stage", items: unstaged)) }
        for stage in stages.sorted(by: { ($0.sequence, $0.id) < ($1.sequence, $1.id) }) {
            let matching = items.filter { $0.stageId == stage.id }
            if !matching.isEmpty { sections.append(TodoSection(id: "stage-\(stage.id)", title: stage.name, items: matching)) }
        }
        return sections
    }
}
