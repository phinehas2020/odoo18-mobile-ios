import AVFoundation
import SwiftUI

struct BarcodeScannerView: View {
    let onConfirm: (String) async -> Bool
    private let previewCameraState: ScannerCameraState?

    @Environment(\.dismiss) private var dismiss
    @State private var detectedCode: String?
    @State private var detectedCandidates: [BarcodeCandidate] = []
    @State private var confirmedCode: String?
    @State private var cameraState: ScannerCameraState = .checkingPermission
    @State private var scanGeneration = 0
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @Environment(\.dynamicTypeSize) private var textSize

    init(previewCameraState: ScannerCameraState? = nil, onConfirm: @escaping (String) async -> Bool) {
        self.previewCameraState = previewCameraState
        self.onConfirm = onConfirm
        _cameraState = State(initialValue: previewCameraState ?? .checkingPermission)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if previewCameraState == nil {
                    ScannerCameraView(
                        isScanning: detectedCandidates.isEmpty && detectedCode == nil && confirmedCode == nil,
                        generation: scanGeneration,
                        onFound: { candidates in
                            guard detectedCode == nil, confirmedCode == nil else { return }
                            detectedCandidates = candidates
                            if candidates.count == 1 { detectedCode = candidates[0].barcode }
                        },
                        onStateChange: { cameraState = $0 }
                    )
                }

                if cameraState == .ready && confirmedCode == nil {
                    ScannerTarget()
                }

            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) { cameraMessage; resultPanel }
                        .frame(maxWidth: .infinity).padding(16)
                }.frame(height: textSize.isAccessibilitySize ? 260 : 200).clipped().background(.bar)
            }

            .background(Color.black)
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)

            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).disabled(isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    @ViewBuilder
    private var cameraMessage: some View {
        switch cameraState {
        case .checkingPermission:
            Label("Checking camera access…", systemImage: "camera").scannerMessageStyle()
        case .starting:
            ProgressView("Starting camera…").scannerMessageStyle()
        case .interrupted:
            Label("Camera paused. Return to the app to resume.", systemImage: "camera").scannerMessageStyle()
        case .requestingPermission:
            Label("Allow camera access to scan", systemImage: "camera.badge.ellipsis").scannerMessageStyle()
        case .denied:
            VStack(spacing: 8) {
                Label("Camera access is off", systemImage: "camera.fill")
                Text("Enable Camera for this app in Settings, or type the barcode on the transfer screen.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .scannerMessageStyle()
        case .unavailable:
            Label("No camera is available. Type the barcode instead.", systemImage: "camera.fill").scannerMessageStyle()
        case .failed:
            Label("The camera couldn’t start. Type the barcode instead.", systemImage: "exclamationmark.triangle").scannerMessageStyle()
        case .ready:
            EmptyView()
        }
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let confirmedCode {
            VStack(alignment: .leading, spacing: 12) {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text(confirmedCode).font(.title3.monospaced()).textSelection(.enabled)
                if textSize.isAccessibilitySize {
                    VStack(spacing: 12) { nextButton; doneButton }
                } else {
                    HStack(spacing: 12) { nextButton; doneButton }
                }
            }
            .scannerPanelStyle()
        } else if let detectedCode {
            VStack(alignment: .leading, spacing: 12) {
                Text("Detected code").font(.headline)
                Text(detectedCode).font(.title3.monospaced()).textSelection(.enabled)
                Text("Confirm to add this scan to the transfer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isSubmitting { ProgressView("Adding scan…") }
                if let submissionError {
                    Text(submissionError).font(.caption).foregroundStyle(.red)
                }
                if textSize.isAccessibilitySize {
                    VStack(spacing: 12) { confirmButton(detectedCode); retryButton }
                } else {
                    HStack(spacing: 12) { confirmButton(detectedCode); retryButton }
                }
            }
            .scannerPanelStyle()
        } else if !detectedCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose the product barcode").font(.headline)
                ForEach(detectedCandidates) { candidate in
                    Button(candidate.barcode) { detectedCode = candidate.barcode }
                        .font(.body.monospaced()).frame(minHeight: 44)
                        .accessibilityLabel("Select barcode \(candidate.barcode)")
                }
                Button("Try again") { resetForNextScan() }
            }.scannerPanelStyle()
        } else if cameraState == .ready {
            Text("Point at the product barcode")
                .font(.callout)
                .multilineTextAlignment(.center)
                .scannerPanelStyle()
        }
    }

    private var nextButton: some View {
        Button { resetForNextScan() } label: { Text("Scan next").frame(maxWidth: .infinity, minHeight: 44) }
            .workplaceProminentControl()
    }

    private var doneButton: some View {
        Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.bordered).controlSize(.large)
    }

    private func confirmButton(_ code: String) -> some View {
        Button { submit(code) } label: { Text("Confirm code").frame(maxWidth: .infinity, minHeight: 44) }
            .workplaceProminentControl()
            .disabled(isSubmitting).accessibilityLabel("Confirm barcode \(code)")
    }

    private var retryButton: some View {
        Button { resetForNextScan() } label: { Text("Try again").frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.bordered).controlSize(.large)
            .disabled(isSubmitting)
    }

    private func resetForNextScan() {
        detectedCode = nil
        detectedCandidates = []
        confirmedCode = nil
        scanGeneration += 1
        submissionError = nil
    }

    private func submit(_ code: String) {
        isSubmitting = true
        submissionError = nil
        Task {
            let saved = await onConfirm(code)
            isSubmitting = false
            if saved {
                confirmedCode = code
            } else {
                submissionError = "This scan was not added. Review the notice and try again."
            }
        }
    }
}

struct ScannerTarget: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
            .frame(width: ScannerGeometry.targetSize.width, height: ScannerGeometry.targetSize.height)
            .shadow(color: .black.opacity(0.7), radius: 4)
            .accessibilityHidden(true)
    }
}

enum ScannerCameraState: Equatable {
    case checkingPermission, requestingPermission, starting, ready, denied, unavailable, interrupted, failed
}

struct BarcodeDetectionGate {
    private(set) var hasDelivered = false

    mutating func accept(_ value: String?) -> String? {
        guard !hasDelivered, let value, !value.isEmpty else { return nil }
        hasDelivered = true
        return value
    }

    mutating func reset() { hasDelivered = false }
}

struct ScannerCameraView: UIViewControllerRepresentable {
    let isScanning: Bool
    let generation: Int
    let onFound: ([BarcodeCandidate]) -> Void
    let onStateChange: (ScannerCameraState) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onFound = onFound
        controller.onStateChange = onStateChange
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        controller.onFound = onFound
        controller.onStateChange = onStateChange
        controller.setScanning(isScanning, generation: generation)
    }
}

/// All capture configuration and start/stop calls share one serial queue, including
/// across successive scanner presentations. UI updates and delivery stay on main.
final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: (([BarcodeCandidate]) -> Void)?
    var onStateChange: ((ScannerCameraState) -> Void)?
    private let session = AVCaptureSession()
    private static let cameraQueue = DispatchQueue(label: "com.homestead.mobile.camera", qos: .userInitiated)
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var detectionGate = BarcodeCandidateGate()
    private var isVisible = false
    private var wantsScanning = true
    private var generation = -1
    private var cameraState: ScannerCameraState = .checkingPermission
    private var captureObservers: [NSObjectProtocol] = []
    // Access only on cameraQueue.
    private var configured = false
    private let supportedTypes: [AVMetadataObject.ObjectType] = [.ean8, .ean13, .qr, .code128, .code39, .upce, .pdf417, .dataMatrix, .aztec, .interleaved2of5, .itf14]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = session
        view.layer.addSublayer(previewLayer)
        observe(.AVCaptureSessionInterruptionEnded) { controller in controller.startCamera() }
        observe(.AVCaptureSessionWasInterrupted) { controller in controller.publish(.interrupted) }
        captureObservers.append(NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError, object: session, queue: .main
        ) { [weak self] notification in
            guard let self, self.isVisible else { return }
            if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError,
               error.code == .mediaServicesWereReset { self.startCamera() }
            else { self.publish(.failed) }
        })
        captureObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.prepareCamera()
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        prepareCamera()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // SwiftUI may replace the callback during sheet presentation. Replay state.
        publish(cameraState)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        Self.cameraQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    deinit {
        for observer in captureObservers { NotificationCenter.default.removeObserver(observer) }
        Self.cameraQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func setScanning(_ enabled: Bool, generation: Int) {
        wantsScanning = enabled
        if self.generation != generation {
            self.generation = generation
            detectionGate.reset()
            if isVisible && enabled && cameraState == .failed { prepareCamera() }
        }
        // Pause delivery, not the camera. Confirm/retry must not restart hardware.
    }

    private func observe(_ name: Notification.Name, action: @escaping (ScannerViewController) -> Void) {
        captureObservers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { [weak self] _ in
            guard let self, self.isVisible else { return }
            action(self)
        })
    }

    private func publish(_ state: ScannerCameraState) {
        cameraState = state
        onStateChange?(state)
    }

    private func prepareCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startCamera()
        case .notDetermined:
            publish(.requestingPermission)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.isVisible else { return }
                    allowed ? self.startCamera() : self.publish(.denied)
                }
            }
        case .denied, .restricted: publish(.denied)
        @unknown default: publish(.failed)
        }
    }

    private func startCamera() {
        guard isVisible else { return }
        publish(.starting)
        Self.cameraQueue.async { [weak self] in
            guard let self else { return }
            let result = self.configureAndStart()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isVisible else { return }
                self.publish(result)
            }
        }
    }

    private func configureAndStart() -> ScannerCameraState {
        if !configured {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return .unavailable }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureMetadataOutput()
                session.beginConfiguration()
                if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
                guard session.canAddInput(input) else { session.commitConfiguration(); return .failed }
                session.addInput(input)
                guard session.canAddOutput(output) else {
                    session.removeInput(input); session.commitConfiguration(); return .failed
                }
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                // The whole image is searchable. The aiming guide is never a hidden crop.
                output.rectOfInterest = ScannerGeometry.fullFrameRegion
                session.commitConfiguration()
                output.metadataObjectTypes = supportedTypes.filter { output.availableMetadataObjectTypes.contains($0) }
                guard !output.metadataObjectTypes.isEmpty else {
                    session.beginConfiguration(); session.removeOutput(output); session.removeInput(input); session.commitConfiguration()
                    return .failed
                }
                configured = true
            } catch { return .failed }
        }
        if !session.isRunning { session.startRunning() }
        return session.isRunning ? .ready : .failed
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard wantsScanning, isVisible else { return }
        let candidates = metadataObjects.compactMap { object -> BarcodeCandidate? in
            guard let code = object as? AVMetadataMachineReadableCodeObject,
                  let barcode = code.stringValue, !barcode.isEmpty else { return nil }
            return BarcodeCandidate(barcode: barcode, symbology: Self.symbology(code.type))
        }
        guard let accepted = detectionGate.accept(candidates) else { return }
        wantsScanning = false
        publish(.ready)
        onFound?(accepted)
    }
    private static func symbology(_ type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .code128: return "code128"
        case .code39: return "code39"
        case .ean8: return "ean8"
        case .ean13: return "ean13"
        case .upce: return "upce"
        case .qr: return "qr"
        case .pdf417: return "pdf417"
        case .dataMatrix: return "data_matrix"
        case .aztec: return "aztec"
        case .interleaved2of5: return "interleaved2of5"
        case .itf14: return "itf14"
        default: return "unknown"
        }
    }
}

struct BarcodeCandidateGate {
    private(set) var hasDelivered = false
    mutating func accept(_ candidates: [BarcodeCandidate]) -> [BarcodeCandidate]? {
        guard !hasDelivered else { return nil }
        let unique = Array(Set(candidates.filter { !$0.barcode.isEmpty })).sorted { $0.id < $1.id }
        guard !unique.isEmpty else { return nil }
        hasDelivered = true
        return unique
    }
    mutating func reset() { hasDelivered = false }
}

enum ScannerGeometry {
    static let targetSize = CGSize(width: 290, height: 170)
    static let fullFrameRegion = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func targetRect(in bounds: CGRect) -> CGRect {
        let width = min(targetSize.width, bounds.width)
        let height = min(targetSize.height, bounds.height)
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }
}

extension View {
    func scannerMessageStyle() -> some View {
        padding(.vertical, 4)
    }

    func scannerPanelStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}
