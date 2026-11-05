import SwiftUI

struct SalesView: View {
    @EnvironmentObject private var apiProvider: APIClientProvider
    @StateObject private var viewModel = SalesViewModel()
    @State private var searchText = ""
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        List {
            status
            Section {
                NavigationLink(destination: CustomerSearchView()) {
                    Label("Find a customer", systemImage: "person.crop.circle.badge.magnifyingglass")
                        .frame(minHeight: 44)
                }
            }
            if !filteredOrders.isEmpty {
                Section {
                    ForEach(filteredOrders) { order in
                        NavigationLink(destination: SalesOrderDetailView(orderId: order.id)) {
                            orderRow(order)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .workplaceScreen()
        .navigationTitle("Sales orders")
        .searchable(text: $searchText, prompt: "Search by name or customer")
        .refreshable { await reload() }
        .task {
            if let client = apiProvider.client { await viewModel.load(apiClient: client) }
        }
    }

    private var filteredOrders: [SaleOrderItem] {
        viewModel.orders.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.partnerName ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private func orderRow(_ order: SaleOrderItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let row = textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            row {
                Text(order.name).font(.headline).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                WorkplaceStatusPill(text: SalesOrderPresentation.title(for: order.state),
                                    symbol: SalesOrderPresentation.symbol(for: order.state),
                                    tint: SalesOrderPresentation.tint(for: order.state))
            }
            if let partnerName = order.partnerName, !partnerName.isEmpty {
                Text(partnerName).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let date = order.dateOrder {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        if viewModel.isLoading && viewModel.orders.isEmpty {
            ProgressView("Loading sales orders…").frame(maxWidth: .infinity, minHeight: 80)
        } else if let message = viewModel.errorMessage {
            LoadFailureView(message: message) { Task { await reload() } }
        } else if !searchText.isEmpty && !viewModel.orders.isEmpty && !viewModel.orders.contains(where: {
            $0.name.localizedCaseInsensitiveContains(searchText) || ($0.partnerName ?? "").localizedCaseInsensitiveContains(searchText)
        }) {
            ContentUnavailableView.search(text: searchText)
        } else if viewModel.orders.isEmpty {
            ContentUnavailableView("No orders", systemImage: "doc.text", description: Text("Pull down to check for the latest customer orders."))
        }
    }

    private func reload() async {
        guard let client = apiProvider.client else { return }
        await viewModel.load(apiClient: client)
    }
}

// Presentation only: preserve the server state and actions unchanged.
enum SalesOrderPresentation {
    static func title(for state: String) -> String {
        switch state {
        case "draft": return "Quotation"
        case "sent": return "Quotation sent"
        case "sale": return "Confirmed"
        case "done": return "Completed"
        case "cancel": return "Cancelled"
        default: return state.capitalized
        }
    }
    static func symbol(for state: String) -> String {
        switch state {
        case "sent": return "paperplane"
        case "sale": return "checkmark.seal"
        case "done": return "checkmark.circle"
        case "cancel": return "xmark.circle"
        default: return "doc.text"
        }
    }
    static func tint(for state: String) -> Color {
        switch state {
        case "draft", "sent": return WorkplaceTheme.attention
        case "sale", "done": return WorkplaceTheme.accent
        case "cancel": return WorkplaceTheme.danger
        default: return WorkplaceTheme.information
        }
    }
}
