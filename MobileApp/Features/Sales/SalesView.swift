import SwiftUI

struct SalesView: View {
  @EnvironmentObject private var apiProvider: APIClientProvider
  @StateObject private var viewModel = SalesViewModel()

  @State private var searchText = ""

  var body: some View {
    List {
      status
      Section {
        NavigationLink(destination: CustomerSearchView()) {
          Label("Find a customer", systemImage: "person.crop.circle.badge.magnifyingglass")
            .font(.headline).frame(minHeight: 52)
        }
      }

      Section(header: Text("Orders")) {
        ForEach(
          viewModel.orders.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
              || ($0.partnerName ?? "").localizedCaseInsensitiveContains(searchText)
          }
        ) { order in
          NavigationLink(destination: SalesOrderDetailView(orderId: order.id)) {
            VStack(alignment: .leading, spacing: 8) {
              Text(order.name).font(.headline)
              Text(order.partnerName ?? "")
                .font(.subheadline)
                .foregroundColor(.secondary)
              Text(order.state.capitalized)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle("Sales Orders")
    .searchable(text: $searchText, prompt: "Search by name or customer")
    .refreshable { await reload() }
    .task {
      if let client = apiProvider.client {
        await viewModel.load(apiClient: client)
      }
    }
  }
  @ViewBuilder
  private var status: some View {
    if viewModel.isLoading && viewModel.orders.isEmpty {
      ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 80)
    } else if let message = viewModel.errorMessage {
      LoadFailureView(message: message) { Task { await reload() } }
    } else if !searchText.isEmpty && !viewModel.orders.isEmpty && !viewModel.orders.contains(where: {
      $0.name.localizedCaseInsensitiveContains(searchText) || ($0.partnerName ?? "").localizedCaseInsensitiveContains(searchText)
    }) {
      ContentUnavailableView.search(text: searchText)
    } else if viewModel.orders.isEmpty {
      ContentUnavailableView(
        "No orders", systemImage: "cart", description: Text("Pull down to refresh."))
    }
  }

  private func reload() async {
    guard let client = apiProvider.client else { return }
    await viewModel.load(apiClient: client)
  }

}
