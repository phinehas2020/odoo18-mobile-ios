import SwiftUI
import AudioToolbox

struct InventoryDetailView: View {
    @AppStorage("workplaceHapticsEnabled") private var hapticsEnabled = true
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
    @FocusState private var barcodeFocused: Bool

    var body: some View {
        Group {
            if let detail = viewModel.detail {
                List {
                    if !networkMonitor.isOnline || viewModel.needsRefresh {
                        Section {
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
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(detail.name).font(.headline).accessibilityAddTraits(.isHeader)
                            if let partner = detail.partnerName, !partner.isEmpty {
                                Text(partner).font(.subheadline).foregroundStyle(.secondary)
                            }
                            WorkStatusBadge(state: detail.state)
                            VStack(alignment: .leading, spacing: 8) {
                                Label("From: \(detail.sourceLocation.name)", systemImage: "mappin.and.ellipse")
                                Label("To: \(detail.destLocation.name)", systemImage: "arrow.down.right")
                            }.font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Items") {
                        ForEach(detail.lines) { line in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(line.productName).font(.headline)
                                Text("Done \(line.qtyDone.formatted()) / \(line.qtyDemanded.formatted()) \(line.uomName ?? "")")
                                    .font(.title3.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(WorkplaceTheme.accent)
                                if line.tracking == "lot" || line.tracking == "serial" {
                                    Label("\(line.tracking == "serial" ? "Serial" : "Lot"): \(line.lotName ?? "Required")", systemImage: "tag")
                                        .font(.subheadline)
                                        .foregroundStyle(line.qtyDone > 0 && line.lotName == nil ? WorkplaceTheme.attention : Color.secondary)
                                }
                                ProgressView(value: line.qtyDemanded == 0 ? 0 : min(1, max(0, line.qtyDone / line.qtyDemanded)))
                                    .accessibilityLabel("Progress for \(line.productName)")
                                    .accessibilityValue("\(line.qtyDone.formatted()) of \(line.qtyDemanded.formatted()) \(line.uomName ?? "") processed")
                                if detail.pickingTypeCode == "incoming" && !["done", "cancel"].contains(detail.state) {
                                    Button { selectedLine = line } label: {
                                        Label("Edit quantity", systemImage: "pencil")
                                    }
                                        .buttonStyle(.bordered)
                                        .frame(minHeight: 44)
                                        .accessibilityLabel("Edit received quantity for \(line.productName)")
                                        .accessibilityValue("\(line.qtyDone.formatted()) \(line.uomName ?? "")")
                                        .disabled(viewModel.isSubmitting || viewModel.needsRefresh || !networkMonitor.isOnline)
                                }
                            }.padding(.vertical, 8)
                        }
                    }

                    if detail.pickingTypeCode == "incoming" && !unstartedMoves(in: detail).isEmpty {
                        Section("Not received") {
                            ForEach(unstartedMoves(in: detail)) { move in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(move.productName).font(.headline)
                                    Text("Demanded \(move.qtyDemanded.formatted()) \(move.uomName ?? "")")
                                        .font(.subheadline.weight(.medium)).monospacedDigit()
                                        .foregroundStyle(.secondary)
                                    Button { selectedMove = move } label: {
                                        Label("Receive product", systemImage: "tray.and.arrow.down")
                                    }
                                        .buttonStyle(.bordered)
                                        .frame(minHeight: 44)
                                        .accessibilityLabel("Receive \(move.productName)")
                                        .accessibilityValue("\(move.qtyDemanded.formatted()) \(move.uomName ?? "") expected")
                                        .disabled(viewModel.isSubmitting || viewModel.needsRefresh || !networkMonitor.isOnline)
                                }.padding(.vertical, 8)
                            }
                        }
                    }

                    if !completionBlockers(in: detail).isEmpty {
                        Section {
                            WorkplaceNotice(title: "Resolve before completion",
                                message: completionBlockers(in: detail).joined(separator: "\n"),
                                symbol: "exclamationmark.triangle.fill")
                        }
                    }

                    if isEditable(detail) {
                        Section {
                            DisclosureGroup("Enter barcode manually") {
                            TextField("Barcode", text: $barcodeInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .frame(minHeight: 44)
                                .focused($barcodeFocused)
                                .accessibilityLabel("Product barcode")
                                .submitLabel(.done)
                                .onSubmit { submitScan() }
                            Button("Add barcode") { submitScan() }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                                .disabled(barcodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .disabled(viewModel.isLoading || viewModel.isSubmitting || viewModel.needsRefresh)
                    }

                    if detail.state == "done" {
                        Section {
                            Button { showReturn = true } label: {
                                WorkplaceActionLabel(title: "Return goods", subtitle: "Review quantities and create a return transfer.", symbol: "arrow.uturn.backward")
                            }
                            .accessibilityLabel("Return goods from \(detail.name)")
                            .disabled(!networkMonitor.isOnline || viewModel.needsRefresh)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                .workplaceScreen()
            } else if viewModel.isLoading {
                ProgressView("Loading transfer details…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "No transfer data",
                        systemImage: "shippingbox",
                        description: Text("The transfer could not be loaded.")
                    )
                    Button("Try again") {
                        Task { await viewModel.load(apiClient: apiProvider.client, pickingId: pickingId) }
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle(transferTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(WorkplaceTheme.canvas)
        .tint(WorkplaceTheme.accent)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { barcodeFocused = false }
            }
            if let detail = viewModel.detail, isEditable(detail) {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan", systemImage: "barcode.viewfinder")
                    }
                    .accessibilityLabel("Scan barcode")
                    .disabled(viewModel.isLoading || viewModel.isSubmitting || viewModel.needsRefresh)
                }
            }
        }
        .workplaceBottomBar {
            if let detail = viewModel.detail, isEditable(detail) {
                Button {
                    confirmCompletion = true
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isSubmitting { ProgressView().tint(.white) }
                        Label(viewModel.isSubmitting ? "Saving…" : "Review \(transferTitle.lowercased())", systemImage: "checklist")
                            .fontWeight(.semibold)
                    }.frame(maxWidth: .infinity, minHeight: 28)
                }
                .workplaceProminentControl()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isLoading || viewModel.isSubmitting || viewModel.needsRefresh)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
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

    private var transferTitle: String {
        switch viewModel.detail?.pickingTypeCode {
        case "incoming": return "Receipt"
        case "outgoing": return "Delivery"
        default: return "Transfer"
        }
    }

    private func isEditable(_ detail: PickingDetail) -> Bool {
        !["done", "cancel"].contains(detail.state)
    }

    private func playFeedback(for status: String) {
        let generator = UINotificationFeedbackGenerator()
        switch status {
        case "success", "validated":
            if hapticsEnabled { generator.notificationOccurred(.success) }
            AudioServicesPlaySystemSound(1104)
        case "queued":
            if hapticsEnabled { generator.notificationOccurred(.warning) }
            AudioServicesPlaySystemSound(1054)
        default:
            if hapticsEnabled { generator.notificationOccurred(.error) }
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
    @State private var confirmDiscard = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case quantity, lot }
    private var initialQuantity: String {
        move.tracking == "serial" ? "1" : move.qtyDemanded.formatted(.number.precision(.fractionLength(0...3)))
    }
    private var hasUnsavedChanges: Bool { quantityText != initialQuantity || !lotName.isEmpty }

    init(move: PickingMove, onSave: @escaping (Double, String?) async -> Bool) {
        self.move = move
        self.onSave = onSave
        _quantityText = State(initialValue: move.tracking == "serial" ? "1" : move.qtyDemanded.formatted(.number.precision(.fractionLength(0...3))))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(move.productName).font(.headline).accessibilityAddTraits(.isHeader)
                }
                Section("Received") {
                    TextField("Quantity", text: $quantityText).keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold)).monospacedDigit().frame(minHeight: 44)
                        .focused($focusedField, equals: .quantity)
                        .accessibilityLabel("Received quantity for \(move.productName)")
                        .accessibilityValue("\(quantityText) \(move.uomName ?? "")")
                    Text("Demanded: \(move.qtyDemanded.formatted()) \(move.uomName ?? "")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if move.tracking == "lot" || move.tracking == "serial" {
                    Section(move.tracking == "serial" ? "Serial number" : "Lot") {
                        TextField(move.tracking == "serial" ? "Serial number" : "Lot name", text: $lotName)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled().frame(minHeight: 44)
                            .focused($focusedField, equals: .lot)
                            .accessibilityLabel("\(move.tracking == "serial" ? "Serial number" : "Lot") for \(move.productName)")
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                        if move.tracking == "serial" {
                            Text("Receive one serial at a time. Use Receive product again for the next serial.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                if let validationMessage {
                    Section {
                        WorkplaceNotice(title: "Check the received quantity", message: validationMessage,
                            symbol: "exclamationmark.circle", tint: WorkplaceTheme.danger)
                    }
                }
                if isSaving { ProgressView("Saving received quantity…").frame(maxWidth: .infinity, minHeight: 44) }
            }
            .disabled(isSaving)
            .scrollDismissesKeyboard(.interactively)
            .workplaceScreen()
            .navigationTitle("Receive product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving)
                        .accessibilityLabel("Save received quantity for \(move.productName)")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField == .quantity && (move.tracking == "lot" || move.tracking == "serial") {
                        Button("Next") { focusedField = .lot }
                    }
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Your changes to \(move.productName) haven’t been saved.") }
        }
        .interactiveDismissDisabled(isSaving || hasUnsavedChanges)
    }

    private func cancel() {
        focusedField = nil
        if hasUnsavedChanges { confirmDiscard = true } else { dismiss() }
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
    @State private var confirmDiscard = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case quantity, lot }
    private var hasUnsavedChanges: Bool {
        quantityText != line.qtyDone.formatted(.number.precision(.fractionLength(0...3))) || lotName != (line.lotName ?? "")
    }

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
                Section {
                    Text(line.productName).font(.headline).accessibilityAddTraits(.isHeader)
                }
                Section("Received") {
                    TextField("Quantity", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold)).monospacedDigit().frame(minHeight: 44)
                        .focused($focusedField, equals: .quantity)
                        .accessibilityLabel("Received quantity for \(line.productName)")
                        .accessibilityValue("\(quantityText) \(line.uomName ?? "")")
                    Text("Demanded: \(line.qtyDemanded.formatted()) \(line.uomName ?? "")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if line.tracking == "lot" || line.tracking == "serial" {
                    Section(line.tracking == "serial" ? "Serial number" : "Lot") {
                        TextField(line.tracking == "serial" ? "Serial number" : "Lot name", text: $lotName)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled().frame(minHeight: 44)
                            .focused($focusedField, equals: .lot)
                            .accessibilityLabel("\(line.tracking == "serial" ? "Serial number" : "Lot") for \(line.productName)")
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                        if line.lotId == nil && permitsNewLot {
                            Text("If this name does not exist, Odoo may create it for this receipt when the operation allows new lots.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let validationMessage {
                    Section {
                        WorkplaceNotice(title: "Check the received quantity", message: validationMessage,
                            symbol: "exclamationmark.circle", tint: WorkplaceTheme.danger)
                    }
                }
                if isSaving { ProgressView("Saving received quantity…").frame(maxWidth: .infinity, minHeight: 44) }
            }
            .disabled(isSaving)
            .scrollDismissesKeyboard(.interactively)
            .workplaceScreen()
            .navigationTitle("Received quantity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving)
                        .accessibilityLabel("Save received quantity for \(line.productName)")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField == .quantity && (line.tracking == "lot" || line.tracking == "serial") {
                        Button("Next") { focusedField = .lot }
                    }
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Your changes to \(line.productName) haven’t been saved.") }
        }
        .interactiveDismissDisabled(isSaving || hasUnsavedChanges)
    }

    private func cancel() {
        focusedField = nil
        if hasUnsavedChanges { confirmDiscard = true } else { dismiss() }
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
        WorkplaceNotice(title: "You’re offline",
            message: pendingCount > 0 ? "\(pendingCount) changes are waiting to sync. Connect before updating inventory." : "Connect before updating inventory.",
            symbol: "wifi.slash")
    }
}

struct RefreshBanner: View {
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkplaceNotice(title: "Refresh required",
                message: "Load the latest quantities before continuing.", symbol: "arrow.clockwise")
            Button("Refresh") {
                onRefresh()
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WarningMessage: Identifiable {
    let id = UUID()
    let text: String
}
