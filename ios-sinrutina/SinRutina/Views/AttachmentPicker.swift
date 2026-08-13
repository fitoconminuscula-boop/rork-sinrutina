import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

/// What SinRutina accepts as an attachment. `.item` at the end keeps the picker
/// open to anything else the person actually has, instead of refusing a file
/// because we did not think of its format.
nonisolated enum SRAttachmentKinds {
    static let allowed: [UTType] = {
        var types: [UTType] = [.pdf, .image, .plainText, .rtf, .text, .spreadsheet, .presentation, .audio, .movie, .zip]
        for value in ["doc", "docx", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "key", "epub", "csv"] {
            if let type = UTType(filenameExtension: value) { types.append(type) }
        }
        types.append(.item)
        return types
    }()

    /// A recognisable symbol per format, so a list of files can be read at a glance.
    static func symbol(for fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "doc", "docx", "pages", "rtf", "txt", "md": return "doc.text"
        case "xls", "xlsx", "numbers", "csv": return "tablecells"
        case "ppt", "pptx", "key": return "rectangle.on.rectangle"
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp": return "photo"
        case "mp3", "m4a", "wav", "aac": return "waveform"
        case "mov", "mp4", "m4v": return "film"
        case "zip": return "doc.zipper"
        default: return "paperclip"
        }
    }
}

/// Copies picked files and photos into the app group, off the main actor where
/// possible, and reports the stored names back.
nonisolated enum SRAttachmentIntake {
    static func store(files urls: [URL]) -> (names: [String], failures: Int) {
        var names: [String] = []
        var failures = 0
        for url in urls {
            do {
                names.append(try AttachmentStore.store(from: url))
            } catch {
                failures += 1
            }
        }
        return (names, failures)
    }

    static func store(photo data: Data, index: Int) throws -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        let suffix = index == 0 ? "" : "-\(index + 1)"
        return try AttachmentStore.store(data: data, suggestedName: "Foto-\(stamp)\(suffix).jpg")
    }
}

/// The one attach control in the app: files, photos, anything.
///
/// It only stores bytes on this iPhone and hands back the names. Nothing is
/// uploaded, and nothing is read or interpreted unless the person asks for it.
struct SRAttachButton: View {
    var label: String = "Adjuntar"
    var isCompact: Bool = false
    let onAttached: ([String]) -> Void

    @State private var showsFileImporter = false
    @State private var showsPhotoPicker = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                Button {
                    showsFileImporter = true
                    SRHaptics.light()
                } label: {
                    Label("Archivos", systemImage: "folder")
                }
                Button {
                    showsPhotoPicker = true
                    SRHaptics.light()
                } label: {
                    Label("Fotos", systemImage: "photo.on.rectangle")
                }
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().controlSize(.mini).tint(SRDesign.primary)
                    } else {
                        Image(systemName: "paperclip")
                            .font(.system(size: isCompact ? 13 : 15, weight: .semibold))
                    }
                    Text(label)
                        .font(isCompact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(SRDesign.primary)
                .padding(.horizontal, isCompact ? 14 : 18)
                .padding(.vertical, isCompact ? 10 : 13)
                .srGlassCapsule()
            }
            .disabled(isWorking)
            .accessibilityLabel("Adjuntar archivos o fotos")
            .accessibilityHint("PDF, Word, imágenes u otros archivos. Se guardan en este iPhone.")

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(SRDesign.blush)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: SRAttachmentKinds.allowed,
            allowsMultipleSelection: true
        ) { result in
            handleFiles(result)
        }
        .photosPicker(
            isPresented: $showsPhotoPicker,
            selection: $photoSelection,
            maxSelectionCount: 6,
            matching: .images
        )
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            Task { await handlePhotos(items) }
        }
        .animation(SRDesign.quickAnimation, value: errorMessage)
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            errorMessage = nil
            let outcome = SRAttachmentIntake.store(files: urls)
            if !outcome.names.isEmpty {
                onAttached(outcome.names)
                SRHaptics.success()
            }
            if outcome.failures > 0 {
                errorMessage = outcome.failures == 1
                    ? "Un archivo no se pudo copiar."
                    : "\(outcome.failures) archivos no se pudieron copiar."
            }
        case .failure:
            errorMessage = "No se pudo abrir el selector de archivos."
        }
    }

    private func handlePhotos(_ items: [PhotosPickerItem]) async {
        isWorking = true
        errorMessage = nil
        var names: [String] = []
        var failures = 0
        for (index, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failures += 1
                    continue
                }
                names.append(try SRAttachmentIntake.store(photo: data, index: index))
            } catch {
                failures += 1
            }
        }
        photoSelection = []
        isWorking = false
        if !names.isEmpty {
            onAttached(names)
            SRHaptics.success()
        }
        if failures > 0 {
            errorMessage = "No se pudo guardar \(failures == 1 ? "una imagen" : "\(failures) imágenes")."
        }
    }
}

/// Attached files as removable chips. Tapping one opens it in Quick Look, so a PDF
/// can be checked without leaving the task.
struct SRAttachmentChips: View {
    let names: [String]
    var onRemove: ((String) -> Void)?

    @State private var previewURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(names, id: \.self) { name in
                HStack(spacing: 10) {
                    Image(systemName: SRAttachmentKinds.symbol(for: name))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SRDesign.primary)
                        .frame(width: 22)

                    Button {
                        previewURL = AttachmentStore.url(for: name)
                        SRHaptics.light()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(SRDesign.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let size = AttachmentStore.sizeLabel(for: name) {
                                Text(size)
                                    .font(.caption2)
                                    .foregroundStyle(SRDesign.secondaryInk)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(SRPressStyle())
                    .accessibilityLabel("Abrir \(name)")

                    if let onRemove {
                        Button {
                            withAnimation(SRDesign.quickAnimation) { onRemove(name) }
                            SRHaptics.light()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(SRDesign.secondaryInk)
                                .frame(width: 30, height: 30)
                                .contentShape(.rect)
                        }
                        .buttonStyle(SRPressStyle())
                        .accessibilityLabel("Quitar \(name)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(SRDesign.primarySoft.opacity(0.5))
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
            }
        }
        .quickLookPreview($previewURL)
    }
}
