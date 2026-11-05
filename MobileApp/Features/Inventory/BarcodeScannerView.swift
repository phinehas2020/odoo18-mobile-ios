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

                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 16) {
                            cameraMessage
                            Spacer(minLength: 24)
                            resultPanel
                        }
                        .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 32), alignment: .bottom)
                        .padding(16)
                    }.scrollBounceBehavior(.basedOnSize)
                }
            }
            .background(Color.black)
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
            Text("Place one barcode inside the frame. Detection will pause for confirmation.")
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
        RoundedRectangle(cornerRadius: 18)
            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, dash: [18, 10]))
            .frame(width: ScannerGeometry.targetSize.width, height: ScannerGeometry.targetSize.height)
            .shadow(color: .black.opacity(0.7), radius: 4)
            .accessibilityHidden(true)
    }
}

enum ScannerCameraState: Equatable {
    case checkingPermission, requestingPermission, ready, denied, unavailable, failed
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

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: (([BarcodeCandidate]) -> Void)?
    var onStateChange: ((ScannerCameraState) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.homestead.mobile.barcode-camera")
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var detectionGate = BarcodeCandidateGate()
    private var metadataOutput: AVCaptureMetadataOutput?
    private var videoInputPort: AVCaptureInput.Port?
    private var previewObservation: NSKeyValueObservation?
    private var captureObservers: [NSObjectProtocol] = []
    private var configured = false
    private var isVisible = false
    private var wantsScanning = true
    private var generation = -1
    private let supportedTypes: [AVMetadataObject.ObjectType] = [.ean8, .ean13, .qr, .code128, .code39, .upce, .pdf417, .dataMatrix, .aztec, .interleaved2of5, .itf14]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        previewObservation = previewLayer.observe(\.isPreviewing, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.capturePreviewDidChange() }
        }
        captureObservers.append(NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionDidStartRunning, object: session, queue: .main
        ) { [weak self] _ in self?.capturePreviewDidChange() })
        captureObservers.append(NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError, object: session, queue: .main
        ) { [weak self] notification in
            guard let self, self.isVisible else { return }
            self.onStateChange?(.failed)
            #if DEBUG
            if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError {
                print("[scanner] capture failed domain=\(error.domain) code=\(error.code)")
            }
            #endif
        })
        prepareCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        updateSessionRunningState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        updateRegionOfInterest()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    deinit {
        previewObservation?.invalidate()
        for observer in captureObservers { NotificationCenter.default.removeObserver(observer) }
    }

    func setScanning(_ enabled: Bool, generation: Int) {
        wantsScanning = enabled
        if self.generation != generation {
            self.generation = generation
            detectionGate.reset()
        }
        updateSessionRunningState()
    }

    private func prepareCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCamera()
        case .notDetermined:
            onStateChange?(.requestingPermission)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self else { return }
                    allowed ? self.configureCamera() : self.onStateChange?(.denied)
                }
            }
        case .denied, .restricted:
            onStateChange?(.denied)
        @unknown default:
            onStateChange?(.failed)
        }
    }

    private func configureCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            onStateChange?(.unavailable)
            return
        }
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            onStateChange?(.failed)
            return
        }
        let output = AVCaptureMetadataOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            onStateChange?(.failed)
            return
        }
        session.beginConfiguration()
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.rectOfInterest = ScannerGeometry.fullFrameRegion
        metadataOutput = output
        videoInputPort = input.ports.first(where: { $0.mediaType == .video })
        if let videoInputPort {
            captureObservers.append(NotificationCenter.default.addObserver(
                forName: .AVCaptureInputPortFormatDescriptionDidChange, object: videoInputPort, queue: .main
            ) { [weak self] _ in self?.capturePreviewDidChange() })
        }
        session.commitConfiguration()
        configureMetadataTypes()
        previewLayer.session = session
        configured = true
        updateSessionRunningState()
    }

    private func updateSessionRunningState() {
        guard configured else { return }
        let shouldRun = wantsScanning && isVisible
        sessionQueue.async { [weak self, session] in
            if shouldRun, !session.isRunning {
                session.startRunning()
                DispatchQueue.main.async { self?.capturePreviewDidChange() }
            } else if !shouldRun, session.isRunning {
                session.stopRunning()
            }
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard wantsScanning, isVisible else { return }
        let candidates = metadataObjects.compactMap { object -> BarcodeCandidate? in
            guard let code = object as? AVMetadataMachineReadableCodeObject,
                  let barcode = code.stringValue, !barcode.isEmpty else { return nil }
            return BarcodeCandidate(barcode: barcode, symbology: Self.symbology(code.type))
        }
        guard let accepted = detectionGate.accept(candidates) else { return }
        #if DEBUG
        print("[scanner] detected candidates=\(accepted.count) types=\(accepted.map(\.symbology).joined(separator: ","))")
        #endif
        wantsScanning = false
        updateSessionRunningState()
        onFound?(accepted)
    }
    private func capturePreviewDidChange() {
        guard configured, isVisible, session.isRunning else { return }
        configureMetadataTypes()
        updateRegionOfInterest()
        if previewLayer.isPreviewing, metadataOutput?.metadataObjectTypes.isEmpty == false { onStateChange?(.ready) }
    }

    private func configureMetadataTypes() {
        guard let metadataOutput else { return }
        // Capabilities belong to the connected input port. Read them after the
        // configuration commits, and again when that port starts delivering video.
        let types = supportedTypes.filter { metadataOutput.availableMetadataObjectTypes.contains($0) }
        if metadataOutput.metadataObjectTypes != types { metadataOutput.metadataObjectTypes = types }
    }

    private func updateRegionOfInterest() {
        guard configured, let metadataOutput else { return }
        let dimensions: CGSize
        if let format = videoInputPort?.formatDescription {
            let video = CMVideoFormatDescriptionGetDimensions(format)
            dimensions = CGSize(width: CGFloat(video.width), height: CGFloat(video.height))
        } else {
            dimensions = .zero
        }
        // Converting before capture has established its preview transform can
        // produce an empty ROI (and a singular-matrix warning), suppressing all codes.
        guard ScannerGeometry.canConvertRegion(
            viewBounds: view.bounds, previewBounds: previewLayer.bounds,
            videoDimensions: dimensions, sessionRunning: session.isRunning,
            previewing: previewLayer.isPreviewing
        ) else {
            metadataOutput.rectOfInterest = ScannerGeometry.fullFrameRegion
            return
        }
        let target = ScannerGeometry.targetRect(in: view.bounds)
        let converted = previewLayer.metadataOutputRectConverted(fromLayerRect: target)
        let region = ScannerGeometry.validatedRegion(converted)
        if metadataOutput.rectOfInterest != region {
            metadataOutput.rectOfInterest = region
            #if DEBUG
            print("[scanner] preview ready region=\(region) video=\(Int(dimensions.width))x\(Int(dimensions.height))")
            #endif
        }
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

    static func canConvertRegion(viewBounds: CGRect, previewBounds: CGRect, videoDimensions: CGSize,
                                 sessionRunning: Bool, previewing: Bool) -> Bool {
        sessionRunning && previewing && validArea(viewBounds) && validArea(previewBounds) &&
        videoDimensions.width.isFinite && videoDimensions.height.isFinite &&
        videoDimensions.width > 0 && videoDimensions.height > 0
    }

    static func validatedRegion(_ converted: CGRect) -> CGRect {
        guard validArea(converted) else { return fullFrameRegion }
        let clipped = converted.intersection(fullFrameRegion)
        return validArea(clipped) ? clipped : fullFrameRegion
    }

    private static func validArea(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite &&
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite) &&
        rect.size.width > 0 && rect.size.height > 0
    }
    static func targetRect(in bounds: CGRect) -> CGRect {
        let width = min(targetSize.width, bounds.width)
        let height = min(targetSize.height, bounds.height)
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }
}

extension View {
    func scannerMessageStyle() -> some View {
        padding(12)
            .foregroundStyle(.white)
            .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 12))
    }

    func scannerPanelStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
