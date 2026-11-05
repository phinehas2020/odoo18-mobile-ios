import SwiftUI

struct SalesOrderDetailView: View {
    let orderId: Int
    @EnvironmentObject private var apiProvider: APIClientProvider
    @StateObject private var viewModel = SalesOrderDetailViewModel()
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        List {
            if let detail = viewModel.detail {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        if let partner = detail.partnerName, !partner.isEmpty {
                            Text(partner).font(.headline).fixedSize(horizontal: false, vertical: true)
                        }
                        WorkplaceStatusPill(text: SalesOrderPresentation.title(for: detail.state),
                                            symbol: SalesOrderPresentation.symbol(for: detail.state),
                                            tint: SalesOrderPresentation.tint(for: detail.state))
                        if let date = detail.dateOrder {
                            Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                Section("Order items") {
                    ForEach(detail.lines) { line in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(line.productName).font(.headline).fixedSize(horizontal: false, vertical: true)
                            LabeledContent("Quantity") {
                                Text(line.quantity.formatted()).monospacedDigit().foregroundStyle(.primary)
                            }.font(.subheadline)
                        }.padding(.vertical, 4).accessibilityElement(children: .combine)
                    }
                }
                Section {
                    TextField("Write an order note", text: Binding(get: { viewModel.noteText }, set: viewModel.updateNoteDraft), axis: .vertical)
                        .lineLimit(3...6).padding(.vertical, 6)
                        .focused($noteIsFocused)
                        .disabled(viewModel.isSavingNote)
                        .accessibilityLabel("Team note for \(detail.name)")
                    if let error = viewModel.noteErrorMessage {
                        WorkplaceNotice(title: "Note not confirmed", message: error,
                                        symbol: "exclamationmark.triangle", tint: WorkplaceTheme.danger)
                    } else if viewModel.noteSaved {
                        Label("Note saved to this order", systemImage: "checkmark.circle")
                            .font(.subheadline).foregroundStyle(WorkplaceTheme.success)
                    }
                    Button {
                        Task {
                            if let client = apiProvider.client {
                                await viewModel.addNote(apiClient: client, orderId: orderId)
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if viewModel.isSavingNote { ProgressView().tint(.white) }
                            Text(viewModel.isSavingNote ? "Saving note…" : "Save note")
                        }.font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(WorkplaceTheme.buttonFill)
                    .disabled(viewModel.isSavingNote || viewModel.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiProvider.client == nil)
                    .accessibilityLabel(viewModel.isSavingNote ? "Saving note for \(detail.name)" : "Save note to \(detail.name)")
                } header: {
                    Text("Team note").accessibilityAddTraits(.isHeader)
                } footer: {
                    Text("Add useful context for the people working on this order.")
                }
            } else if viewModel.isLoading {
                ProgressView("Loading order details…").frame(maxWidth: .infinity, minHeight: 100)
            } else if let message = viewModel.loadErrorMessage {
                LoadFailureView(message: message) { Task { await reload() } }
            } else {
                ContentUnavailableView("No order details", systemImage: "doc.text", description: Text("Return to sales orders and open this order again."))
            }
        }
        .listStyle(.insetGrouped)
        .workplaceScreen()
        .navigationTitle(viewModel.detail?.name ?? "Order")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { noteIsFocused = false }
            }
        }
        .refreshable { await reload() }
        .task { await reload() }
        .onChange(of: viewModel.noteErrorMessage) { _, message in
            if let message { UIAccessibility.post(notification: .announcement, argument: message) }
        }
        .onChange(of: viewModel.noteSaved) { _, saved in
            if saved { UIAccessibility.post(notification: .announcement, argument: "Note saved to this order.") }
        }
    }

    private func reload() async {
        if let client = apiProvider.client { await viewModel.load(apiClient: client, orderId: orderId) }
    }
}
