import SwiftUI

struct SalesOrderDetailView: View {
    let orderId: Int

    @EnvironmentObject private var apiProvider: APIClientProvider
    @StateObject private var viewModel = SalesOrderDetailViewModel()

    var body: some View {
        ScrollView {
            if let detail = viewModel.detail {
                VStack(alignment: .leading, spacing: 16) {
                    Text(detail.name).font(.title2).bold()
                    Text(detail.partnerName ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Divider()

                    ForEach(detail.lines) { line in
                        HStack {
                            Text(line.productName)
                            Spacer()
                            Text("\(line.quantity)")
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    TextField("Add note", text: $viewModel.noteText)
                        .textFieldStyle(.roundedBorder)
                    Button("Save Note") {
                        Task {
                            if let client = apiProvider.client {
                                await viewModel.addNote(apiClient: client, orderId: orderId)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if viewModel.isLoading {
                ProgressView()
            } else {
                Text("No order details")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Order")
        .task {
            if let client = apiProvider.client {
                await viewModel.load(apiClient: client, orderId: orderId)
            }
        }
    }
}
