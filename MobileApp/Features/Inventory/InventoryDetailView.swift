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
    @State private var confirmCompletion = false
    @State private var selectedLine: PickingLine?
    @State private var selectedMove: PickingMove?
    @State private var showReturn = false

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
                    Button("Complete transfer") { confirmCompletion = true }
                        .buttonStyle(.bordered)
                }

                .controlSize(.large)
                .disabled(viewModel.isLoading || viewModel.isSubmitting || viewModel.needsRefresh || ["done", "cancel"].contains(detail.state))

                if !completionBlockers(in: detail).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Resolve before completion", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                        ForEach(completionBlockers(in: detail), id: \.self) { Text($0).font(.caption) }
                    }
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if detail.state == "done" {
                    Button { showReturn = true } label: {
                        Label("Return goods", systemImage: "arrow.uturn.backward").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.bordered).disabled(!networkMonitor.isOnline || viewModel.needsRefresh)
                }
                WorkStatusBadge(state: detail.state)
                Text("From \(detail.sourceLocation.name) → \(detail.destLocation.name)").font(.subheadline).foregroundStyle(.secondary)

                List {
                    Section("Processed lines") {
                        ForEach(detail.lines) { line in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(line.productName).font(.headline)
                                Text("Done \(line.qtyDone.formatted()) / \(line.qtyDemanded.formatted()) \(line.uomName ?? "")")
                                    .font(.caption)
                                if line.tracking == "lot" || line.tracking == "serial" {
                                    Text("\(line.tracking == "serial" ? "Serial" : "Lot"): \(line.lotName ?? "Required")")
                                        .font(.caption)
                                        .foregroundStyle(line.qtyDone > 0 && line.lotName == nil ? Color.orange : Color.secondary)
                                }
                                ProgressView(value: line.qtyDemanded == 0 ? 0 : line.qtyDone / line.qtyDemanded)
                                if detail.pickingTypeCode == "incoming" && !["done", "cancel"].contains(detail.state) {
                                    Button("Edit received quantity") { selectedLine = line }
                                        .buttonStyle(.bordered)
                                        .disabled(viewModel.isSubmitting || viewModel.needsRefresh || !networkMonitor.isOnline)
                                }
                            }
                        }
                    }
                    if detail.pickingTypeCode == "incoming" && !unstartedMoves(in: detail).isEmpty {
                        Section("Not received") {
                            ForEach(unstartedMoves(in: detail)) { move in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(move.productName).font(.headline)
                                    Text("Demanded \(move.qtyDemanded.formatted()) \(move.uomName ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Button("Receive product") { selectedMove = move }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(viewModel.isSubmitting || viewModel.needsRefresh || !networkMonitor.isOnline)
                                }
                            }
                        }
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
        .navigationTitle("Transfer")
        .confirmationDialog("Complete this transfer in Odoo?", isPresented: $confirmCompletion, titleVisibility: .visible) {
            Button("Complete transfer") { submitValidate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(completionBlockers(in: viewModel.detail).isEmpty
                 ? "Odoo will verify quantities, lots and whether a backorder decision is needed."
                 : "Resolve the highlighted lot or serial issues first.")
        }
        .task {
            await viewModel.load(apiClient: apiProvider.client, pickingId: pickingId)
        }
        .sheet(isPresented: $showReturn) { TransferReturnSheet(pickingId: pickingId) }
        .sheet(isPresented: $showScanner) {
            BarcodeScannerView { code in
                barcodeInput = code
                return await submitScannedCode(code)
            }
        }
        .sheet(item: $selectedLine) { line in
            ReceiptLineEditor(
                line: line,
                permitsNewLot: viewModel.detail?.pickingTypeCode == "incoming"
            ) { quantity, lotId, lotName in
                await viewModel.updateLine(
                    apiClient: apiProvider.client,
                    pickingId: pickingId,
                    lineId: line.id,
                    quantity: quantity,
                    lotId: lotId,
                    lotName: lotName,
                    isOnline: networkMonitor.isOnline
                )
            }
        }
        .sheet(item: $selectedMove) { move in
            ReceiptMoveEditor(move: move) { quantity, lotName in
                await viewModel.createLine(
                    apiClient: apiProvider.client,
                    pickingId: pickingId,
                    moveId: move.id,
                    quantity: quantity,
                    lotId: nil,
                    lotName: lotName,
                    isOnline: networkMonitor.isOnline
                )
            }
        }
        .confirmationDialog(
            "Handle remaining quantities?",
            isPresented: Binding(
                get: { viewModel.needsBackorderDecision },
                set: { viewModel.needsBackorderDecision = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Create backorder") { submitValidate(policy: .create) }
            Button("Finish without backorder", role: .destructive) { submitValidate(policy: .cancel) }
            Button("Keep reviewing", role: .cancel) {}
        } message: {
            Text(viewModel.backorderMessage ?? "Some requested quantities remain. Choose how Odoo should handle them.")
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
            _ = await viewModel.scan(
                apiClient: apiProvider.client,
                pickingId: pickingId,
                code: code,
                isOnline: networkMonitor.isOnline
            )
            barcodeInput = ""
        }
    }

    private func submitScannedCode(_ code: String) async -> Bool {
        let saved = await viewModel.scan(
            apiClient: apiProvider.client,
            pickingId: pickingId,
            code: code,
            isOnline: networkMonitor.isOnline
        )
        if saved { barcodeInput = "" }
        return saved
    }

    private func submitValidate(policy: BackorderPolicy = .ask) {
        guard completionBlockers(in: viewModel.detail).isEmpty else {
            viewModel.lastWarning = "Add the required lot or serial details before completing this transfer."
            return
        }
        Task {
            await viewModel.validate(
                apiClient: apiProvider.client,
                pickingId: pickingId,
                isOnline: networkMonitor.isOnline,
                backorderPolicy: policy
            )
        }
    }

    private func completionBlockers(in detail: PickingDetail?) -> [String] {
        guard let detail else { return [] }
        return detail.lines.compactMap { line in
            guard line.qtyDone > 0 else { return nil }
            if (line.tracking == "lot" || line.tracking == "serial") && line.lotId == nil && line.lotName?.isEmpty != false {
                return "\(line.productName) needs a \(line.tracking == "serial" ? "serial number" : "lot")."
            }
            if line.tracking == "serial" && line.qtyDone != 1 {
                return "\(line.productName) serial quantity must be 1."
            }
            return nil
        }
    }

    private func unstartedMoves(in detail: PickingDetail) -> [PickingMove] {
        let representedMoveIds = Set(detail.lines.compactMap(\.moveId))
        return (detail.moves ?? []).filter { !representedMoveIds.contains($0.id) && $0.qtyDone == 0 }
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

private struct ReceiptMoveEditor: View {
    let move: PickingMove
    let onSave: (Double, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var quantityText: String
    @State private var lotName = ""
    @State private var isSaving = false
    @State private var validationMessage: String?

    init(move: PickingMove, onSave: @escaping (Double, String?) async -> Bool) {
        self.move = move
        self.onSave = onSave
        _quantityText = State(initialValue: move.tracking == "serial" ? "1" : move.qtyDemanded.formatted(.number.precision(.fractionLength(0...3))))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Received") {
                    TextField("Quantity", text: $quantityText).keyboardType(.decimalPad)
                    Text("Demanded: \(move.qtyDemanded.formatted()) \(move.uomName ?? "")")
                        .foregroundStyle(.secondary)
                }
                if move.tracking == "lot" || move.tracking == "serial" {
                    Section(move.tracking == "serial" ? "Serial number" : "Lot") {
                        TextField(move.tracking == "serial" ? "Serial number" : "Lot name", text: $lotName)
                            .textInputAutocapitalization(.characters)
                        if move.tracking == "serial" {
                            Text("Receive one serial at a time. Use Receive product again for the next serial.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let validationMessage {
                    Section { Text(validationMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(move.productName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(isSaving) }
            }
        }
    }

    private func save() {
        let normalized = quantityText.replacingOccurrences(of: ",", with: "")
        guard let quantity = Double(normalized), quantity > 0 else {
            validationMessage = "Enter a quantity greater than zero."
            return
        }
        let trimmedLot = lotName.trimmingCharacters(in: .whitespacesAndNewlines)
        if (move.tracking == "lot" || move.tracking == "serial") && trimmedLot.isEmpty {
            validationMessage = "Enter the required \(move.tracking == "serial" ? "serial number" : "lot")."
            return
        }
        if move.tracking == "serial" && quantity != 1 {
            validationMessage = "Receive serial-numbered products one at a time with quantity 1."
            return
        }
        isSaving = true
        Task {
            let saved = await onSave(quantity, trimmedLot.isEmpty ? nil : trimmedLot)
            isSaving = false
            if saved { dismiss() }
        }
    }
}

private struct ReceiptLineEditor: View {
    let line: PickingLine
    let permitsNewLot: Bool
    let onSave: (Double, Int?, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var quantityText: String
    @State private var lotName: String
    @State private var isSaving = false
    @State private var validationMessage: String?

    init(
        line: PickingLine,
        permitsNewLot: Bool,
        onSave: @escaping (Double, Int?, String?) async -> Bool
    ) {
        self.line = line
        self.permitsNewLot = permitsNewLot
        self.onSave = onSave
        _quantityText = State(initialValue: line.qtyDone.formatted(.number.precision(.fractionLength(0...3))))
        _lotName = State(initialValue: line.lotName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Received") {
                    TextField("Quantity", text: $quantityText)
                        .keyboardType(.decimalPad)
                    Text("Demanded: \(line.qtyDemanded.formatted()) \(line.uomName ?? "")")
                        .foregroundStyle(.secondary)
                }
                if line.tracking == "lot" || line.tracking == "serial" {
                    Section(line.tracking == "serial" ? "Serial number" : "Lot") {
                        TextField(line.tracking == "serial" ? "Serial number" : "Lot name", text: $lotName)
                            .textInputAutocapitalization(.characters)
                        if line.lotId == nil && permitsNewLot {
                            Text("If this name does not exist, Odoo may create it for this receipt when the operation allows new lots.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let validationMessage {
                    Section { Text(validationMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(line.productName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        let normalized = quantityText.replacingOccurrences(of: ",", with: "")
        guard let quantity = Double(normalized), quantity >= 0 else {
            validationMessage = "Enter a quantity of zero or more."
            return
        }
        let trimmedLot = lotName.trimmingCharacters(in: .whitespacesAndNewlines)
        if quantity > 0 && (line.tracking == "lot" || line.tracking == "serial") && trimmedLot.isEmpty {
            validationMessage = "Enter the required \(line.tracking == "serial" ? "serial number" : "lot")."
            return
        }
        if line.tracking == "serial" && quantity != 0 && quantity != 1 {
            validationMessage = "A serial-numbered line must have quantity 0 or 1."
            return
        }
        isSaving = true
        Task {
            let saved = await onSave(quantity, line.lotId, trimmedLot.isEmpty ? nil : trimmedLot)
            isSaving = false
            if saved { dismiss() }
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
