import SwiftUI

struct InventoryView: View {
  private let scope: InventoryScope
  @EnvironmentObject private var apiProvider: APIClientProvider
  @StateObject private var viewModel = InventoryViewModel()

  @State private var searchText = ""

  init(scope: InventoryScope = .myReady) {
    self.scope = scope
  }

  init(receiptsOnly: Bool) {
    self.scope = receiptsOnly ? .receipts : .myReady
  }

  var body: some View {
    List {
      status
      Section(scope.sectionTitle) {
        ForEach(filteredPickings) { picking in
          NavigationLink(destination: InventoryDetailView(pickingId: picking.id)) {
            transferRow(picking)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .workplaceScreen()
    .navigationTitle(scope.title)
    .searchable(text: $searchText, prompt: "Search by name or customer")
    .refreshable { await reload() }
    .task {
      if let client = apiProvider.client {
        await viewModel.load(apiClient: client, scope: scope)
      }
    }
  }
  @ViewBuilder
  private var status: some View {
    if viewModel.isLoading && viewModel.pickings.isEmpty {
      ProgressView("Loading \(scope.title.lowercased())…")
        .frame(maxWidth: .infinity, minHeight: 80)
    } else if let message = viewModel.errorMessage {
      LoadFailureView(message: message) { Task { await reload() } }
    } else if !searchText.isEmpty && !viewModel.pickings.isEmpty && !viewModel.pickings.contains(where: {
      $0.name.localizedCaseInsensitiveContains(searchText) || ($0.partnerName ?? "").localizedCaseInsensitiveContains(searchText)
    }) {
      ContentUnavailableView.search(text: searchText)
    } else if viewModel.pickings.isEmpty {
      ContentUnavailableView(
        "No \(scope.title.lowercased())", systemImage: "shippingbox",
        description: Text(emptyDescription))
    }
  }

  private var filteredPickings: [PickingListItem] {
    viewModel.pickings.filter {
      searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        || ($0.partnerName ?? "").localizedCaseInsensitiveContains(searchText)
    }
  }

  private func transferRow(_ picking: PickingListItem) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        WorkplaceIcon(symbol: scopeSymbol)
        VStack(alignment: .leading, spacing: 5) {
          Text(picking.name).font(.headline).foregroundStyle(.primary)
          if let partnerName = picking.partnerName, !partnerName.isEmpty {
            Text(partnerName).font(.subheadline).foregroundStyle(.secondary)
          }
          if let scheduled = picking.scheduledDate {
            Label(scheduled.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("\(picking.progress.done.formatted()) of \(picking.progress.total.formatted()) processed")
          .font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(.primary)
        ProgressView(value: picking.progress.total == 0
          ? 0 : min(1, max(0, picking.progress.done / picking.progress.total)))
          .accessibilityLabel("Progress for \(picking.name)")
          .accessibilityValue("\(picking.progress.done.formatted()) of \(picking.progress.total.formatted()) processed")
      }
    }
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
  }

  private var scopeSymbol: String {
    switch scope {
    case .myReady: return "checklist"
    case .receipts: return "tray.and.arrow.down"
    case .deliveries: return "shippingbox"
    case .internalTransfers: return "arrow.left.arrow.right"
    case .history: return "clock.arrow.circlepath"
    }
  }

  private var emptyDescription: String {
    switch scope {
    case .myReady: return "No ready transfers are assigned to you. Pull down to check again."
    case .history: return "Completed transfers will appear here. Pull down to refresh."
    default: return "There is no open work in this list. Pull down to check again."
    }
  }

  private func reload() async {
    guard let client = apiProvider.client else { return }
    await viewModel.load(apiClient: client, scope: scope)
  }

}
