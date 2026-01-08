import SwiftUI

struct CustomerSearchView: View {
    @EnvironmentObject private var apiProvider: APIClientProvider
    @StateObject private var viewModel = CustomerSearchViewModel()

    var body: some View {
        List(viewModel.results) { customer in
            VStack(alignment: .leading) {
                Text(customer.name).font(.headline)
                if let email = customer.email {
                    Text(email).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Customers")
        .searchable(text: $viewModel.query)
        .onSubmit(of: .search) {
            Task {
                if let client = apiProvider.client {
                    await viewModel.search(apiClient: client)
                }
            }
        }
    }
}
