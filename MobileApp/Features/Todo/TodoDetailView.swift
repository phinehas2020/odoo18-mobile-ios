import SwiftUI

/// Edits one Odoo to-do natively. Each change is written to Odoo as it is made.
struct TodoDetailView: View {
    let taskId: Int
    var onChange: (TodoItem) -> Void = { _ in }
    var onDelete: (Int) -> Void = { _ in }

    @EnvironmentObject private var apiProvider: APIClientProvider
    @EnvironmentObject private var config: EnvironmentConfig
    @Environment(\.dismiss) private var dismiss

    @State private var detail: TodoDetail?
    @State private var stages: [TodoStage]
    @State private var title = ""
    @State private var notesDraft = ""
    @State private var editingNotes = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var pendingSaves = 0
    @State private var saveChain: Task<Void, Never>?
    @State private var deadlineDebounce: Task<Void, Never>?
    @State private var confirmDelete = false
    @State private var deleting = false
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool

    init(taskId: Int, initial: TodoItem? = nil, stages: [TodoStage] = [],
         onChange: @escaping (TodoItem) -> Void = { _ in }, onDelete: @escaping (Int) -> Void = { _ in }) {
        self.taskId = taskId
        self.onChange = onChange
        self.onDelete = onDelete
        _stages = State(initialValue: stages)
        _detail = State(initialValue: initial.map { TodoDetail(item: $0) })
        _title = State(initialValue: initial?.name ?? "")
    }

    private var item: TodoItem? { detail?.item }

    var body: some View {
        Form {
            if let saveError {
                Section { WorkplaceNotice(title: "Change not saved", message: saveError, symbol: "exclamationmark.triangle", tint: WorkplaceTheme.danger) }
            }
            if let item {
                header(item)
                planning(item)
                notes
                people(item)
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label(deleting ? "Deleting…" : "Delete to-do", systemImage: "trash")
                    }.disabled(deleting)
                }
            } else if let loadError {
                Section { LoadFailureView(message: loadError) { Task { await load() } } }
            } else {
                Section { ProgressView("Loading to-do…").frame(maxWidth: .infinity, minHeight: 80) }
            }
        }
        .workplaceScreen()
        .navigationTitle(item?.done == true ? "Done" : "To-do")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if pendingSaves > 0 { ProgressView().accessibilityLabel("Saving") }
            }
            if editingNotes {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Save notes") { saveNotes() }.fontWeight(.semibold)
                }
            }
        }
        .confirmationDialog("Delete this to-do?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It is removed from Odoo for everyone it’s shared with.")
        }
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: titleFocused) { _, focused in if !focused { commitTitle() } }
        .onDisappear {
            if titleFocused { commitTitle() }
            deadlineDebounce?.cancel()
        }
    }

    // MARK: Sections

    private func header(_ item: TodoItem) -> some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                Button { save(TodoPatch(done: !item.done)) { $0.done.toggle(); $0.closed = $0.done } } label: {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.title)
                        .foregroundStyle(item.done ? WorkplaceTheme.success : Color.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(item.done ? "Mark not done" : "Mark done")

                TextField("Title", text: $title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .strikethrough(item.done, color: .secondary)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .padding(.top, 8)
                    .onChange(of: title) { _, value in
                        // Titles are single-line in Odoo; Return finishes editing.
                        if value.contains("\n") {
                            title = value.replacingOccurrences(of: "\n", with: " ")
                            titleFocused = false
                        }
                    }

                Button { save(TodoPatch(starred: !item.starred)) { $0.starred.toggle() } } label: {
                    Image(systemName: item.starred ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(item.starred ? WorkplaceTheme.attention : Color.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(item.starred ? "Remove star" : "Star")
            }
            if item.state == "1_canceled" {
                Label("Cancelled in Odoo", systemImage: "xmark.circle").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func planning(_ item: TodoItem) -> some View {
        Section {
            if !stages.isEmpty {
                Picker(selection: Binding(get: { item.stageId }, set: { id in
                    guard let id, let stage = stages.first(where: { $0.id == id }) else { return }
                    save(TodoPatch(stageId: id)) { $0.stageId = id; $0.stageName = stage.name }
                })) {
                    if item.stageId == nil { Text("None").tag(Int?.none) }
                    ForEach(stages) { Text($0.name).tag(Optional($0.id)) }
                } label: { Label("Stage", systemImage: "tray") }
            }
            Toggle(isOn: Binding(get: { item.dateDeadline != nil }, set: { on in
                deadlineDebounce?.cancel()
                let value: Date? = on ? TodoComposeSheet.defaultDeadline() : nil
                save(TodoPatch(dateDeadline: .some(value))) { $0.dateDeadline = value }
            }).animation()) {
                Label("Deadline", systemImage: "calendar")
                    .foregroundStyle(item.isOverdue ? WorkplaceTheme.danger : .primary)
            }
            if let deadline = item.dateDeadline {
                DatePicker("Due", selection: Binding(get: { deadline }, set: { scheduleDeadline($0) }))
                if item.isOverdue {
                    Text("Overdue").font(.caption.weight(.semibold)).foregroundStyle(WorkplaceTheme.danger)
                }
            }
        }
    }

    @ViewBuilder private var notes: some View {
        let html = detail?.descriptionHTML ?? ""
        Section {
            if editingNotes {
                TextField("Notes", text: $notesDraft, axis: .vertical)
                    .lineLimit(4...20)
                    .focused($notesFocused)
                if containsFormatting(html) {
                    Text("Saving replaces this note’s Odoo formatting with plain text.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Cancel") { editingNotes = false; notesFocused = false }
                        .buttonStyle(.borderless)
                    Spacer()
                    Button("Save notes") { saveNotes() }
                        .buttonStyle(.borderless).fontWeight(.semibold)
                }
            } else if html.isEmpty {
                Button { beginNotes(html) } label: { Label("Add notes", systemImage: "square.and.pencil") }
            } else {
                Text(QualityInstructionText.render(html, baseURL: config.baseURL))
                    .textSelection(.enabled)
                    .lineSpacing(4)
                    .tint(WorkplaceTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { beginNotes(html) } label: { Label("Edit notes", systemImage: "square.and.pencil") }
            }
        } header: { Text("Notes") }
    }

    @ViewBuilder private func people(_ item: TodoItem) -> some View {
        if !item.tags.isEmpty || item.assignees.count > 1 {
            Section {
                if !item.tags.isEmpty {
                    Label(item.tags.map(\.name).joined(separator: ", "), systemImage: "tag")
                }
                if item.assignees.count > 1 {
                    Label(item.assignees.map(\.name).joined(separator: ", "), systemImage: "person.2")
                }
            } header: { Text("Shared") } footer: {
                Text("Tags and sharing are managed in Odoo.")
            }
        }
    }

    // MARK: Actions

    private func load() async {
        guard let client = apiProvider.client else { return }
        do {
            async let detailRequest: TodoDetail = client.send(Endpoint(path: TodoAPI.task(taskId), method: "GET"))
            if stages.isEmpty {
                stages = (try? await client.send(Endpoint(path: "/api/v1/todo/stages", method: "GET"))) ?? []
            }
            let fresh = try await detailRequest
            detail = fresh
            if !titleFocused { title = fresh.item.name }
            loadError = nil
            onChange(fresh.item)
        } catch {
            if detail == nil { loadError = TodoListViewModel.message(for: error, fallback: "Couldn’t open this to-do.") }
            else { saveError = TodoListViewModel.message(for: error, fallback: "Couldn’t refresh this to-do.") }
        }
    }

    /// Applies the change locally, then writes it. Saves run in order so the last edit wins.
    private func save(_ patch: TodoPatch, optimistic: (inout TodoItem) -> Void = { _ in }) {
        guard let client = apiProvider.client, detail != nil else { return }
        optimistic(&detail!.item)
        saveError = nil
        pendingSaves += 1
        let previous = saveChain
        saveChain = Task {
            await previous?.value
            defer { pendingSaves -= 1 }
            do {
                let updated = try await TodoAPI.patch(taskId, patch, client: client)
                detail = updated
                if !titleFocused { title = updated.item.name }
                onChange(updated.item)
            } catch {
                saveError = TodoListViewModel.message(for: error, fallback: "Couldn’t save your change.")
                await load()   // Odoo is the source of truth after a failed write.
            }
        }
    }

    private func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let item else { return }
        guard !trimmed.isEmpty else { title = item.name; return }
        guard trimmed != item.name else { return }
        title = trimmed
        save(TodoPatch(name: trimmed)) { $0.name = trimmed }
    }

    private func scheduleDeadline(_ date: Date) {
        detail?.item.dateDeadline = date
        deadlineDebounce?.cancel()
        deadlineDebounce = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            save(TodoPatch(dateDeadline: .some(date)))
        }
    }

    private func beginNotes(_ html: String) {
        notesDraft = html.isEmpty ? "" : String(QualityInstructionText.render(html, baseURL: config.baseURL).characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        editingNotes = true
        notesFocused = true
    }

    private func saveNotes() {
        let text = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        editingNotes = false
        notesFocused = false
        save(TodoPatch(descriptionText: .some(text.isEmpty ? nil : text))) {
            $0.hasDescription = !text.isEmpty
        }
        // Show the plain text immediately; the saved HTML replaces it when Odoo answers.
        detail?.descriptionHTML = text.isEmpty ? "" : text
    }

    private func delete() async {
        guard let client = apiProvider.client else { return }
        deleting = true
        defer { deleting = false }
        do {
            await saveChain?.value
            try await client.sendNoResponse(Endpoint(path: TodoAPI.task(taskId), method: "DELETE"))
            onDelete(taskId)
            dismiss()
        } catch {
            saveError = TodoListViewModel.message(for: error, fallback: "Couldn’t delete this to-do.")
        }
    }

    private func containsFormatting(_ html: String) -> Bool {
        html.range(of: #"<(?!/?(p|br|div|span)\b)[a-zA-Z/]"#, options: .regularExpression) != nil
    }
}
