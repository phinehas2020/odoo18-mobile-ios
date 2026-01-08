import SwiftUI
import AudioToolbox

struct InventoryDetailView: View {
    let pickingId: Int

    @EnvironmentObject private var apiProvider: APIClientProvider
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var syncEngine: SyncEngine

    @StateObject private var viewModel = InventoryDetailViewModel()
    @State private var barcodeInput: String = ""
    @State private var showScanner = false

    var body: some View {
        VStack(spacing: 12) {
            if !networkMonitor.isOnline {
                OfflineBanner(pendingCount: syncEngine.pendingOutboxCount)
            }
            if viewModel.needsRefresh {
                RefreshBanner {
                    Task {
                        await viewModel.load(apiClient: apiProvider.client, pickingId: pickingId)
                    }
                }
            }

            if let detail = viewModel.detail {
                VStack(alignment: .leading, spacing: 8) {
                    Text(detail.name).font(.title2).bold()
                    Text(detail.partnerName ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    TextField("Scan or type barcode", text: $barcodeInput)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { submitScan() }
                    Button(action: { showScanner = true }) {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Button("Add Scan") { submitScan() }
                        .buttonStyle(.borderedProminent)
                    Button("Validate") { submitValidate() }
                        .buttonStyle(.bordered)
                }

                List(detail.lines) { line in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(line.productName).font(.headline)
                        Text("Done \(line.qtyDone) / \(line.qtyDemanded)")
                            .font(.caption)
                        ProgressView(value: line.qtyDemanded == 0 ? 0 : line.qtyDone / line.qtyDemanded)
                    }
                }
            } else if viewModel.isLoading {
                ProgressView()
            } else {
                Text("No data available")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .navigationTitle("Picking")
        .task {
            await viewModel.load(apiClient: apiProvider.client, pickingId: pickingId)
        }
        .sheet(isPresented: $showScanner) {
            BarcodeScannerView { code in
                showScanner = false
                barcodeInput = code
                submitScan()
            }
        }
        .alert(item: Binding(
            get: { viewModel.lastWarning.map { WarningMessage(text: $0) } },
            set: { _ in viewModel.lastWarning = nil }
        )) { message in
            Alert(title: Text("Notice"), message: Text(message.text), dismissButton: .default(Text("OK")))
        }
        .onChange(of: viewModel.lastScanStatus) { status in
            guard let status else { return }
            playFeedback(for: status)
            viewModel.lastScanStatus = nil
        }
    }

    private func submitScan() {
        let code = barcodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        Task {
            await viewModel.scan(
                apiClient: apiProvider.client,
                pickingId: pickingId,
                code: code,
                isOnline: networkMonitor.isOnline
            )
            barcodeInput = ""
        }
    }

    private func submitValidate() {
        Task {
            await viewModel.validate(
                apiClient: apiProvider.client,
                pickingId: pickingId,
                isOnline: networkMonitor.isOnline
            )
        }
    }

    private func playFeedback(for status: String) {
        let generator = UINotificationFeedbackGenerator()
        switch status {
        case "success", "validated":
            generator.notificationOccurred(.success)
            AudioServicesPlaySystemSound(1104)
        case "queued":
            generator.notificationOccurred(.warning)
            AudioServicesPlaySystemSound(1054)
        default:
            generator.notificationOccurred(.error)
            AudioServicesPlaySystemSound(1073)
        }
    }
}

struct OfflineBanner: View {
    let pendingCount: Int

    var body: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text("Offline · \(pendingCount) pending")
                .font(.caption)
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.2))
        .cornerRadius(8)
    }
}

struct RefreshBanner: View {
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
            Text("Updates available. Refresh required.")
                .font(.caption)
            Spacer()
            Button("Refresh") {
                onRefresh()
            }
            .buttonStyle(.bordered)
        }
        .padding(8)
        .background(Color.yellow.opacity(0.2))
        .cornerRadius(8)
    }
}

struct WarningMessage: Identifiable {
    let id = UUID()
    let text: String
}
