import SwiftUI

struct PackingLabelScanner: View {
    let isFinishing: Bool
    let onScan: ([BarcodeCandidate]) async -> Bool
    let message: () -> String?
    private let usesPreviewCamera: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var state: ScannerCameraState = .checkingPermission
    @State private var generation = 0
    @State private var paused = false
    @State private var submitting = false
    @State private var manualTracking = ""
    @State private var failure: String?
    @State private var manualEntryExpanded = false
    @FocusState private var manualEntryFocused: Bool

    init(isFinishing: Bool, onScan: @escaping ([BarcodeCandidate]) async -> Bool,
         message: @escaping () -> String?, previewCameraState: ScannerCameraState? = nil,
         previewFailure: String? = nil) {
        self.isFinishing = isFinishing
        self.onScan = onScan
        self.message = message
        usesPreviewCamera = previewCameraState != nil
        _state = State(initialValue: previewCameraState ?? .checkingPermission)
        _failure = State(initialValue: previewFailure)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                if !usesPreviewCamera {
                    ScannerCameraView(isScanning: !paused && !manualEntryExpanded, generation: generation,
                                      onFound: submit, onStateChange: { state = $0 })
                }
                if !paused { ScannerTarget().allowsHitTesting(false) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        if submitting {
                            ProgressView(isFinishing ? "Finishing box…" : "Finding box…")
                        } else if let failure {
                            Text(failure).font(.subheadline).multilineTextAlignment(.center)
                            Button("Scan again") { generation += 1; paused = false; self.failure = nil }
                                .buttonStyle(.borderedProminent)
                        } else if state == .ready {
                            Text(isFinishing ? "Scan this box’s shipping barcode" : "Point at the shipping barcode")
                                .font(.subheadline).multilineTextAlignment(.center)
                        } else {
                            Text(state.message).font(.subheadline).multilineTextAlignment(.center)
                            if state == .failed {
                                Button("Restart camera") { generation += 1 }.buttonStyle(.bordered)
                            }
                        }
                        Button("Enter tracking number") { manualEntryExpanded = true }
                            .font(.subheadline).frame(minHeight: 44).disabled(submitting)
                    }.frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 16)
                }
                .frame(height: verticalSizeClass == .compact ? 120 : (failure != nil || textSize.isAccessibilitySize ? 220 : 130))
                .clipped()
                .background(.bar)
            }
            .navigationTitle(isFinishing ? "Finish box" : "Scan label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(submitting)
                }
            }
            .sheet(isPresented: $manualEntryExpanded) {
                NavigationStack {
                    Form {
                        Section("Tracking number") {
                            TextField("Type the number below the barcode", text: $manualTracking)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .keyboardType(.asciiCapable).focused($manualEntryFocused)
                                .accessibilityIdentifier("packing-manual-tracking")
                                .onSubmit { submitManual() }
                        }
                        Button(isFinishing ? "Finish box" : "Find box") { submitManual() }
                            .disabled(manualTracking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting)
                    }
                    .navigationTitle("Enter tracking number").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { manualEntryExpanded = false } } }
                    .onAppear { manualEntryFocused = true }
                }.presentationDetents([.medium, .large])
            }
            .interactiveDismissDisabled(submitting)
            .onChange(of: failure) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: "Label not confirmed. " + message) }
            }
        }
    }

    private func submitManual() {
        let value = manualTracking.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        manualEntryExpanded = false
        submit([BarcodeCandidate(barcode: value, symbology: "manual")])
    }

    private func submit(_ candidates: [BarcodeCandidate]) {
        guard !submitting else { return }
        paused = true; submitting = true; failure = nil
        Task {
            let accepted = await onScan(candidates)
            submitting = false
            if accepted { dismiss() }
            else { failure = message() ?? "This label wasn’t confirmed. Check the label and try again." }
        }
    }
}

extension ScannerCameraState {
    var message: String {
        switch self {
        case .checkingPermission: "Checking camera…"
        case .requestingPermission: "Allow camera access to scan."
        case .starting: "Starting camera…"
        case .ready: "Point at a barcode"
        case .denied: "Allow Camera in iPhone Settings to scan."
        case .unavailable: "No camera is available."
        case .interrupted: "Camera paused. Return to the app to resume."
        case .failed: "The camera couldn’t start. Try again."
        }
    }
}

/// Uses the production scanner without calling any business APIs.
struct ScannerTestView: View {
    @State private var cameraState: ScannerCameraState = .checkingPermission
    @State private var generation = 0
    @State private var result: String?
    @State private var scans = 0
    @State private var started = Date()
    @State private var elapsed: TimeInterval?
    var body: some View {
        ZStack {
            ScannerCameraView(isScanning: result == nil, generation: generation, onFound: { candidates in
                result = candidates.map(\.barcode).joined(separator: "\n")
                elapsed = Date().timeIntervalSince(started)
                scans += 1
            }, onStateChange: { cameraState = $0 })
            if result == nil { ScannerTarget().allowsHitTesting(false) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if let result {
                    Label("Scan \(scans) detected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(result).font(.body.monospaced()).textSelection(.enabled)
                    if let elapsed { Text("\(elapsed.formatted(.number.precision(.fractionLength(1)))) seconds since scan started").font(.caption).foregroundStyle(.secondary) }
                    Button("Scan again") { self.result = nil; elapsed = nil; started = Date(); generation += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text(cameraState.message).font(.subheadline)
                    if cameraState == .failed {
                        Button("Restart camera") { generation += 1 }
                    }
                }
                Text("Test only. No orders or stock are changed.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding().background(.bar)
        }
        .navigationTitle("Test scanner").navigationBarTitleDisplayMode(.inline)
        .onAppear { started = Date() }
    }
}
