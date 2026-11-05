import SwiftUI

private enum PackingScanMode: String, Identifiable {
    case lookup, finish
    var id: String { rawValue }
}

struct PackingView: View {
    let shipmentId: Int?
    private let model: PackingViewModel?
    @EnvironmentObject private var authStore: AuthStore

    @MainActor
    init(shipmentId: Int? = nil, model: PackingViewModel? = nil) {
        self.shipmentId = shipmentId
        self.model = model
    }

    var body: some View {
        PackingWorkspaceView(shipmentId: shipmentId, model: model)
            .id("\(authStore.user?.id ?? 0):\(authStore.activeCompanyId ?? authStore.user?.companyId ?? 0)")
    }
}

private struct PackingWorkspaceView: View {
    let shipmentId: Int?
    @EnvironmentObject private var apiProvider: APIClientProvider
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var model: PackingViewModel
    @State private var scanMode: PackingScanMode?
    @State private var completedFinishCount = 0
    @AppStorage("workplaceHapticsEnabled") private var hapticsEnabled = true

    @MainActor
    init(shipmentId: Int? = nil, model: PackingViewModel? = nil) {
        self.shipmentId = shipmentId
        _model = StateObject(wrappedValue: model ?? PackingViewModel())
    }

    private var companyId: Int? { authStore.activeCompanyId ?? authStore.user?.companyId }
    private var isPreviewOnly: Bool { model.canUsePacking && !model.canWritePacking }

    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var availabilityMessage: String {
        if isPreviewOnly {
            return networkMonitor.isOnline
                ? "You can view the products. Picking confirmation is not active."
                : "Reconnect to view a label. Picking confirmation is not active."
        }
        return "Reconnect to view a label and confirm packing."
    }

    var body: some View {
        List {
            if let detail = model.detail {
                Section {
                    VStack(alignment: .leading, spacing: 18) {
                        PackingOrderSummary(detail: detail)
                        PackingCardInstruction(detail: detail)
                        nextStep(for: detail)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                Section {
                    ForEach(detail.items) { item in
                        PackingItemRow(item: item, editable: model.canEdit && networkMonitor.isOnline) {
                            Task {
                                await model.setQuantity(lineId: item.lineId, quantity: item.isConfirmed ? 0 : item.requiredQuantity,
                                                        client: apiProvider.client, online: networkMonitor.isOnline)
                            }
                        }
                        .listRowBackground(item.isConfirmed ? WorkplaceTheme.accent.opacity(0.04) : WorkplaceTheme.surface)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                } header: {
                    let headerLayout = textSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                        : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
                    headerLayout {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Products").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            if model.canEdit && !textSize.isAccessibilitySize {
                                Text("Tap an item when packed").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !isPreviewOnly && detail.workflowVersion != "legacy_print" {
                            Text("\(detail.items.filter(\.isConfirmed).count) / \(detail.items.count) picked")
                                .font(.caption).monospacedDigit()
                        }
                    }.textCase(nil).padding(.vertical, 6)
                }
                if detail.boxCount > 1 {
                    Section("Boxes in this order") {
                        ForEach(detail.siblings) { box in
                            PackingSiblingRow(box: box, isCurrent: box.shipmentId == detail.shipmentId)
                        }
                    }
                }
                Section {
                    DisclosureGroup("Label details") {
                        PackingLabelDetails(detail: detail, currentUserId: authStore.user?.id)
                    }
                }
                if detail.isPacked || detail.needsReview {
                    Section {
                        Button { Task { await model.refresh(client: apiProvider.client, online: networkMonitor.isOnline) } } label: {
                            Label("Refresh status", systemImage: "arrow.clockwise")
                                .frame(minHeight: 44)
                        }.disabled(model.isBusy || !networkMonitor.isOnline)
                    }
                }
                if !model.requiresRefresh && !detail.isPacked && !detail.needsReview && model.canWritePacking && detail.workflowVersion == "packing_v1" {
                    Section {
                        anotherLabelButton(title: "Scan another label")
                    }
                }
            } else {
                if isPreviewOnly || !networkMonitor.isOnline {
                    Section {
                        WorkplaceNotice(title: isPreviewOnly ? "Preview only" : "You’re offline",
                                        message: availabilityMessage,
                                        symbol: networkMonitor.isOnline ? "eye" : "wifi.slash",
                                        tint: isPreviewOnly ? WorkplaceTheme.information : WorkplaceTheme.attention)
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Scan a shipping label").font(.title2.weight(.semibold))
                            Text("See this box’s products and quantities.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 64, weight: .ultraLight))
                            .foregroundStyle(WorkplaceTheme.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 32)
                            .accessibilityHidden(true)
                        Button { scanMode = .lookup } label: {
                            Label("Scan shipping label", systemImage: "viewfinder")
                        }.workplaceProminentControl()
                            .disabled(!model.canUsePacking || model.isBusy || !networkMonitor.isOnline)
                            .accessibilityIdentifier("packing-open-label")
                        if !isPreviewOnly {
                            DisclosureGroup("How packing works") {
                              VStack(alignment: .leading, spacing: 18) {
                                packingStep("1", title: "Scan the label", detail: "Open the right order and box.")
                                packingStep("2", title: "Check each product", detail: "Confirm the full quantity as you pack.")
                                packingStep("3", title: "Scan to finish", detail: "Use the same label to complete the box.")
                              }.padding(.top, 16)
                            }.font(.subheadline)
                        }
                    }.padding(.vertical, 16)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }

                if let message = model.errorMessage {
                    Section {
                        WorkplaceNotice(title: "Couldn’t open this label", message: message,
                                        symbol: "exclamationmark.triangle", tint: WorkplaceTheme.attention)
                        Button("Try again") { Task { await prepare() } }
                            .frame(minHeight: 44).buttonStyle(.bordered)
                            .disabled(model.isBusy || !networkMonitor.isOnline)
                    }
                }
            }
            if model.isBusy {
                Section { ProgressView("Checking packing details…").padding(.vertical, 10) }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(12)
        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
        .workplaceScreen()
        .workplaceBottomBar(isPresented: model.detail != nil) {
            if let detail = model.detail {
                if model.requiresRefresh {
                    Button { Task { await model.refresh(client: apiProvider.client, online: networkMonitor.isOnline) } } label: {
                        Label("Refresh status", systemImage: "arrow.clockwise")
                            .fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 28)
                    }.workplaceProminentControl()
                        .disabled(model.isBusy || !networkMonitor.isOnline)
                        .accessibilityHint("Read the latest result before confirming more products or finishing again.")
                } else if model.canWritePacking && detail.workflowVersion == "packing_v1" && !detail.isPacked && !detail.needsReview {
                    VStack(spacing: 8) {
                        if !textSize.isAccessibilitySize && verticalSizeClass != .compact {
                            Text(finishReason(for: detail)).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button {
                            if model.beginFinish() { scanMode = .finish }
                        } label: {
                            if textSize.isAccessibilitySize {
                                Text("Finish box \(detail.boxNumber)").frame(maxWidth: .infinity, minHeight: 28)
                            } else {
                                Label("Scan to finish box \(detail.boxNumber)", systemImage: "barcode.viewfinder")
                                    .fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 28)
                            }
                        }
                        .workplaceProminentControl()
                        .disabled(!model.canFinish || !networkMonitor.isOnline)
                        .accessibilityIdentifier("packing-finish")
                        .accessibilityLabel("Scan to finish box \(detail.boxNumber) for \(detail.orderName)")
                        .accessibilityHint(finishReason(for: detail))
                    }
                } else {
                    anotherLabelButton(title: "Scan next label").workplaceProminentControl()
                }
            }
        }
        .navigationTitle(model.detail?.orderName ?? "Pack orders")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            if model.detail != nil { await model.refresh(client: apiProvider.client, online: networkMonitor.isOnline) }
            else { await prepare() }
        }
        .task { await prepare() }
        .sheet(item: $scanMode, onDismiss: { model.cancelFinish() }) { mode in
            PackingLabelScanner(isFinishing: mode == .finish, onScan: { candidates in
                let accepted: Bool
                if mode == .finish {
                    accepted = await model.finish(candidates: candidates, client: apiProvider.client, online: networkMonitor.isOnline,
                                                  userId: authStore.user?.id ?? 0, companyId: companyId)
                    if accepted && model.detail?.isPacked == true && model.detail?.needsReview == false {
                        completedFinishCount += 1
                    }
                } else {
                    accepted = await model.resolve(candidates: candidates, client: apiProvider.client, online: networkMonitor.isOnline)
                }
                if model.requiresRefresh { scanMode = nil }
                return accepted
            }, message: { model.errorMessage })
        }
        .sensoryFeedback(.success, trigger: completedFinishCount) { _, _ in hapticsEnabled }
        .onChange(of: model.errorMessage) { _, message in
            if scanMode == nil, let message { UIAccessibility.post(notification: .announcement, argument: message) }
        }
    }

    private func prepare() async {
        await model.prepare(client: apiProvider.client, online: networkMonitor.isOnline,
                            userId: authStore.user?.id ?? 0, companyId: companyId, shipmentId: shipmentId)
    }

    private func packingStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.caption.monospaced().weight(.medium))
                .foregroundStyle(WorkplaceTheme.accent).frame(width: 28, height: 28)
                .background(WorkplaceTheme.accent.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }

    private func anotherLabelButton(title: String) -> some View {
        Button { model.resetForAnotherLabel(); scanMode = .lookup } label: {
            Label(title, systemImage: "barcode.viewfinder")
                .fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 28)
        }.disabled(model.isBusy || !networkMonitor.isOnline || !model.canUsePacking)
    }

    private func finishReason(for detail: PackingDetail) -> String {
        if !networkMonitor.isOnline { return "Reconnect to finish." }
        if model.isBusy { return "Saving confirmation…" }
        if !detail.allItemsConfirmed {
            let remaining = detail.items.filter { !$0.isConfirmed }.count
            return remaining == 1 ? "1 product left to confirm" : "\(remaining) products left to confirm"
        }
        if !model.canFinish { return "Finishing is unavailable. Ask a supervisor." }
        return "Scan this box’s label to finish."
    }

    @ViewBuilder
    private func nextStep(for detail: PackingDetail) -> some View {
        if model.requiresRefresh {
            PackingNextStep(title: "Refresh before continuing",
                            message: model.errorMessage ?? "Check the latest result before confirming more products or finishing again.",
                            symbol: "arrow.clockwise.circle", tint: WorkplaceTheme.attention)
        } else if detail.needsReview {
            PackingNextStep(title: detail.isPacked ? "Box packed — review needed" : "Ask a supervisor",
                            message: detail.statusExplanation, symbol: "exclamationmark.triangle.fill", tint: WorkplaceTheme.attention)
        } else if detail.workflowVersion == "legacy_print" {
            PackingNextStep(title: "Previous workflow label", message: detail.statusExplanation,
                            symbol: "info.circle", tint: WorkplaceTheme.information)
        } else if isPreviewOnly {
            PackingNextStep(title: "View products only", message: "Picking confirmation is not active for this app.",
                            symbol: "eye", tint: WorkplaceTheme.information)
        } else if detail.isPacked {
            PackingNextStep(title: detail.statusTitle, message: detail.statusExplanation,
                            symbol: "checkmark.circle.fill", tint: WorkplaceTheme.success)
        } else if !networkMonitor.isOnline {
            PackingNextStep(title: "Reconnect to continue", message: "Confirm products and finish this box when you’re online.",
                            symbol: "wifi.slash", tint: WorkplaceTheme.attention)
        } else if let message = model.errorMessage {
            PackingNextStep(title: "Check this box", message: message,
                            symbol: "exclamationmark.triangle", tint: WorkplaceTheme.attention)
        } else if !detail.canEdit && !detail.canFinish {
            if let owner = detail.owner, owner.id != authStore.user?.id {
                PackingNextStep(title: "Assigned to \(owner.name)", message: "Ask a supervisor to change the assignment before confirming products.",
                                symbol: "person.crop.circle", tint: WorkplaceTheme.attention)
            } else {
                PackingNextStep(title: "Confirmation unavailable", message: "Ask a supervisor to check this box’s status.",
                                symbol: "lock", tint: WorkplaceTheme.attention)
            }
        }

    }
}

struct PackingOrderSummary: View {
    let detail: PackingDetail
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Box \(detail.boxNumber) of \(detail.boxCount)")
                    .font(.subheadline.weight(.medium)).foregroundStyle(WorkplaceTheme.accent)
                Spacer()
                if let carrier = detail.carrier, !carrier.isEmpty {
                    Text(carrier.uppercased()).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            if let name = detail.customerName, !name.isEmpty {
                Text(name).font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            }
        }.accessibilityElement(children: .combine)
    }
}

private struct PackingCardInstruction: View {
    let detail: PackingDetail
    private var tint: Color { detail.customerOrderCount == nil ? WorkplaceTheme.attention : WorkplaceTheme.accent }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "ticket").font(.body).foregroundStyle(tint).padding(.top, 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.customerHistoryTitle).font(.caption).foregroundStyle(.secondary)
                Text(detail.discountCardInstruction).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("packing.discountCard")
    }
}

private struct PackingNextStep: View {
    let title: String
    let message: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }
}

private struct PackingLabelDetails: View {
    let detail: PackingDetail
    let currentUserId: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let carrier = detail.carrier, !carrier.isEmpty {
                Label(carrier.uppercased(), systemImage: "truck.box").font(.subheadline)
            }
            Text(detail.trackingNumber).font(.subheadline.monospaced()).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Tracking number").accessibilityValue(detail.trackingNumber)
            if let owner = detail.owner {
                Label(owner.id == currentUserId ? "Assigned to you" : "Assigned to \(owner.name)", systemImage: "person.crop.circle")
                    .font(.subheadline)
            } else if detail.canEdit {
                Text("Confirming the first product assigns this order to you.").font(.subheadline)
            }
            if let completedAt = detail.completedAt, detail.isPacked,
               let date = ISO8601DateFormatter().date(from: completedAt) {
                Label("Packed \(date.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.subheadline)
            }
        }.foregroundStyle(.secondary).padding(.vertical, 8)
    }
}

struct PackingItemRow: View {
    let item: PackingItem
    let editable: Bool
    let onToggle: () -> Void
    @Environment(\.dynamicTypeSize) private var textSize

    private var package: String? {
        guard let variant = item.variantTitle, !variant.isEmpty, variant != "Default Title" else { return nil }
        return variant
    }

    var body: some View {
        Group {
            if editable {
                Button(action: onToggle) { content }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("packing-item-\(item.lineId)")
                    .accessibilityLabel(item.isConfirmed ? "Undo confirmation for \(item.displayTitle)"
                                        : "Confirm all \(item.requiredQuantity.formatted()) \(item.displayTitle) picked")
                    .accessibilityValue("\(item.confirmedQuantity.formatted()) of \(item.requiredQuantity.formatted()) picked")
            } else { content.accessibilityElement(children: .combine) }
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 14) {
            if editable || item.isConfirmed {
                Image(systemName: item.isConfirmed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(item.isConfirmed ? WorkplaceTheme.accent : Color.secondary)
                    .padding(.top, 3).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let package { Text(package).font(.subheadline).foregroundStyle(.secondary) }
                if let sku = item.sku, !sku.isEmpty {
                    Text("SKU \(sku)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                if item.isConfirmed {
                    Text("Picked").font(.caption.weight(.medium)).foregroundStyle(WorkplaceTheme.accent)
                } else if item.confirmedQuantity > 0 {
                    Text("\(item.confirmedQuantity.formatted()) picked · \(item.remainingQuantity.formatted()) left")
                        .font(.caption).foregroundStyle(WorkplaceTheme.attention).monospacedDigit()
                }
                if textSize.isAccessibilitySize { quantity }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !textSize.isAccessibilitySize { quantity }
        }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle()).padding(.vertical, 5)
    }

    private var quantity: some View {
        Text("×\(item.requiredQuantity.formatted())")
            .font(.title3.weight(.semibold)).monospacedDigit()
            .foregroundStyle(.primary)
            .fixedSize().padding(.top, 1)
            .accessibilityLabel("Required quantity: \(item.requiredQuantity.formatted())")
    }
}

private struct PackingSiblingRow: View {
    let box: PackingSibling
    let isCurrent: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var status: String {
        box.packingState == "packed" ? "Packed" : box.packingState == "review" ? "Review" : "To pick"
    }
    private var symbol: String {
        box.packingState == "packed" ? "checkmark.circle.fill" : box.packingState == "review" ? "exclamationmark.triangle" : "shippingbox"
    }
    private var tint: Color {
        box.packingState == "packed" ? WorkplaceTheme.success : box.packingState == "review" ? WorkplaceTheme.attention : WorkplaceTheme.accent
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) { boxTitle; statusPill }
            } else {
                HStack(spacing: 12) { boxTitle; Spacer(minLength: 8); statusPill }
            }
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }
    private var boxTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Box \(box.boxNumber)").font(.body.weight(.medium))
            if isCurrent { Text("This box").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var statusPill: some View { WorkplaceStatusPill(text: status, symbol: symbol, tint: tint) }
}
