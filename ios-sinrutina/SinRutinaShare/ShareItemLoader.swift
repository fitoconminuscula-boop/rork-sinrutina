import Foundation
import UniformTypeIdentifiers
import UIKit

/// Everything SinRutina could read from what was shared.
struct SRSharedPayload: Sendable {
    var text: String = ""
    var url: String?
    var attachmentName: String?
    var sourceApp: String?

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && url == nil && attachmentName == nil
    }

    /// What the intelligence layer should read.
    var readableText: String {
        var parts: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }
        if let attachmentName { parts.append(attachmentName) }
        if let url, trimmed.isEmpty { parts.append(url) }
        return parts.joined(separator: "\n")
    }
}

/// Pulls text, links, images and documents out of the share sheet.
/// SinRutina only ever reads what the person handed over — it never goes looking
/// inside WhatsApp, Mail or any other app.
enum ShareItemLoader {
    static func load(from context: NSExtensionContext?) async -> SRSharedPayload {
        var payload = SRSharedPayload()
        guard let items = context?.inputItems as? [NSExtensionItem] else { return payload }

        for item in items {
            if let attributed = item.attributedContentText?.string, !attributed.isEmpty {
                payload.text = append(attributed, to: payload.text)
            }
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(from: provider) {
                        payload.url = url.absoluteString
                        if payload.text.isEmpty {
                            payload.text = append(url.absoluteString, to: payload.text)
                        }
                        continue
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadText(from: provider) {
                        payload.text = append(text, to: payload.text)
                        continue
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    payload.attachmentName = payload.attachmentName ?? "Imagen compartida"
                    continue
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    payload.attachmentName = payload.attachmentName ?? "Documento PDF"
                    continue
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let url = await loadURL(from: provider) {
                        payload.attachmentName = payload.attachmentName ?? url.lastPathComponent
                    }
                }
            }
        }
        return payload
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private static func append(_ addition: String, to existing: String) -> String {
        let trimmed = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return existing }
        guard !existing.isEmpty else { return trimmed }
        guard !existing.contains(trimmed) else { return existing }
        return existing + "\n" + trimmed
    }
}
