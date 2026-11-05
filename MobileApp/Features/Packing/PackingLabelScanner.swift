import SwiftUI

struct PackingLabelScanner: View {
    let isFinishing: Bool
    let onScan: ([BarcodeCandidate]) async -> Bool
    let message: () -> String?
    private let usesPreviewCamera: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var state: ScannerCameraState = .checkingPermission
    @State private var generation = 0
    @State private var paused = false
    @State private var submitting = false
    @State private var manualTracking = ""
    @State private var failure: String?
    @State private var manualEntryExpanded = false
    @FocusState private var manualEntryFocused: Bool
    @Environment(\.dynamicTypeSize) private var textSize

    init(isFinishing: Bool, onScan: @escaping ([BarcodeCandidate]) async -> Bool,
         message: @escaping () -> String?, previewCameraState: ScannerCameraState? = nil,
         previewFailure: String? = nil) {
        self.isFinishing = isFinishing
        self.onScan = onScan
        self.message = message
        usesPreviewCamera = previewCameraState != nil
        _state = State(initialValue: previewCameraState ?? .checkingPermission)
        _manualEntryExpanded = State(initialValue: previewCameraState != nil)
        _failure = State(initialValue: previewFailure)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if usesPreviewCamera { Color.black }
                else { ScannerCameraView(isScanning: !paused, generation: generation, onFound: submit, onStateChange: { state = $0 }) }
                if state == .ready && !paused { ScannerTarget() }
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 16) {
                            scanningInstructions
                            Spacer(minLength: 24)
                            scannerControls
                        }
                        .frame(minHeight: max(0, geometry.size.height - 32))
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .background(.black)
            .tint(WorkplaceTheme.accent)
            .navigationTitle(isFinishing ? "Finish this box" : "Scan label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).disabled(submitting)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { manualEntryFocused = false }
                }
            }
            .interactiveDismissDisabled(submitting)
            .onChange(of: failure) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: "Label not confirmed. " + message) }
            }
        }
    }

    private var scanningInstructions: some View {
        HStack(alignment: .top, spacing: 12) {
            if !textSize.isAccessibilitySize {
                Image(systemName: isFinishing ? "shippingbox.fill" : "barcode.viewfinder")
                    .font(.title2).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(isFinishing ? "Scan the label on this box" : "Scan the shipping barcode")
                    .font(.headline).accessibilityAddTraits(.isHeader)
                Text(isFinishing ? "Use the same label you scanned to open this box." : "The tracking barcode opens this box’s products and quantities.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scannerMessageStyle()
    }

    private var scannerControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            if submitting {
                ProgressView(isFinishing ? "Checking and finishing…" : "Finding your box…")
                    .padding(.vertical, 4)
            }
            if let failure {
                WorkplaceNotice(title: "Label not confirmed", message: failure,
                                symbol: "exclamationmark.triangle", tint: WorkplaceTheme.danger)
                Button {
                    generation += 1
                    paused = false
                    self.failure = nil
                } label: {
                    Label("Scan again", systemImage: "barcode.viewfinder")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }.workplaceProminentControl()
            }
            if state != .ready {
                WorkplaceNotice(title: "Camera access", message: cameraMessage,
                                symbol: "camera", tint: WorkplaceTheme.attention)
            }
            if !submitting {
                DisclosureGroup(isExpanded: $manualEntryExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Tracking number", text: $manualTracking)
                            .textFieldStyle(.roundedBorder).frame(minHeight: 44).padding(.top, 8)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.asciiCapable).submitLabel(.go)
                            .focused($manualEntryFocused)
                            .onSubmit { submitManual() }
                            .accessibilityIdentifier("packing-manual-tracking")
                        Button { submitManual() } label: {
                            Label(isFinishing ? "Finish this box" : "Open box",
                                  systemImage: isFinishing ? "checkmark" : "arrow.right")
                                .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(manualTracking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.bordered)
                    }
                } label: {
                    Label("Enter tracking number", systemImage: "keyboard")
                        .font(.body.weight(.medium)).padding(.vertical, 6)
                }
            }
        }.scannerPanelStyle()
    }

    private var cameraMessage: String {
        switch state {
        case .checkingPermission: "Checking camera access…"
        case .requestingPermission: "Allow camera access to scan your label."
        case .denied: "Camera access is off. Enable Camera in Settings, or enter the tracking number below."
        case .unavailable: "No camera is available. Enter the tracking number below."
        case .failed: "The camera couldn’t start. Enter the tracking number below."
        case .ready: "Place the tracking barcode inside the frame."
        }
    }

    private func submitManual() {
        let value = manualTracking.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        submit([BarcodeCandidate(barcode: value, symbology: "manual")])
    }

    private func submit(_ candidates: [BarcodeCandidate]) {
        guard !submitting else { return }
        paused = true
        submitting = true
        failure = nil
        Task {
            let accepted = await onScan(candidates)
            submitting = false
            if accepted { dismiss() }
            else { failure = message() ?? "This label wasn’t confirmed. Review the box and try again." }
        }
    }
}
