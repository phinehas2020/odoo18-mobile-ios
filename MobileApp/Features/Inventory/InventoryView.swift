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
        ForEach(
          viewModel.pickings.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
              || ($0.partnerName ?? "").localizedCaseInsensitiveContains(searchText)
          }
        ) { picking in
          NavigationLink(destination: InventoryDetailView(pickingId: picking.id)) {
            VStack(alignment: .leading, spacing: 8) {
              Text(picking.name).font(.headline)
              Text(picking.partnerName ?? "")
                .font(.subheadline)
                .foregroundColor(.secondary)
              Text("\(picking.progress.done.formatted()) of \(picking.progress.total.formatted()) processed")
                .font(.subheadline).monospacedDigit()
              ProgressView(
                value: picking.progress.total == 0
                  ? 0 : min(1, max(0, picking.progress.done / picking.progress.total)))
            }
          }
        }
      }
    }
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
      ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 80)
    } else if let message = viewModel.errorMessage {
      LoadFailureView(message: message) { Task { await reload() } }
    } else if !searchText.isEmpty && !viewModel.pickings.isEmpty && !viewModel.pickings.contains(where: {
      $0.name.localizedCaseInsensitiveContains(searchText) || ($0.partnerName ?? "").localizedCaseInsensitiveContains(searchText)
    }) {
      ContentUnavailableView.search(text: searchText)
    } else if viewModel.pickings.isEmpty {
      ContentUnavailableView(
        "No \(scope.title.lowercased())", systemImage: "shippingbox",
        description: Text("Pull down to refresh."))
    }
  }

  private func reload() async {
    guard let client = apiProvider.client else { return }
    await viewModel.load(apiClient: client, scope: scope)
  }

}
