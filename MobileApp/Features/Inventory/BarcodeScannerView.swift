import AVFoundation
import SwiftUI

struct BarcodeScannerView: View {
    let onConfirm: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var detectedCode: String?
    @State private var confirmedCode: String?
    @State private var cameraState: ScannerCameraState = .checkingPermission
    @State private var scanGeneration = 0
    @State private var isSubmitting = false
    @State private var submissionError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ScannerCameraView(
                    isScanning: detectedCode == nil && confirmedCode == nil,
                    generation: scanGeneration,
                    onFound: { code in
                        guard detectedCode == nil, confirmedCode == nil else { return }
                        detectedCode = code
                    },
                    onStateChange: { cameraState = $0 }
                )
                .ignoresSafeArea()

                if cameraState == .ready && confirmedCode == nil {
                    ScannerTarget()
                }

                VStack {
                    cameraMessage
                    Spacer()
                    resultPanel
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
                HStack {
                    Button("Scan next") { resetForNextScan() }.buttonStyle(.borderedProminent)
                    Button("Done") { dismiss() }.buttonStyle(.bordered)
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
                HStack {
                    Button("Confirm code") {
                        submit(detectedCode)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)
                    Button("Try again") { resetForNextScan() }.buttonStyle(.bordered)
                        .disabled(isSubmitting)
                }
            }
            .scannerPanelStyle()
        } else if cameraState == .ready {
            Text("Place one barcode inside the frame. Detection will pause for confirmation.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .scannerPanelStyle()
        }
    }

    private func resetForNextScan() {
        detectedCode = nil
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

private struct ScannerTarget: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, dash: [18, 10]))
            .frame(width: 290, height: 170)
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

private struct ScannerCameraView: UIViewControllerRepresentable {
    let isScanning: Bool
    let generation: Int
    let onFound: (String) -> Void
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

private final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?
    var onStateChange: ((ScannerCameraState) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.homestead.mobile.barcode-camera")
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var detectionGate = BarcodeDetectionGate()
    private var configured = false
    private var wantsScanning = true
    private var generation = -1

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        prepareCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
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
        guard let device = AVCaptureDevice.default(for: .video) else {
            onStateChange?(.unavailable)
            return
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
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .qr, .code128, .code39, .upce]
        session.commitConfiguration()
        previewLayer.session = session
        configured = true
        onStateChange?(.ready)
        updateSessionRunningState()
    }

    private func updateSessionRunningState() {
        guard configured else { return }
        let shouldRun = wantsScanning
        sessionQueue.async { [session] in
            if shouldRun, !session.isRunning {
                session.startRunning()
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
        guard wantsScanning,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = detectionGate.accept(object.stringValue) else { return }
        wantsScanning = false
        updateSessionRunningState()
        onFound?(value)
    }
}

private extension View {
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
