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
    @State private var showDiscardConfirmation = false
    @FocusState private var notesFocused: Bool
    private var supported: Bool { ["instructions", "passfail", "picture"].contains(check.controlType ?? "") }
    private var needsPhoto: Bool { check.controlType == "picture" }
    private var instructionsOnly: Bool { check.controlType == "instructions" }
    private var hasUnsavedChanges: Bool { !submitted && (!notes.isEmpty || photoData != nil) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WorkplaceHeader(title: check.name,
                                    subtitle: instructionsOnly ? "Read the instructions, then confirm the check is complete." : needsPhoto ? "Inspect the product and attach a photo of the result." : "Inspect the product and record the actual result.",
                                    symbol: "checkmark.shield")
                    if check.failureAction == "block" {
                        Label("A failed check blocks production completion.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let instructions = check.instructions, !instructions.isEmpty {
                    Section("Inspection Instructions") {
                        QualityInstructionsView(source: instructions)
                    }
                }
                if needsPhoto {
                    Section("Required Photo") {
                        if let photoData, let image = UIImage(data: photoData) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Selected inspection photo")
                            WorkplaceStatusPill(text: "Photo attached", symbol: "checkmark.circle.fill", tint: WorkplaceTheme.success)
                        }
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: {
                                WorkplaceActionLabel(title: "Take photo", subtitle: "Capture this inspection", symbol: "camera")
                            }.accessibilityLabel("Take inspection photo for \(check.name)")
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            WorkplaceActionLabel(title: "Choose photo", subtitle: "Use an existing inspection photo", symbol: "photo")
                        }.accessibilityLabel("Choose inspection photo for \(check.name)")
                    }
                }
                Section("Inspection Notes") {
                    TextField("What did you check?", text: $notes, axis: .vertical).lineLimit(3...8)
                        .padding(.vertical, 6).focused($notesFocused)
                        .accessibilityLabel("Inspection notes for \(check.name)")
                    Text("Record the actual inspection result. This updates Odoo.").font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage {
                    WorkplaceNotice(title: "Inspection needs attention", message: errorMessage, symbol: "exclamationmark.triangle", tint: WorkplaceTheme.danger)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)).listRowBackground(Color.clear)
                }
                if !supported {
                    WorkplaceNotice(title: "Complete this check in Odoo", message: "This check requires a control that is not available here. Complete it in Odoo.", symbol: "arrow.up.right.square")
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)).listRowBackground(Color.clear)
                }
                Section("Record Inspection") {
                    Button { submit(true) } label: {
                        Label(instructionsOnly ? "Confirm complete" : needsPhoto ? "Save and pass" : "Pass check", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(WorkplaceTheme.buttonFill)
                    .controlSize(.large)
                    .accessibilityLabel(instructionsOnly ? "Confirm \(check.name) is complete" : needsPhoto ? "Save photo and pass \(check.name)" : "Pass \(check.name)")
                    .disabled(needsPhoto && photoData == nil)
                    if check.controlType == "passfail" || check.controlType == nil {
                        Button { confirmFailure = true } label: {
                            Label("Fail check", systemImage: "xmark.octagon")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(WorkplaceTheme.danger)
                        .accessibilityLabel("Record a failed inspection for \(check.name)")
                    }
                }
                .disabled(!supported)
                if busy { ProgressView("Saving inspection…").frame(maxWidth: .infinity).padding(.vertical, 12) }
            }
            .workplaceScreen()
            .disabled(busy || submitted)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Quality Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if submitted {
                        if #available(iOS 26, *) {
                            Button(role: .close) { dismiss() }.disabled(busy)
                        } else {
                            Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                                .labelStyle(.iconOnly).disabled(busy)
                        }
                    } else {
                        Button("Cancel", role: .cancel) { requestDismiss() }.disabled(busy)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { notesFocused = false }
                }
            }
            .interactiveDismissDisabled(busy || hasUnsavedChanges)
            .confirmationDialog("Discard Inspection Draft?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("The inspection notes and photo you added will be lost.")
            }
            .confirmationDialog("Record a failed inspection?", isPresented: $confirmFailure, titleVisibility: .visible) {
                Button("Record failure", role: .destructive) { submit(false) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(check.failureAction == "block" ? "This failure blocks production completion until the check is resolved." : "This records a failed quality check in Odoo.")
            }
            .fullScreenCover(isPresented: $showCamera) {
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
    private func requestDismiss() {
        notesFocused = false
        if hasUnsavedChanges { showDiscardConfirmation = true }
        else { dismiss() }
    }
    private func submit(_ passed: Bool) {
        guard !busy, !submitted, notes.count <= 2000, !needsPhoto || photoData != nil else { return }
        notesFocused = false
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
