import SwiftUI

/// Native replacement for Odoo's web To-Do app: personal tasks grouped by personal stage.
struct TodoListView: View {
    @EnvironmentObject private var apiProvider: APIClientProvider
    @StateObject private var model = TodoListViewModel()
    @State private var search = ""
    @State private var composing = false
    @State private var pendingDelete: TodoItem?

    var body: some View {
        let sections = model.sections(matching: search)
        List {
            Section {
                HStack(spacing: 4) {
                    ForEach(TodoFilter.allCases) { option in
                        WorkplaceFilterButton(title: option.title, selected: model.filter == option) {
                            Task { await model.setFilter(option, client: apiProvider.client) }
                        }
                    }
                }
            }.listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))

            if let message = model.actionMessage {
                Section {
                    WorkplaceNotice(title: "Change not saved", message: message, symbol: "exclamationmark.triangle", tint: WorkplaceTheme.danger)
                }
            }
            status(isEmpty: sections.isEmpty)
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in row(item) }
                } header: {
                    Text(section.title)
                }
            }
            if model.truncated {
                Section {
                    Text("Showing your first 200 to-dos. Search to find older ones.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .workplaceScreen()
        .navigationTitle("To-do")
        .searchable(text: $search, prompt: "Search to-dos")
        .refreshable { await reload() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { composing = true } label: { Label("New to-do", systemImage: "plus") }
                    .disabled(apiProvider.client == nil)
            }
        }
        .sheet(isPresented: $composing) {
            TodoComposeSheet(stages: model.stages) { request in
                guard let client = apiProvider.client else { throw APIError.invalidResponse }
                _ = try await model.create(request, client: client)
            }
        }
        .confirmationDialog("Delete this to-do?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { item in
            Button("Delete “\(item.name)”", role: .destructive) {
                guard let client = apiProvider.client else { return }
                Task { await model.delete(item, client: client) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It is removed from Odoo for everyone it’s shared with.")
        }
        .task(id: apiProvider.client.map { ObjectIdentifier($0) }) {
            if !model.hasLoaded { await reload() }
        }
    }

    private func row(_ item: TodoItem) -> some View {
        NavigationLink {
            TodoDetailView(taskId: item.id, initial: item, stages: model.stages,
                           onChange: { model.apply($0) }, onDelete: { model.remove(id: $0) })
        } label: {
            TodoRow(item: item, busy: model.isBusy(item.id)) { act { await model.toggleDone(item, client: $0) } }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { act { await model.toggleDone(item, client: $0) } } label: {
                Label(item.done ? "Reopen" : "Done", systemImage: item.done ? "arrow.uturn.backward" : "checkmark")
            }.tint(WorkplaceTheme.buttonFill)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { pendingDelete = item } label: { Label("Delete", systemImage: "trash") }
            Button { act { await model.toggleStar(item, client: $0) } } label: {
                Label(item.starred ? "Unstar" : "Star", systemImage: item.starred ? "star.slash" : "star")
            }.tint(WorkplaceTheme.attention)
        }
        .contextMenu {
            Button { act { await model.toggleDone(item, client: $0) } } label: {
                Label(item.done ? "Mark not done" : "Mark done", systemImage: item.done ? "circle" : "checkmark.circle")
            }
            Button { act { await model.toggleStar(item, client: $0) } } label: {
                Label(item.starred ? "Remove star" : "Star", systemImage: item.starred ? "star.slash" : "star")
            }
            if !model.stages.isEmpty {
                Menu {
                    ForEach(model.stages) { stage in
                        Button { act { await model.move(item, to: stage, client: $0) } } label: {
                            if stage.id == item.stageId { Label(stage.name, systemImage: "checkmark") } else { Text(stage.name) }
                        }
                    }
                } label: { Label("Move to", systemImage: "tray.and.arrow.down") }
            }
            Divider()
            Button(role: .destructive) { pendingDelete = item } label: { Label("Delete", systemImage: "trash") }
        }
    }

    @ViewBuilder private func status(isEmpty: Bool) -> some View {
        if let message = model.errorMessage, model.items.isEmpty {
            Section { LoadFailureView(message: message) { Task { await reload() } } }
        } else if !model.hasLoaded {
            Section { ProgressView("Loading your to-dos…").frame(maxWidth: .infinity, minHeight: 80) }
        } else if isEmpty && !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if isEmpty {
            Section {
                if model.filter == .open {
                    ContentUnavailableView {
                        Label("All caught up", systemImage: "checkmark.circle")
                    } description: {
                        Text("Add a to-do with the + button. It syncs to Odoo To-do.")
                    }
                } else {
                    ContentUnavailableView("Nothing completed yet", systemImage: "checklist", description: Text("Finished to-dos appear here."))
                }
            }.listRowBackground(Color.clear)
        }
    }

    private func act(_ work: @escaping (APIClient) async -> Void) {
        guard let client = apiProvider.client else { return }
        Task { await work(client) }
    }

    private func reload() async {
        guard let client = apiProvider.client else { return }
        await model.load(client: client)
    }
}

struct TodoRow: View {
    let item: TodoItem
    var busy = false
    let toggle: () -> Void
    @ScaledMetric(relativeTo: .title2) private var checkSize: CGFloat = 26

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: toggle) {
                Image(systemName: item.done ? "checkmark.circle.fill" : (item.closed ? "xmark.circle" : "circle"))
                    .font(.system(size: checkSize, weight: .regular))
                    .foregroundStyle(item.done ? WorkplaceTheme.success : Color.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(busy)
            .padding(.leading, -8)
            .accessibilityLabel(item.done ? "Mark “\(item.name)” not done" : "Mark “\(item.name)” done")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body)
                    .strikethrough(item.done, color: .secondary)
                    .foregroundStyle(item.closed ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                let meta = TodoFormat.metadata(item)
                if !meta.isEmpty {
                    // Plain icon+text pairs: List gives Labels a wide icon column.
                    HStack(spacing: 12) {
                        ForEach(Array(meta.enumerated()), id: \.offset) { _, part in
                            HStack(spacing: 3) {
                                Image(systemName: part.symbol).imageScale(.small).accessibilityHidden(true)
                                Text(part.text)
                            }
                            .foregroundStyle(part.urgent ? WorkplaceTheme.danger : .secondary)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(part.accessibilityLabel)
                        }
                    }
                    .font(.caption)
                    .lineLimit(1)
                }
            }
            .padding(.top, 11)
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.starred {
                Image(systemName: "star.fill")
                    .foregroundStyle(WorkplaceTheme.attention)
                    .padding(.top, 12)
                    .accessibilityLabel("Starred")
            }
        }
        .opacity(busy ? 0.6 : 1)
        .accessibilityElement(children: .contain)
    }
}

enum TodoFormat {
    struct Part { let text: String; let symbol: String; var urgent = false; var accessibilityLabel: String }

    static func metadata(_ item: TodoItem) -> [Part] {
        var parts: [Part] = []
        if let date = item.dateDeadline {
            let text = deadline(date)
            parts.append(Part(text: text, symbol: "calendar", urgent: item.isOverdue,
                              accessibilityLabel: item.isOverdue ? "Overdue, due \(text)" : "Due \(text)"))
        }
        if !item.tags.isEmpty {
            let names = item.tags.map(\.name).joined(separator: ", ")
            parts.append(Part(text: names, symbol: "tag", accessibilityLabel: "Tags: \(names)"))
        }
        if item.assignees.count > 1 {
            parts.append(Part(text: "\(item.assignees.count)", symbol: "person.2", accessibilityLabel: "Shared with \(item.assignees.count) people"))
        }
        if item.hasDescription { parts.append(Part(text: "Notes", symbol: "text.alignleft", accessibilityLabel: "Has notes")) }
        return parts
    }

    static func deadline(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let sameYear = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.month(.abbreviated).day()) : date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct TodoComposeSheet: View {
    let stages: [TodoStage]
    let onCreate: (TodoCreateRequest) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var starred = false
    @State private var hasDeadline = false
    @State private var deadline = TodoComposeSheet.defaultDeadline()
    @State private var stageId: Int?
    @State private var saving = false
    @State private var error: String?
    @State private var confirmDiscard = false
    @FocusState private var titleFocused: Bool

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasDraft: Bool { !trimmedTitle.isEmpty || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.body.weight(.medium))
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onSubmit { Task { await add() } }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Toggle(isOn: $starred) { Label("Starred", systemImage: "star") }
                    Toggle(isOn: $hasDeadline.animation()) { Label("Deadline", systemImage: "calendar") }
                    if hasDeadline {
                        DatePicker("Due", selection: $deadline)
                    }
                    if !stages.isEmpty {
                        Picker(selection: $stageId) {
                            ForEach(stages) { Text($0.name).tag(Optional($0.id)) }
                        } label: { Label("Stage", systemImage: "tray") }
                    }
                }
                if let error {
                    Section { WorkplaceNotice(title: "Not added", message: error, symbol: "exclamationmark.triangle", tint: WorkplaceTheme.danger) }
                }
            }
            .workplaceScreen()
            .navigationTitle("New to-do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if hasDraft { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Add") { Task { await add() } }.disabled(trimmedTitle.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(hasDraft || saving)
            .confirmationDialog("Discard this to-do?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .onAppear {
                if stageId == nil { stageId = stages.first?.id }
                titleFocused = true
            }
        }
    }

    private func add() async {
        guard !trimmedTitle.isEmpty, !saving else { return }
        saving = true
        error = nil
        defer { saving = false }
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await onCreate(TodoCreateRequest(name: trimmedTitle, descriptionText: text.isEmpty ? nil : text,
                                                 starred: starred, dateDeadline: hasDeadline ? deadline : nil, stageId: stageId))
            dismiss()
        } catch {
            self.error = TodoListViewModel.message(for: error, fallback: "Couldn’t add this to-do.")
        }
    }

    static func defaultDeadline(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let fivePM = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now
        return fivePM > now ? fivePM : calendar.date(byAdding: .day, value: 1, to: fivePM) ?? fivePM
    }
}
