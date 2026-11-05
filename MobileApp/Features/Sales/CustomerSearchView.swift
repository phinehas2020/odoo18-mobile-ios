import SwiftUI

struct CustomerSearchView: View {
    @EnvironmentObject private var apiProvider: APIClientProvider
    @StateObject private var viewModel = CustomerSearchViewModel()
    @State private var hasSubmittedSearch = false

    var body: some View {
        List {
            if let message = viewModel.errorMessage {
                LoadFailureView(message: message) { Task { await search() } }
            }
            if viewModel.isSearching {
                ProgressView("Finding customers…").frame(maxWidth: .infinity, minHeight: 80)
            }
            if viewModel.results.isEmpty && !viewModel.isSearching && viewModel.errorMessage == nil {
                Section {
                    ContentUnavailableView(hasSubmittedSearch ? "No customers to display" : "Search for a customer",
                                           systemImage: "person.crop.circle.badge.magnifyingglass",
                                           description: Text(hasSubmittedSearch ? "Try another customer name, then tap Search again." : "Enter a customer name, then tap Search on the keyboard."))
                }
            } else if !viewModel.results.isEmpty {
                Section {
                    ForEach(viewModel.results) { customer in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(customer.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            if let email = customer.email, !email.isEmpty {
                                Label(email, systemImage: "envelope").font(.subheadline).foregroundStyle(.secondary)
                                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                            if let phone = customer.phone, !phone.isEmpty {
                                Label(phone, systemImage: "phone").font(.subheadline).foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }.padding(.vertical, 4).accessibilityElement(children: .contain)
                    }
                } footer: {
                    if let query = viewModel.resultsQuery { Text("Results for “\(query)”.") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .workplaceScreen()
        .navigationTitle("Customers")
        .searchable(text: $viewModel.query, prompt: "Search by customer name")
        .scrollDismissesKeyboard(.interactively)
        .onSubmit(of: .search) {
            Task { await search() }
        }
    }

    private func search() async {
        guard !viewModel.isSearching, let client = apiProvider.client else { return }
        hasSubmittedSearch = !viewModel.query.isEmpty
        await viewModel.search(apiClient: client)
        UIAccessibility.post(notification: .announcement,
                             argument: viewModel.errorMessage ?? (viewModel.results.isEmpty ? "No customers to display." : "\(viewModel.results.count) customers found."))
    }
}
