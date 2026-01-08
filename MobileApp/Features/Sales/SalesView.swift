import SwiftUI

struct SalesView: View {
    @EnvironmentObject private var apiProvider: APIClientProvider
    @StateObject private var viewModel = SalesViewModel()

    var body: some View {
        List {
            Section {
                NavigationLink(destination: CustomerSearchView()) {
                    Text("Customer Search")
                }
            }

            Section(header: Text("Orders")) {
                ForEach(viewModel.orders) { order in
                    NavigationLink(destination: SalesOrderDetailView(orderId: order.id)) {
                        VStack(alignment: .leading) {
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
        .task {
            if let client = apiProvider.client {
                await viewModel.load(apiClient: client)
            }
        }
    }
}
