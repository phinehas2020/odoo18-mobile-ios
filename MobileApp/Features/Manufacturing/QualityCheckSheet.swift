import SwiftUI
import PhotosUI
import UIKit

struct QualityCheckSheet: View {
    let check: ManufacturingQualityCheck
    let save: (Bool, String, Data?) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""
    @State private var busy = false
    @State private var submitted = false
    @State private var errorMessage: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showCamera = false
    @State private var confirmFailure = false
    private var supported: Bool { ["instructions", "passfail", "picture"].contains(check.controlType ?? "") }
    private var needsPhoto: Bool { check.controlType == "picture" }
    private var instructionsOnly: Bool { check.controlType == "instructions" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(check.name).font(.title2.bold())
                    if let instructions = check.instructions, !instructions.isEmpty {
                        Text(instructions).textSelection(.enabled)
                    }
                }
                if needsPhoto {
                    Section("Required photo") {
                        if let photoData, let image = UIImage(data: photoData) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).accessibilityLabel("Selected inspection photo")
                        }
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: { Label("Take photo", systemImage: "camera").frame(minHeight: 48) }
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Choose photo", systemImage: "photo").frame(minHeight: 48)
                        }
                    }
                }
                Section("Inspection notes") {
                    TextField("What did you check?", text: $notes, axis: .vertical).lineLimit(3...8)
                    Text("Record the actual inspection result. This updates Odoo.").font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                if !supported {
                    Text("This check requires a control that is not available here. Complete it in Odoo.").foregroundStyle(.secondary)
                }
                Section {
                    Button { submit(true) } label: {
                        Label(instructionsOnly ? "Confirm instructions completed" : needsPhoto ? "Save photo and pass" : "Pass check", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity, minHeight: 52)
                    }.buttonStyle(.borderedProminent)
                        .disabled(needsPhoto && photoData == nil)
                    if check.controlType == "passfail" || check.controlType == nil {
                        Button { confirmFailure = true } label: {
                            Label("Fail check", systemImage: "xmark.octagon").frame(maxWidth: .infinity, minHeight: 52)
                        }.buttonStyle(.bordered)
                    }
                }
                .disabled(!supported)
                if busy { ProgressView("Saving inspection…") }
            }
            .disabled(busy || submitted)
            .navigationTitle("Quality check")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .confirmationDialog("Record a failed inspection?", isPresented: $confirmFailure, titleVisibility: .visible) {
                Button("Record failure", role: .destructive) { submit(false) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(check.failureAction == "block" ? "This failure blocks production completion until the check is resolved." : "This records a failed quality check in Odoo.")
            }
            .sheet(isPresented: $showCamera) {
                InspectionCamera { image in
                    photoData = inspectionJPEG(image)
                    showCamera = false
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        errorMessage = "Couldn’t open this photo. Choose another image."; return
                    }
                    photoData = inspectionJPEG(image)
                }
            }
        }
    }
    private func submit(_ passed: Bool) {
        guard !busy, !submitted, notes.count <= 2000, !needsPhoto || photoData != nil else { return }
        busy = true; submitted = true
        Task {
            let success = await save(passed, notes, photoData)
            busy = false
            if success { dismiss() }
            else { errorMessage = "The result could not be confirmed. Close and refresh the order before trying again." }
        }
    }
}

private func inspectionJPEG(_ image: UIImage) -> Data? {
    guard image.size.width > 0, image.size.height > 0 else { return nil }
    let scale = min(1, 1600 / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    // Re-render only pixels; don't upload location or other source-image metadata.
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }.jpegData(compressionQuality: 0.8)
}

private struct InspectionCamera: UIViewControllerRepresentable {
    let captured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let owner: InspectionCamera
        init(_ owner: InspectionCamera) { self.owner = owner }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { owner.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { owner.captured(image) }
            owner.dismiss()
        }
    }
}
