import SwiftUI

struct InventoryView: View {
    @EnvironmentObject private var apiProvider: APIClientProvider
    @StateObject private var viewModel = InventoryViewModel()

    var body: some View {
        List(viewModel.pickings) { picking in
            NavigationLink(destination: InventoryDetailView(pickingId: picking.id)) {
                VStack(alignment: .leading) {
                    Text(picking.name).font(.headline)
                    Text(picking.partnerName ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    ProgressView(value: picking.progress.total == 0 ? 0 : picking.progress.done / picking.progress.total)
                }
            }
        }
        .navigationTitle("Pickings")
        .task {
            if let client = apiProvider.client {
                await viewModel.load(apiClient: client)
            }
        }
    }
}
