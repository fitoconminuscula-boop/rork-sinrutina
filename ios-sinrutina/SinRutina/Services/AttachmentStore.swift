import Foundation
import UniformTypeIdentifiers

/// Files the person attached to a task, kept inside the shared app group so the
/// share extension and the mail composer can reach the same bytes.
///
/// When the app group is not available — installs signed with a free Apple ID —
/// the files live in the app's own storage instead. Attachments still work; only
/// the share extension cannot reach them.
///
/// Nothing is uploaded anywhere. Deleting a task never deletes its files silently:
/// removal is always an explicit call.
nonisolated enum AttachmentStore {
    private static let folderName = "Adjuntos"

    /// True when attachments are readable by the share extension too.
    static var isShared: Bool { SRShared.hasSharedContainer }

    static var folderURL: URL? {
        guard let base = SRShared.sharedContainerURL ?? ownContainerURL else { return nil }
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// The app's private storage, used when there is no shared container.
    private static var ownContainerURL: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    static func url(for fileName: String) -> URL? {
        folderURL?.appendingPathComponent(fileName, isDirectory: false)
    }

    static func exists(_ fileName: String) -> Bool {
        guard let url = url(for: fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Copies an external file in and returns the stored name.
    @discardableResult
    static func store(from source: URL) throws -> String {
        guard let folder = folderURL else { throw AttachmentError.noContainer }
        let name = uniqueName(for: source.lastPathComponent)
        let destination = folder.appendingPathComponent(name, isDirectory: false)

        // Security-scoped resources arrive from the document picker.
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return name
    }

    @discardableResult
    static func store(data: Data, suggestedName: String) throws -> String {
        guard let folder = folderURL else { throw AttachmentError.noContainer }
        let name = uniqueName(for: suggestedName)
        try data.write(to: folder.appendingPathComponent(name, isDirectory: false), options: .atomic)
        return name
    }

    static func remove(_ fileName: String) {
        guard let url = url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func data(for fileName: String) -> Data? {
        guard let url = url(for: fileName) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func mimeType(for fileName: String) -> String {
        let extensionValue = (fileName as NSString).pathExtension
        if let type = UTType(filenameExtension: extensionValue),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    static func sizeLabel(for fileName: String) -> String? {
        guard let url = url(for: fileName),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private static func uniqueName(for suggested: String) -> String {
        let base = suggested.isEmpty ? "adjunto" : suggested
        let sanitized = base
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "|", with: "-")
        guard exists(sanitized) else { return sanitized }
        let name = (sanitized as NSString).deletingPathExtension
        let extensionValue = (sanitized as NSString).pathExtension
        let stamp = Int(Date().timeIntervalSince1970)
        return extensionValue.isEmpty ? "\(name)-\(stamp)" : "\(name)-\(stamp).\(extensionValue)"
    }
}

nonisolated enum AttachmentError: LocalizedError {
    case noContainer
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noContainer: return "No se pudo acceder al almacenamiento de la app."
        case .unreadable: return "No se pudo leer el archivo."
        }
    }
}
